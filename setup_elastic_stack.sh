#!/bin/bash
set -e

# ==============================================================================
# Elastic Stack Automated Deployment Script
# Automates Phase 1 (Core Stack) & Phase 2 (Fleet & Agent)
# ==============================================================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "\n${BLUE}>>> $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 0. Check prerequisites
log_step "Checking Prerequisites"
command -v docker >/dev/null 2>&1 || log_error "Docker is required but not installed."
command -v curl >/dev/null 2>&1 || log_error "curl is required but not installed."
command -v jq >/dev/null 2>&1 || log_error "jq is required but not installed."

if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        log_info "Creating .env from .env.example..."
        cp .env.example .env
        
        KIBANA_ENC_KEY=$(openssl rand -hex 32)
        KIBANA_REP_KEY=$(openssl rand -hex 32)
        KIBANA_SEC_KEY=$(openssl rand -hex 32)
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^KIBANA_ENCRYPTION_KEY=.*/KIBANA_ENCRYPTION_KEY=${KIBANA_ENC_KEY}/" .env
            sed -i '' "s/^KIBANA_REPORTING_KEY=.*/KIBANA_REPORTING_KEY=${KIBANA_REP_KEY}/" .env
            sed -i '' "s/^KIBANA_SECURITY_KEY=.*/KIBANA_SECURITY_KEY=${KIBANA_SEC_KEY}/" .env
            sed -i '' "s/^ELASTIC_PASSWORD=.*/ELASTIC_PASSWORD=elastic123456789/" .env
            sed -i '' "s/^KIBANA_PASSWORD=.*/KIBANA_PASSWORD=kibana123456789/" .env
        else
            sed -i "s/^KIBANA_ENCRYPTION_KEY=.*/KIBANA_ENCRYPTION_KEY=${KIBANA_ENC_KEY}/" .env
            sed -i "s/^KIBANA_REPORTING_KEY=.*/KIBANA_REPORTING_KEY=${KIBANA_REP_KEY}/" .env
            sed -i "s/^KIBANA_SECURITY_KEY=.*/KIBANA_SECURITY_KEY=${KIBANA_SEC_KEY}/" .env
            sed -i "s/^ELASTIC_PASSWORD=.*/ELASTIC_PASSWORD=elastic123456789/" .env
            sed -i "s/^KIBANA_PASSWORD=.*/KIBANA_PASSWORD=kibana123456789/" .env
        fi
        log_info ".env created with generated keys and default passwords."
    else
        log_error ".env and .env.example not found!"
    fi
fi

# Load environment variables
source .env
if [ -z "$ELASTIC_PASSWORD" ]; then
    log_error "ELASTIC_PASSWORD is not set in .env"
fi

# ==============================================================================
# PHASE 1: Core Stack
# ==============================================================================
log_step "Phase 1: Deploying Core Stack"
log_info "Building Core images..."
docker compose -f elk-multi-node-cluster.yml build --no-cache

log_info "Starting Core stack..."
docker compose -f elk-multi-node-cluster.yml up -d

log_info "Waiting for elastic-setup container to finish..."
while true; do
    SETUP_STATUS=$(docker inspect --format='{{.State.Status}}' elastic-setup 2>/dev/null || echo "missing")
    if [ "$SETUP_STATUS" == "exited" ]; then
        log_info "elastic-setup completed."
        break
    elif [ "$SETUP_STATUS" == "missing" ]; then
        log_error "elastic-setup container not found!"
    fi
    echo -n "."
    sleep 5
done
echo ""

log_info "Waiting for Elasticsearch cluster to be healthy..."
until docker exec es-01 curl -sf --cacert config/certs/ca/ca.crt -u "elastic:${ELASTIC_PASSWORD}" "https://localhost:9200/_cluster/health" | grep -qE '"status":"(green|yellow)"'; do
    echo -n "."
    sleep 10
done
echo ""
log_info "Elasticsearch is healthy."

log_info "Waiting for Kibana to be ready..."
until curl -sk "https://localhost:5601/api/status" | grep -q '"level":"available"'; do
    echo -n "."
    sleep 10
