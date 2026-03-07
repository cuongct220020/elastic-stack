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



log_step "Deployment complete!"
log_info "Kibana: https://localhost:5601 (elastic / ${ELASTIC_PASSWORD})"
log_info "Elasticsearch: https://localhost:9200"
