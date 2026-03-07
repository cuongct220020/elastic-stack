#!/usr/bin/env bash
# cleanup_offline_agents.sh
# Bulk unenroll all offline agents from Fleet
# Usage: bash scripts/cleanup_offline_agents.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

ELASTIC_PASSWORD=$(grep ^ELASTIC_PASSWORD "$ENV_FILE" | cut -d= -f2)
if [ -z "$ELASTIC_PASSWORD" ]; then
  echo "ERROR: ELASTIC_PASSWORD not found in .env" >&2
  exit 1
fi

echo "Unenrolling all offline agents..."

RESPONSE=$(docker exec kibana curl -sk -X POST \
  -u "elastic:${ELASTIC_PASSWORD}" \
  "https://kibana:5601/api/fleet/agents/bulk_unenroll" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{"agents": "status:offline", "revoke": true}')

echo "Response: $RESPONSE"
echo "Done."