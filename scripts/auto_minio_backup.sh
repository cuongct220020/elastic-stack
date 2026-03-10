#!/usr/bin/env bash
# auto_minio_backup.sh
# Automates verifying the MinIO snapshot repository, taking a manual snapshot,
# and setting up a Snapshot Lifecycle Management (SLM) policy using SSL/TLS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

# Extract credentials
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

ELASTIC_PASSWORD=$(grep "^ELASTIC_PASSWORD=" "$ENV_FILE" | cut -d= -f2 | tr -d '"')

# Define target container and connection string (Using SSL/TLS)
# Defaulting to es-01 for multi-node setup
NODE="es-01"
if ! docker ps --format '{{.Names}}' | grep -q "^${NODE}$" ; then
    # Fallback to single node container name if es-01 is not running
    NODE="elasticsearch"
fi

ES_URL="https://localhost:9200"
AUTH="-u elastic:${ELASTIC_PASSWORD} --cacert config/certs/ca/ca.crt"
REPO_NAME="minio-snapshots"

echo "==========================================================" 
echo "    VERIFYING & AUTOMATING MINIO BACKUP (SSL/TLS)" 
echo "    Target Node: $NODE" 
echo "========================================================="

# 1. Verify Repository
echo "1. Verifying Snapshot Repository '$REPO_NAME'..."
VERIFY_RES=$(docker exec -i "$NODE" curl -sk -X POST $AUTH "$ES_URL/_snapshot/$REPO_NAME/_verify" || echo "FAILED")

if echo "$VERIFY_RES" | grep -q '"nodes"'; then
    echo " -> SUCCESS: Repository verified successfully!"
else
    echo " -> FAILED: Cannot verify repository. Are you sure you registered it first?"
    echo "    Response: $VERIFY_RES"
    exit 1
fi

# 2. Take Manual Snapshot
echo ""
echo "2. Taking an initial manual snapshot (Backing up all indices)..."
SNAP_NAME="snapshot-$(date +%Y%m%d-%H%M%S)"
echo " -> Creating snapshot: $SNAP_NAME (this might take a few moments)..."

SNAP_PAYLOAD=$(cat <<EOF
{
  "indices": "*",
  "ignore_unavailable": true,
  "include_global_state": true
}
EOF
)

SNAP_RES=$(echo "$SNAP_PAYLOAD" | docker exec -i "$NODE" curl -sk -X PUT $AUTH "$ES_URL/_snapshot/$REPO_NAME/$SNAP_NAME?wait_for_completion=true" \
  -H "Content-Type: application/json" -d @-)

if echo "$SNAP_RES" | grep -q '"state":"SUCCESS"'; then
    echo " -> SUCCESS: Initial snapshot completed!"
else
    echo " -> WARNING: Snapshot may have failed or partially completed."
    echo "    Response: $SNAP_RES"
fi

# 3. Set up SLM (Snapshot Lifecycle Management)
echo ""
echo "3. Setting up Snapshot Lifecycle Management (SLM) Policy..."
# SLM runs daily at 1:30 AM UTC
SLM_PAYLOAD=$(cat <<EOF
{
  "schedule": "0 30 1 * * ?", 
  "name": "<daily-snap-{now/d}>",
  "repository": "$REPO_NAME",
  "config": {
    "indices": ["*"],
    "ignore_unavailable": true,
    "include_global_state": true
  },
  "retention": {
    "expire_after": "30d",
    "min_count": 5,
    "max_count": 50
  }
}
EOF
)

SLM_RES=$(echo "$SLM_PAYLOAD" | docker exec -i "$NODE" curl -sk -X PUT "$ES_URL/_slm/policy/daily-snapshots" \
    -H "Content-Type: application/json" -d @-)

if echo "$SLM_RES" | grep -q '"acknowledged":true'; then
    echo " -> SUCCESS: SLM Policy 'daily-snapshots' created."
    echo "    Backups will run automatically every day at 1:30 AM."
else
    echo " -> FAILED to create SLM policy."
    echo "    Response: $SLM_RES"
fi

echo "========================================================="
echo "Done!"
