#!/usr/bin/env bash
# setup_elastic_stack.sh
# Full automated deployment of Elastic Stack + Fleet Server + Elastic Agent
# Source of truth: DEPLOYMENT.md
#
# Usage:
#   bash setup_elastic_stack.sh              # full deploy
#   bash setup_elastic_stack.sh --rebuild    # full rebuild (images + volumes)
#   bash setup_elastic_stack.sh --fleet-only # redeploy fleet + agent only

set -euo pipefail

# ==============================================================================
# Config
# ==============================================================================
COMPOSE_STACK="elk-multi-node-cluster.yml"
COMPOSE_FLEET="fleet-compose.yml"
ENV_FILE=".env"
FLEET_TOKEN_NAME="fleet-token"
AGENT_POLICY_ID="general-agent-policy"
HEALTH_RETRIES=60
HEALTH_INTERVAL=10

# ==============================================================================
# Flags
# ==============================================================================
REBUILD=false
FLEET_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild)    REBUILD=true;     shift ;;
    --fleet-only) FLEET_ONLY=true;  shift ;;
    --help)
      echo "Usage: $0 [--rebuild] [--fleet-only]"
      echo "  --rebuild     Tear down everything, remove fleet-data volume, rebuild images"
      echo "  --fleet-only  Redeploy fleet-server and elastic-agent only"
      exit 0
      ;;
    *) echo "Unknown argument: $1. Use --help for usage." >&2; exit 1 ;;
  esac
done

# ==============================================================================
# Colors
# ==============================================================================
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_step()  { echo -e "\n${BLUE}==> $1${NC}"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# ==============================================================================
# Helpers
# ==============================================================================
wait_healthy() {
  local CONTAINER="$1"
  local LABEL="${2:-$1}"
  echo -n "    Waiting for $LABEL to be healthy"
  for i in $(seq 1 $HEALTH_RETRIES); do
    STATUS=$(docker inspect "$CONTAINER" --format='{{.State.Health.Status}}' 2>/dev/null || echo "missing")
    if [ "$STATUS" == "healthy" ]; then
      echo -e " ${GREEN}OK${NC}"
      return 0
    fi
    echo -n "."
    sleep $HEALTH_INTERVAL
  done
  echo ""
  log_error "$LABEL did not become healthy after $((HEALTH_RETRIES * HEALTH_INTERVAL))s"
}

update_env() {
  local KEY="$1"
  local VALUE="$2"
  if grep -q "^${KEY}=" "$ENV_FILE"; then
    sed -i.bak "s|^${KEY}=.*|${KEY}=${VALUE}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
  else
    echo "${KEY}=${VALUE}" >> "$ENV_FILE"
  fi
}

# ==============================================================================
# Pre-flight
# ==============================================================================
log_step "Pre-flight checks"

command -v docker >/dev/null 2>&1 || log_error "Docker is not installed."
docker compose version >/dev/null 2>&1 || log_error "Docker Compose plugin is not installed."

[ -f "$ENV_FILE" ] || log_error ".env file not found. Create it from .env.example first."

ELASTIC_PASSWORD=$(grep ^ELASTIC_PASSWORD "$ENV_FILE" | cut -d= -f2)
[n "$ELASTIC_PASSWORD" ] || log_error "ELASTIC_PASSWORD is not set in .env"

log_info "Ensuring external volumes exist..."
docker volume create app-logs >/dev/null 2>&1 || true

log_info "Prerequisites OK"

# ==============================================================================
# Phase 0: Teardown (if --rebuild or --fleet-only)
# ==============================================================================
if $REBUILD; then
  log_step "Teardown (--rebuild)"
  docker compose -f "$COMPOSE_FLEET" down 2>/dev/null || true
  docker compose -f "$COMPOSE_STACK" down 2>/dev/null || true
  docker volume rm fleet-data 2>/dev/null && log_info "Removed fleet-data volume" || true
fi

if $FLEET_ONLY; then
  log_step "Teardown fleet services (--fleet-only)"
  docker compose -f "$COMPOSE_FLEET" down 2>/dev/null || true
  docker volume rm fleet-data 2>/dev/null && log_info "Removed fleet-data volume" || true
fi

# ==============================================================================
# Phase 1: Core Stack
# ==============================================================================
if ! $FLEET_ONLY; then
  log_step "Phase 1: Core Stack"

  BUILD_FLAG=""
  $REBUILD && BUILD_FLAG="--build"

  log_info "Building core images..."
  docker compose -f "$COMPOSE_STACK" build

  log_info "Building fleet images..."
  docker compose -f "$COMPOSE_FLEET" build

  log_info "Starting core stack..."
  docker compose -f "$COMPOSE_STACK" up -d $BUILD_FLAG

  log_info "Waiting for elastic-setup to complete..."
  for i in $(seq 1 60); do
    SETUP_STATUS=$(docker inspect --format='{{.State.Status}}' elastic-setup 2>/dev/null || echo "missing")
    if [ "$SETUP_STATUS" == "exited" ]; then
      log_info "elastic-setup completed"
      break
    elif [ "$SETUP_STATUS" == "missing" ]; then
      log_error "elastic-setup container not found"
    fi
    echo -n "."
    sleep 5
  done
  echo ""

  wait_healthy "es-01"    "Elasticsearch es-01"
  wait_healthy "es-02"    "Elasticsearch es-02"
  wait_healthy "es-03"    "Elasticsearch es-03"
  wait_healthy "kibana"   "Kibana"

  log_info "Core stack is healthy"

  # ==============================================================================
  # Phase 1.5: Setup Templates & Import Dashboard
  # ==============================================================================
  log_step "Phase 1.5: Setup Templates & Import Dashboard"
  
  log_info "Setting up Elasticsearch templates..."
  bash scripts/setup_elastic_templates.sh || log_warn "Failed to setup templates"

  log_info "Importing Kibana dashboard..."
  bash scripts/import_kibana_dashboard.sh || log_warn "Failed to import dashboard"
fi

# ==============================================================================
# Phase 2: Fleet Server Service Token
# ==============================================================================
log_step "Phase 2: Fleet Server service token"

BASE_URL="https://localhost:9200/_security/service/elastic/fleet-server/credential/token/$FLEET_TOKEN_NAME"

# Delete existing token (ignore errors — may not exist)
log_info "Deleting existing token '$FLEET_TOKEN_NAME' (if any)..."
docker exec es-01 curl -sk -X DELETE \
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  "$BASE_URL" -o /dev/null || true

log_info "Creating new API-based token '$FLEET_TOKEN_NAME'..."
TOKEN_RESPONSE=$(docker exec es-01 curl -sk -X POST \
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  "$BASE_URL")

# Parse inside using portable bash tools (grep/cut)
FLEET_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)

