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

BASE_URL="https://localhost:9200/_security/service/elastic/fleet-server/credential/token/$TOKEN_NAME"

echo "Deleting existing token '$TOKEN_NAME'..."
docker exec es-01 curl -sk -X DELETE \
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  "$BASE_URL" -o /dev/null

echo "Creating new token '$TOKEN_NAME'..."
RESPONSE=$(docker exec es-01 curl -sk -X POST \
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  "$BASE_URL")

# Parse token value directly using sed/grep (no python3 needed)
TOKEN_VALUE=$(echo "$RESPONSE" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)

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