#!/usr/bin/env bash
# rotate_fleet_server_token.sh
# Delete and recreate the Fleet Server API-based service token, then update .env
# Usage: bash scripts/rotate_fleet_server_token.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"
TOKEN_NAME="fleet-token"

# Load password
ELASTIC_PASSWORD=$(grep ^ELASTIC_PASSWORD "$ENV_FILE" | cut -d= -f2)
if [ -z "$ELASTIC_PASSWORD" ]; then
  echo "ERROR: ELASTIC_PASSWORD not found in .env" >&2
  exit 1
fi

# Get CA path from running es-01 container
CA_PATH=$(docker inspect es-01 \
  --format='{{range .Mounts}}{{if eq .Destination "/usr/share/elasticsearch/config/certs"}}{{.Source}}{{end}}{{end}}')/ca/ca.crt

if [ ! -f "$CA_PATH" ]; then
  echo "ERROR: CA cert not found at $CA_PATH" >&2
  exit 1
fi

BASE_URL="https://localhost:9200/_security/service/elastic/fleet-server/credential/token/$TOKEN_NAME"
AUTH="-u elastic:${ELASTIC_PASSWORD} --cacert $CA_PATH"

echo "Deleting existing token '$TOKEN_NAME'..."
curl -sk $AUTH -X DELETE "$BASE_URL" -o /dev/null

echo "Creating new token '$TOKEN_NAME'..."
RESPONSE=$(curl -sk $AUTH -X POST "$BASE_URL")

# Parse value without python3 on host - use es-01 container
TOKEN_VALUE=$(echo "$RESPONSE" | docker exec -i es-01 \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d['token']['value'])" 2>/dev/null)

if [ -z "$TOKEN_VALUE" ]; then
  echo "ERROR: Failed to parse token value. Raw response:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

# Update .env
if grep -q "^FLEET_SERVER_SERVICE_TOKEN=" "$ENV_FILE"; then
  # macOS-compatible sed
  sed -i.bak "s|^FLEET_SERVER_SERVICE_TOKEN=.*|FLEET_SERVER_SERVICE_TOKEN=${TOKEN_VALUE}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
else
  echo "FLEET_SERVER_SERVICE_TOKEN=${TOKEN_VALUE}" >> "$ENV_FILE"
fi

echo "Done. FLEET_SERVER_SERVICE_TOKEN updated in .env"
echo "Token: ${TOKEN_VALUE:0:20}...(truncated)"