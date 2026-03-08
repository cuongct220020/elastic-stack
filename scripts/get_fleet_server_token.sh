#!/usr/bin/env bash
# get_fleet_server_token.sh
# Create a new API-based Fleet Server service token and update .env
# This is a thin wrapper around rotate_fleet_token.sh for first-time setup.
#
# Usage:
#   bash scripts/get_fleet_server_token.sh
#   bash scripts/get_fleet_server_token.sh --token-name <name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"
TOKEN_NAME="fleet-token"

# Parse optional --token-name argument
while [[ $# -gt 0 ]]; do
  case "$1" in
    --token-name) TOKEN_NAME="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [--token-name <name>]"
      echo "  --token-name  Token name to create (default: fleet-token)"
      exit 0
      ;;
    *) echo "Unknown argument: $1. Use --help for usage." >&2; exit 1 ;;
  esac
done

ELASTIC_PASSWORD=$(grep ^ELASTIC_PASSWORD "$ENV_FILE" | cut -d= -f2)
[ -n "$ELASTIC_PASSWORD" ] || { echo "ERROR: ELASTIC_PASSWORD not found in .env" >&2; exit 1; }

BASE_URL="https://localhost:9200/_security/service/elastic/fleet-server/credential/token/$TOKEN_NAME"

echo "Creating API-based service token '$TOKEN_NAME'..."

# Try to create — if already exists, delete first then recreate
RESPONSE=$(docker exec es-01 curl -sk -X POST \
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  "$BASE_URL")

# Check for conflict (token already exists)
if echo "$RESPONSE" | grep -q "version_conflict"; then
  echo "Token '$TOKEN_NAME' already exists. Rotating..."
  docker exec es-01 curl -sk -X DELETE \
    --cacert config/certs/ca/ca.crt \
    -u "elastic:${ELASTIC_PASSWORD}" \
    "$BASE_URL" -o /dev/null

  RESPONSE=$(docker exec es-01 curl -sk -X POST \
    --cacert config/certs/ca/ca.crt \
    -u "elastic:${ELASTIC_PASSWORD}" \
    "$BASE_URL")
fi

# Parse token value directly using sed/grep
TOKEN_VALUE=$(echo "$RESPONSE" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)

[ -n "$TOKEN_VALUE" ] || { echo "ERROR: Failed to parse token. Response: $RESPONSE" >&2; exit 1; }

# Update .env
if grep -q "^FLEET_SERVER_SERVICE_TOKEN=" "$ENV_FILE"; then
  sed -i.bak "s|^FLEET_SERVER_SERVICE_TOKEN=.*|FLEET_SERVER_SERVICE_TOKEN=${TOKEN_VALUE}|" "$ENV_FILE" \
    && rm -f "${ENV_FILE}.bak"
else
  echo "FLEET_SERVER_SERVICE_TOKEN=${TOKEN_VALUE}" >> "$ENV_FILE"
fi

echo "Done. FLEET_SERVER_SERVICE_TOKEN updated in .env"
echo "Token: ${TOKEN_VALUE:0:20}...(truncated)"