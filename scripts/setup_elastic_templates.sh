#!/usr/bin/env bash
# setup_elastic_templates.sh
# Automates the creation of ILM Policies, Component Templates, and Index Templates
# directly into Elasticsearch via its REST API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"
ASSETS_DIR="$ROOT_DIR/assets/elasticsearch"

# Extract Elasticsearch Password
ELASTIC_PASSWORD=$(grep "^ELASTIC_PASSWORD=" "$ENV_FILE" | cut -d= -f2 | tr -d '"')
if [ -z "$ELASTIC_PASSWORD" ]; then
  echo "ERROR: ELASTIC_PASSWORD not found in .env" >&2
  exit 1
fi

ES_URL="https://localhost:9200"
AUTH="-u elastic:${ELASTIC_PASSWORD} --cacert config/certs/ca/ca.crt"

echo "==========================================================" 
echo "      ELASTICSEARCH TEMPLATE DEPLOYMENT SCRIPT" 
echo "=========================================================="

# Helper function to send PUT requests
deploy_json() {
    local api_endpoint=$1
    local file_path=$2
    local entity_name=$3

    echo -n "Deploying $entity_name... "
    
    # Read the file content from the host and pass it to curl inside the container
    local payload
    payload=$(cat "$file_path")
    
    # Execute curl inside es-01 to avoid SSL path issues
    local response
    response=$(echo "$payload" | docker exec -i es-01 curl -sk -X PUT $AUTH "$ES_URL/$api_endpoint" \
        -H "Content-Type: application/json" -d @-)
    
    if echo "$response" | grep -q '"acknowledged":true'; then
        echo "SUCCESS"
    else
        echo "FAILED"
        echo "Response: $response"
    fi
}

# 1. Deploy Ingest Pipelines
echo ""
echo "--- 1. Deploying Ingest Pipelines ---"
deploy_json "_ingest/pipeline/audit-logs-pipeline" "$ASSETS_DIR/ingest-pipelines/audit-logs-pipeline.json" "audit-logs-pipeline"

# 2. Deploy ILM Policies (Lifecycle)
echo ""
echo "--- 2. Deploying ILM Policies ---"
deploy_json "_ilm/policy/audit-logs-policy" "$ASSETS_DIR/ilm-policies/audit-logs-policy.json" "audit-logs-policy"

# 3. Deploy Component Templates (Settings & Mappings)
echo ""
echo "--- 3. Deploying Component Templates ---"
deploy_json "_component_template/audit-logs-settings" "$ASSETS_DIR/component-templates/settings/audit-logs-settings.json" "audit-logs-settings"
deploy_json "_component_template/audit-logs-mappings" "$ASSETS_DIR/component-templates/mappings/audit-logs-mappings.json" "audit-logs-mappings"

# 4. Deploy Index Templates (The glue that binds it all)
echo ""
echo "--- 4. Deploying Index Templates ---"
deploy_json "_index_template/audit-logs-template" "$ASSETS_DIR/index-templates/audit-logs-template.json" "audit-logs-template"

echo "=========================================================="
echo "Deployment Complete! You can verify them in Kibana -> Stack Management."
