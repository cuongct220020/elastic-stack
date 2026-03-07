#!/usr/bin/env bash
# get_agent_enrollment_token.sh
# Fetch the active enrollment token for General Agent Policy and update .env
# Usage: bash scripts/get_agent_enrollment_token.sh [--policy-id <id>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"
POLICY_ID="general-agent-policy"

# Parse optional --policy-id argument
while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy-id) POLICY_ID="$2"; shift 2 ;;
    *) echo "Usage: $0 [--policy-id <id>]" >&2; exit 1 ;;
  esac
done

ELASTIC_PASSWORD=$(grep ^ELASTIC_PASSWORD "$ENV_FILE" | cut -d= -f2)
if [ -z "$ELASTIC_PASSWORD" ]; then
  echo "ERROR: ELASTIC_PASSWORD not found in .env" >&2
  exit 1
fi

echo "Fetching enrollment token for policy: $POLICY_ID"

RESPONSE=$(docker exec kibana curl -sk \
  -u "elastic:${ELASTIC_PASSWORD}" \
  "https://kibana:5601/api/fleet/enrollment_api_keys" \
  -H "kbn-xsrf: true")

# Parse inside kibana container - no host python3 needed
TOKEN_VALUE=$(echo "$RESPONSE" | docker exec -i kibana \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('policy_id') == '${POLICY_ID}' and item.get('active'):
        print(item['api_key'])
        break
" 2>/dev/null)

if [ -z "$TOKEN_VALUE" ]; then
  echo "ERROR: No active token found for policy '$POLICY_ID'" >&2
  echo "Available policies:" >&2
  echo "$RESPONSE" | docker exec -i kibana \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    print(f\"  - {item.get('policy_id')} (active={item.get('active')})\")
" 2>/dev/null >&2
  exit 1
fi

# Update .env
if grep -q "^ELASTIC_AGENT_ENROLLMENT_TOKEN=" "$ENV_FILE"; then
  sed -i.bak "s|^ELASTIC_AGENT_ENROLLMENT_TOKEN=.*|ELASTIC_AGENT_ENROLLMENT_TOKEN=${TOKEN_VALUE}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
else
  echo "ELASTIC_AGENT_ENROLLMENT_TOKEN=${TOKEN_VALUE}" >> "$ENV_FILE"
fi

echo "Done. ELASTIC_AGENT_ENROLLMENT_TOKEN updated in .env"
echo "Token: ${TOKEN_VALUE:0:20}...(truncated)"