done
echo ""
log_info "Kibana is ready."

# ==============================================================================
# PHASE 2: Fleet & Elastic Agent
# ==============================================================================
log_step "Phase 2: Configuring Fleet & Deploying Agents"

# 1. Get CA Fingerprint
log_info "Extracting CA fingerprint from es-01..."
CA_FINGERPRINT=$(docker exec es-01 openssl x509 -fingerprint -sha256 -noout -in /usr/share/elasticsearch/config/certs/ca/ca.crt | sed 's/.*=//' | tr -d ':')
log_info "CA Fingerprint: $CA_FINGERPRINT"

# 2. Update Fleet Default Output
log_info "Updating Fleet Default Output..."
curl -sk -u "elastic:${ELASTIC_PASSWORD}" -X PUT "https://localhost:5601/api/fleet/outputs/fleet-default-output" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d '{ 
    "name": "default",
    "type": "elasticsearch",
    "hosts": ["https://es-01:9200"],
    "ca_trusted_fingerprint": "'"${CA_FINGERPRINT}"'",
    "is_default": true,
    "is_default_monitoring": true
  }' > /dev/null

# 3. Add Fleet Server Host
log_info "Adding Fleet Server host..."
curl -sk -u "elastic:${ELASTIC_PASSWORD}" -X POST "https://localhost:5601/api/fleet/fleet_server_hosts" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d '{ 
    "name": "Fleet Server",
    "host_urls": ["https://fleet-server:8220"],
    "is_default": true
  }' > /dev/null

# 4. Create Fleet Server Policy
log_info "Creating Fleet Server Policy..."
POLICY_ID="fleet-server-policy"
curl -sk -u "elastic:${ELASTIC_PASSWORD}" -X POST "https://localhost:5601/api/fleet/agent_policies" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d '{ 
    "id": "'"${POLICY_ID}"'",
    "name": "Fleet Server Policy",
    "description": "Policy for Fleet Server",
    "namespace": "default",
    "monitoring_enabled": ["logs", "metrics"]
  }' > /dev/null

log_info "Getting fleet_server package version..."
FLEET_PKG_VERSION=$(curl -sk -u "elastic:${ELASTIC_PASSWORD}" "https://localhost:5601/api/fleet/epm/packages/fleet_server" -H "kbn-xsrf: true" | jq -r '.item.version')

if [ -z "$FLEET_PKG_VERSION" ] || [ "$FLEET_PKG_VERSION" == "null" ]; then
    log_warn "Failed to get fleet_server package version, defaulting to 9.3.1 (or version from .env)"
    FLEET_PKG_VERSION=${STACK_VERSION:-9.3.1}
fi

log_info "Adding Fleet Server integration to policy..."
curl -sk -u "elastic:${ELASTIC_PASSWORD}" -X POST "https://localhost:5601/api/fleet/package_policies" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d '{ 
    "name": "fleet_server-1",
    "policy_id": "'"${POLICY_ID}"'",
    "package": {
      "name": "fleet_server",
      "version": "'"${FLEET_PKG_VERSION}"'"
    },
    "inputs": []
  }' > /dev/null || log_warn "Integration API failed. You may need to manually add it via Kibana UI."

# 5. Generate Fleet Server Service Token
log_info "Generating Fleet Server Service Token..."
TOKEN_RESP=$(docker exec es-01 curl -sf -X POST \
  --cacert config/certs/ca/ca.crt \
  -u "elastic:${ELASTIC_PASSWORD}" \
  "https://localhost:9200/_security/service/elastic/fleet-server/credential/token/fleet-token-$(date +%s)")
FLEET_SERVER_SERVICE_TOKEN=$(echo $TOKEN_RESP | jq -r '.token.value')

if [ "$FLEET_SERVER_SERVICE_TOKEN" == "null" ] || [ -z "$FLEET_SERVER_SERVICE_TOKEN" ]; then
    log_error "Failed to generate Fleet Server service token."
fi