[ -n "$FLEET_TOKEN" ] || log_error "Failed to create service token. Response: $TOKEN_RESPONSE"

update_env "FLEET_SERVER_SERVICE_TOKEN" "$FLEET_TOKEN"
log_info "FLEET_SERVER_SERVICE_TOKEN updated in .env"

# ==============================================================================
# Phase 3: Agent Enrollment Token
# ==============================================================================
log_step "Phase 3: Agent enrollment token"

log_info "Fetching enrollment token for policy: $AGENT_POLICY_ID"

ENROLL_RESPONSE=$(docker exec kibana curl -sk \
  -u "elastic:${ELASTIC_PASSWORD}" \
  "https://localhost:5601/api/fleet/enrollment_api_keys" \
  -H "kbn-xsrf: true")

# Parse JSON using awk to find the active api_key for the specific policy_id
ENROLL_TOKEN=$(echo "$ENROLL_RESPONSE" | sed 's/},/\n/g' | grep '"active":true' | grep "\"policy_id\":\"${AGENT_POLICY_ID}\"" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4 | head -n 1)

[ -n "$ENROLL_TOKEN" ] || log_error "No active enrollment token found for policy '$AGENT_POLICY_ID'. Is Kibana Fleet configured?"

update_env "ELASTIC_AGENT_ENROLLMENT_TOKEN" "$ENROLL_TOKEN"
log_info "ELASTIC_AGENT_ENROLLMENT_TOKEN updated in .env"

# ==============================================================================
# Phase 4: Fleet Server
# ==============================================================================
log_step "Phase 4: Fleet Server"

BUILD_FLAG=""
$REBUILD && BUILD_FLAG="--build"

log_info "Starting fleet-server..."
docker compose -f "$COMPOSE_FLEET" up -d $BUILD_FLAG fleet-server

wait_healthy "fleet-server" "Fleet Server"

# ==============================================================================
# Phase 5: Elastic Agent
# ==============================================================================
log_step "Phase 5: Elastic Agent"

log_info "Starting elastic-agent..."
docker compose -f "$COMPOSE_FLEET" up -d elastic-agent

log_info "Waiting 15s for agent to enroll..."
sleep 15

AGENT_STATUS=$(docker inspect \
  "$(docker ps -qf 'name=elastic-fleet-elastic-agent' | head -1)" \
  --format='{{.State.Status}}' 2>/dev/null || echo "unknown")

if [ "$AGENT_STATUS" == "running" ]; then
  log_info "Elastic agent is running"
else
  log_warn "Elastic agent status: $AGENT_STATUS — check logs with:"
  log_warn "  docker logs \$(docker ps -qf 'name=elastic-fleet-elastic-agent' | head -1)"
fi

# ==============================================================================
# Summary
# ==============================================================================
log_step "Deployment complete"

echo ""
echo "  Kibana:          https://localhost:5601"
echo "  Elasticsearch:   https://localhost:9200"
echo "  Fleet Server:    https://localhost:8220"
echo "  Credentials:     elastic / ${ELASTIC_PASSWORD}"
echo ""
echo "  Run health check: bash scripts/check_health.sh"
echo ""