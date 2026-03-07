#!/usr/bin/env bash
# check_health.sh
# Check health of all Elastic Stack services and verify Fleet token
# Usage: bash scripts/check_health.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}OK${NC}    $1"; }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC}  $1"; }

ELASTIC_PASSWORD=$(grep ^ELASTIC_PASSWORD "$ENV_FILE" | cut -d= -f2)
CA_PATH=$(docker inspect es-01 \
  --format='{{range .Mounts}}{{if eq .Destination "/usr/share/elasticsearch/config/certs"}}{{.Source}}{{end}}{{end}}')/ca/ca.crt

echo ""
echo "=== Container Health ==="
for NAME in es-01 es-02 es-03 kibana fleet-server; do
  STATUS=$(docker inspect "$NAME" --format='{{.State.Health.Status}}' 2>/dev/null || echo "not found")
  if [ "$STATUS" == "healthy" ]; then
    ok "$NAME ($STATUS)"
  elif [ "$STATUS" == "not found" ]; then
    warn "$NAME (not running)"
  else
    fail "$NAME ($STATUS)"
  fi
done

# Elastic agents (no fixed container name)
AGENT_COUNT=$(docker ps --filter "name=elastic-fleet-elastic-agent" --format "{{.Names}}" | wc -l | tr -d ' ')
if [ "$AGENT_COUNT" -gt 0 ]; then
  ok "elastic-agent x${AGENT_COUNT} (running)"
else
  warn "elastic-agent (not running)"
fi

echo ""
echo "=== Elasticsearch Cluster ==="
CLUSTER=$(docker exec es-01 curl -sf \
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  "https://localhost:9200/_cluster/health" 2>/dev/null || echo "")

if [ -n "$CLUSTER" ]; then
  STATUS=$(echo "$CLUSTER" | docker exec -i es-01 python3 -c \
    "import json,sys; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null)
  NODES=$(echo "$CLUSTER" | docker exec -i es-01 python3 -c \
    "import json,sys; d=json.load(sys.stdin); print(d.get('number_of_nodes',0))" 2>/dev/null)
  if [ "$STATUS" == "green" ] || [ "$STATUS" == "yellow" ]; then
    ok "Cluster status: $STATUS, nodes: $NODES"
  else
    fail "Cluster status: $STATUS, nodes: $NODES"
  fi
else
  fail "Cannot reach Elasticsearch"
fi

echo ""
echo "=== Fleet Server Token ==="
TOKEN=$(grep ^FLEET_SERVER_SERVICE_TOKEN "$ENV_FILE" | cut -d= -f2)
if [ -z "$TOKEN" ]; then
  fail "FLEET_SERVER_SERVICE_TOKEN not set in .env"
else
  AUTH_RESULT=$(curl -sk \
    --cacert "$CA_PATH" \
    -H "Authorization: Bearer $TOKEN" \
    "https://localhost:9200/_security/_authenticate" 2>/dev/null || echo "")

  if echo "$AUTH_RESULT" | grep -q "fleet-server"; then
    ok "Token is valid (API-based)"
  else
    fail "Token is invalid or expired — run: bash scripts/rotate_fleet_token.sh"
  fi

  # Check token type - warn if file-based
  CRED=$(curl -sk -u "elastic:${ELASTIC_PASSWORD}" --cacert "$CA_PATH" \
    "https://localhost:9200/_security/service/elastic/fleet-server/credential" 2>/dev/null || echo "")
  FILE_TOKENS=$(echo "$CRED" | docker exec -i es-01 python3 -c \
    "import json,sys; d=json.load(sys.stdin); print(len(d.get('nodes_credentials',{}).get('file_tokens',{})))" 2>/dev/null || echo "0")
  API_TOKENS=$(echo "$CRED" | docker exec -i es-01 python3 -c \
    "import json,sys; d=json.load(sys.stdin); print(len(d.get('tokens',{})))" 2>/dev/null || echo "0")

  if [ "$FILE_TOKENS" -gt 0 ]; then
    warn "File-based tokens detected ($FILE_TOKENS) — these only exist on one node and will cause 401 errors"
    warn "Run: bash scripts/rotate_fleet_token.sh"
  fi
  if [ "$API_TOKENS" -gt 0 ]; then
    ok "API-based tokens: $API_TOKENS (cluster-wide)"
  fi
fi

echo ""
echo "=== Fleet Agent Enrollment Token ==="
ENROLL_TOKEN=$(grep ^ELASTIC_AGENT_ENROLLMENT_TOKEN "$ENV_FILE" | cut -d= -f2)
if [ -z "$ENROLL_TOKEN" ]; then
  warn "ELASTIC_AGENT_ENROLLMENT_TOKEN not set in .env"
  warn "Run: bash scripts/get_enrollment_token.sh"
else
  ok "Token is set in .env"
fi

echo ""