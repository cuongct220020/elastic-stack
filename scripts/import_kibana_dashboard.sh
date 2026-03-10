#!/usr/bin/env bash
# scripts/import_kibana_dashboard.sh
# Imports a saved NDJSON dashboard into Kibana.
# Usage: bash scripts/import_kibana_dashboard.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"
DASHBOARD_FILE="$ROOT_DIR/assets/kibana/dashboards/demo-audit-logs-dashboard.ndjson"

# Extract credentials
ELASTIC_PASSWORD=$(grep "^ELASTIC_PASSWORD=" "$ENV_FILE" | cut -d= -f2 | tr -d '"')

echo "==========================================================" 
echo "      IMPORTING KIBANA DASHBOARD" 
echo "=========================================================="

if [ ! -f "$DASHBOARD_FILE" ]; then
  echo "ERROR: Dashboard file not found at $DASHBOARD_FILE"
  exit 1
fi

echo "Copying dashboard file into Kibana container..."
docker cp "$DASHBOARD_FILE" kibana:/tmp/dashboard.ndjson

echo "Executing import via Kibana API..."
RESPONSE=$(docker exec kibana bash -c '
  PROTO="http"
  AUTH=""
  
  # Check if Kibana is using HTTPS (Multi-node / Prod setup) or HTTP (Single node / Dev)
  if curl -sk "https://localhost:5601/api/status" > /dev/null 2>&1; then
      PROTO="https"
      AUTH="-u elastic:'"${ELASTIC_PASSWORD}"'"
  fi
  
  curl -sk -X POST "${PROTO}://localhost:5601/api/saved_objects/_import?overwrite=true" \
      ${AUTH} \
      -H "kbn-xsrf: true" \
      --form file=@/tmp/dashboard.ndjson
')

# Clean up
docker exec kibana rm -f /tmp/dashboard.ndjson

if echo "$RESPONSE" | grep -q '"success":true'; then
    echo "SUCCESS: Dashboard imported successfully!"
    echo "Check Kibana > Stack Management > Saved Objects"
else
    echo "FAILED to import dashboard."
    echo "Response: $RESPONSE"
    exit 1
fi

echo "=========================================================="
