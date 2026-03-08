# Self-managed Elastic Stack

A production-ready, containerized Elastic Stack deployment with a 3-node Elasticsearch cluster, Kibana, Fleet Server, and Elastic Agent — all secured with TLS.

![elastic-stack](docs/images/elastic-stack.png)


## Prerequisites

Before running the stack on a Linux host, configure the system for Elasticsearch:

```bash
# Required: raise virtual memory limit
sudo sysctl -w vm.max_map_count=262144

# Persist across reboots
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

For a full production host setup (swap, file descriptors, memory lock, etc.):

```bash
sudo bash scripts/set_important_es_sysconfig.sh
```

An Ansible role is also available under `ansible/` for automated host configuration across multiple nodes.


## Stack Overview

### Services

| Service | Role |
|---|---|
| `es-01`, `es-02`, `es-03` | Elasticsearch data and master nodes, forming a 3-node cluster |
| `kibana` | Web UI for search, dashboards, Fleet management, and index lifecycle configuration |
| `fleet-server` | Central control plane that manages Elastic Agent policies, enrollment, and health |
| `elastic-agent` | Deployed on monitored hosts; collects logs, metrics, and security events per Fleet policy |
| `demo-app` | FastAPI application that generates structured audit logs for pipeline testing |
| `nginx` | Reverse proxy in front of `demo-app` |
| `mongodb` | Document store for `demo-app` |
| `minio` | S3-compatible object storage for Elasticsearch cold/frozen snapshot repository |

### Compose files

| File | Purpose |
|---|---|
| `elk-multi-node-cluster.yml` | Core stack — Elasticsearch (3 nodes) + Kibana + Logstash (optional). Use this in production. |
| `fleet-compose.yml` | Fleet Server + Elastic Agent. Runs on top of the core stack via shared `elastic-net`. |
| `backend-compose.yml` | Demo application stack — FastAPI app + MongoDB + Nginx. |
| `storage-compose.yml` | MinIO object storage for Elasticsearch snapshot repository (cold/frozen tier). |
| `elk-single-node-cluster.yml` | Single-node Elasticsearch + Kibana, security disabled. For local dev only. |


## Deployment

### Automated (recommended)

Copy and configure the environment file, then run the setup script:

```bash
cp .env.example .env
# Edit .env: set ELASTIC_PASSWORD, KIBANA_PASSWORD, and Kibana encryption keys

bash setup_elastic_stack.sh
```

The script handles all steps end-to-end: building images, waiting for health checks, creating the Fleet Server service token, fetching the agent enrollment token, and starting Fleet Server and Elastic Agent in the correct order.

**Options:**

```bash
bash setup_elastic_stack.sh --rebuild     # full teardown + rebuild
bash setup_elastic_stack.sh --fleet-only  # redeploy Fleet Server + Agent only
```

### Manual deployment

For a step-by-step walkthrough with explanations, see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

### Useful scripts

```bash
bash scripts/check_health.sh                # health check all services + verify token type
bash scripts/rotate_fleet_server_token.sh   # rotate the Fleet Server service token
bash scripts/get_agent_enrollment_token.sh  # fetch and update agent enrollment token
bash scripts/cleanup_offline_agents.sh      # unenroll all offline agents
bash scripts/setup_elastic_templates.sh     # apply ILM policies, component templates, and index templates
```


## Demo App and Audit Logs

The `demo-app/` directory contains a FastAPI application that models a shared document repository. Every API action — create, read, update, soft-delete — is recorded as a structured ECS-compliant audit log event and shipped to Elasticsearch via Elastic Agent.

The goal is to demonstrate a complete observability pipeline: application writes logs, Elastic Agent collects and ships them, Elasticsearch indexes them with a defined schema, and Kibana provides dashboards for analysis.

For setup instructions, see [docs/AUDIT_LOGS_SETUP.md](docs/AUDIT_LOGS_SETUP.md).

For Elasticsearch index design and ILM rationale, see [assets/README.md](assets/README.md).

For application-level details (API endpoints, audit log schema, log file location), see [demo-app/README.md](demo-app/README.md).


## Documentation

### Guides

| File | What it covers |
|---|---|
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Step-by-step instructions for deploying the full stack manually |
| [docs/AUDIT_LOGS_SETUP.md](docs/AUDIT_LOGS_SETUP.md) | End-to-end setup for the audit logs pipeline: backend, templates, Kibana integration |
| [docs/ELASTICSEARCH_API.md](docs/ELASTICSEARCH_API.md) | Cookbook of common Elasticsearch API calls for cluster management, querying, and debugging |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Design decisions: why 3-node, why Fleet over Filebeat, data flow, network topology |

### Service Configuration

| Directory | What it covers |
|---|---|
| [elasticsearch/README.md](elasticsearch/README.md) | Node configuration, memory and TLS settings, useful debug commands |
| [kibana/README.md](kibana/README.md) | Kibana configuration, encryption keys, saved object export/import |
| [beats/README.md](beats/README.md) | Overview of Fleet Server and Elastic Agent |
| [beats/fleet/README.md](beats/fleet/README.md) | Fleet Server service token, TLS, startup dependencies |
| [beats/agent/README.md](beats/agent/README.md) | Elastic Agent enrollment, volume mounts, scaling, policy management |
| [assets/README.md](assets/README.md) | Elasticsearch index design: ILM policy, component templates, ingest pipeline |
| [demo-app/README.md](demo-app/README.md) | API endpoints, audit log schema, ECS field reference |