#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

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

echo "1. Injecting MinIO credentials into Elasticsearch Keystores..."
for NODE in es-01 es-02 es-03; do
  echo "  -> Injecting to $NODE..."
  docker exec -i "$NODE" /bin/bash -c "echo '$MINIO_ROOT_USER' | bin/elasticsearch-keystore add --stdin --force s3.client.default.access_key" >/dev/null 2>&1 || true
  docker exec -i "$NODE" /bin/bash -c "echo '$MINIO_ROOT_PASSWORD' | bin/elasticsearch-keystore add --stdin --force s3.client.default.secret_key" >/dev/null 2>&1 || true
done

echo "2. Reloading secure settings on Elasticsearch cluster..."
docker exec -i es-01 curl -sk -X POST $AUTH "$ES_URL/_nodes/reload_secure_settings" >/dev/null

echo "3. Registering repository '$REPO_NAME' via API..."
PAYLOAD=$(cat <<EOF
{
  "type": "s3",
  "settings": {
    "bucket": "es-snapshots-bucket",
    "endpoint": "minio:9000",
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