# 6. Update .env with Fleet config
log_info "Updating .env with Fleet Service Token and Policy ID..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|^FLEET_SERVER_SERVICE_TOKEN=.*|FLEET_SERVER_SERVICE_TOKEN=${FLEET_SERVER_SERVICE_TOKEN}|" .env
    sed -i '' "s|^FLEET_SERVER_POLICY_ID=.*|FLEET_SERVER_POLICY_ID=${POLICY_ID}|" .env
else
    sed -i "s|^FLEET_SERVER_SERVICE_TOKEN=.*|FLEET_SERVER_SERVICE_TOKEN=${FLEET_SERVER_SERVICE_TOKEN}|" .env
    sed -i "s|^FLEET_SERVER_POLICY_ID=.*|FLEET_SERVER_POLICY_ID=${POLICY_ID}|" .env
fi

# 7. Start Fleet Server
log_info "Building Fleet images..."
docker compose -f fleet-compose.yml build --no-cache

log_info "Starting Fleet Server..."
docker compose -f fleet-compose.yml up -d fleet-server

log_info "Waiting for Fleet Server to be healthy..."
while true; do
    FLEET_STATUS=$(docker inspect --format='{{.State.Health.Status}}' fleet-server 2>/dev/null || echo "missing")
    if [ "$FLEET_STATUS" == "healthy" ]; then
        log_info "Fleet Server is healthy."
        break
    elif [ "$FLEET_STATUS" == "missing" ]; then
        log_warn "Fleet Server container missing? Waiting..."
    fi
    echo -n "."
    sleep 5
done
echo ""

# 8. Create Agent Policy and Get Enrollment Token
log_info "Creating generic Agent Policy..."
AGENT_POLICY_ID="agent-policy-prod"
curl -sk -u "elastic:${ELASTIC_PASSWORD}" -X POST "https://localhost:5601/api/fleet/agent_policies" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d '{ 
    "id": "'"${AGENT_POLICY_ID}"'",
    "name": "Production Agent Policy",
    "namespace": "default",
    "monitoring_enabled": ["logs", "metrics"]
  }' > /dev/null

log_info "Retrieving Enrollment Token for Agent Policy..."
TOKENS_RESP=$(curl -sk -u "elastic:${ELASTIC_PASSWORD}" "https://localhost:5601/api/fleet/enrollment_api_keys" -H "kbn-xsrf: true")
ELASTIC_AGENT_ENROLLMENT_TOKEN=$(echo "$TOKENS_RESP" | jq -r '.items[] | select(.policy_id == "'"${AGENT_POLICY_ID}"'" ) | .api_key')

if [ -z "$ELASTIC_AGENT_ENROLLMENT_TOKEN" ] || [ "$ELASTIC_AGENT_ENROLLMENT_TOKEN" == "null" ]; then
    log_warn "Could not automatically retrieve Enrollment Token. Please manually create an Agent policy and token in Kibana."
    log_warn "Then set ELASTIC_AGENT_ENROLLMENT_TOKEN in .env and run: docker compose -f fleet-compose.yml up -d elastic-agent"
else
    log_info "Updating .env with Elastic Agent Enrollment Token..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|^ELASTIC_AGENT_ENROLLMENT_TOKEN=.*|ELASTIC_AGENT_ENROLLMENT_TOKEN=${ELASTIC_AGENT_ENROLLMENT_TOKEN}|" .env
    else
        sed -i "s|^ELASTIC_AGENT_ENROLLMENT_TOKEN=.*|ELASTIC_AGENT_ENROLLMENT_TOKEN=${ELASTIC_AGENT_ENROLLMENT_TOKEN}|" .env
    fi

    # 9. Start single Elastic Agent
    log_info "Starting 1 Elastic Agent..."
    docker compose -f fleet-compose.yml up -d elastic-agent

    log_info "Agent started. Check logs: docker logs -f 
$(docker ps -qf 'name=elastic-fleet-elastic-agent')"
fi

log_step "Deployment complete!"
log_info "Kibana: https://localhost:5601 (elastic / ${ELASTIC_PASSWORD})"
log_info "Elasticsearch: https://localhost:9200"
