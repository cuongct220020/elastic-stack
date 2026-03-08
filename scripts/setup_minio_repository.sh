#!/usr/bin/env bash
# setup_minio_repository.sh
# Registers the MinIO bucket as an S3 Snapshot Repository in Elasticsearch.
# This allows for manual backups (snapshots) and SLM (Snapshot Lifecycle Management),
# even if Searchable Snapshots (ILM) are disabled in the Basic license.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

# Extract credentials from .env
ELASTIC_PASSWORD=$(grep "^ELASTIC_PASSWORD=" "$ENV_FILE" | cut -d= -f2 | tr -d '"')
MINIO_ROOT_USER=$(grep "^MINIO_ROOT_USER=" "$ENV_FILE" | cut -d= -f2 | tr -d '"')
MINIO_ROOT_PASSWORD=$(grep "^MINIO_ROOT_PASSWORD=" "$ENV_FILE" | cut -d= -f2 | tr -d '"')

if [ -z "$ELASTIC_PASSWORD" ] || [ -z "$MINIO_ROOT_USER" ]; then
  echo "ERROR: Missing credentials in .env file" >&2
  exit 1
fi

ES_URL="https://localhost:9200"
AUTH="-u elastic:${ELASTIC_PASSWORD} --cacert config/certs/ca/ca.crt"
REPO_NAME="minio-snapshots"

echo "==========================================================" 
echo "      REGISTERING MINIO SNAPSHOT REPOSITORY"
echo "=========================================================="

# 1. We must inject the MinIO S3 credentials into the Elasticsearch Keystore securely.
# This must be done on ALL nodes in the cluster (es-01, es-02, es-03) before registering the repo.
echo "1. Injecting MinIO credentials into Elasticsearch Keystores..."
for NODE in es-01 es-02 es-03; do
  echo "  -> Injecting to $NODE..."
  # Use echo to pipe the credential into the interactive prompt of elasticsearch-keystore
  docker exec -i "$NODE" /bin/bash -c "echo '$MINIO_ROOT_USER' | bin/elasticsearch-keystore add --stdin s3.client.default.access_key" >/dev/null 2>&1 || true
  docker exec -i "$NODE" /bin/bash -c "echo '$MINIO_ROOT_PASSWORD' | bin/elasticsearch-keystore add --stdin s3.client.default.secret_key" >/dev/null 2>&1 || true
done

# Reload secure settings on all nodes so they pick up the new keystore values without restarting
echo "2. Reloading secure settings on Elasticsearch cluster..."
docker exec -i es-01 curl -sk -X POST $AUTH "$ES_URL/_nodes/reload_secure_settings" >/dev/null

# 3. Register the actual repository via REST API
echo "3. Registering repository '$REPO_NAME' via API..."

# Note: We must use path_style_access: true for MinIO. 
# We also ignore certificate validation (endpoint: https://minio:9000) if using self-signed certs.
PAYLOAD=$(cat <<EOF
{
  "type": "s3",
  "settings": {
    "bucket": "es-snapshots-bucket",
    "endpoint": "https://minio:9000",
    "protocol": "https",
    "path_style_access": "true",
    "max_restore_bytes_per_sec": "100mb",
    "max_snapshot_bytes_per_sec": "100mb"
  }
}
EOF
)

RESPONSE=$(echo "$PAYLOAD" | docker exec -i es-01 curl -sk -X PUT $AUTH "$ES_URL/_snapshot/$REPO_NAME" \
    -H "Content-Type: application/json" -d @-)

if echo "$RESPONSE" | grep -q '"acknowledged":true'; then
    echo "SUCCESS: MinIO repository registered successfully!"
else
    echo "FAILED to register repository."
    echo "Response: $RESPONSE"
    exit 1
fi

echo "=========================================================="
