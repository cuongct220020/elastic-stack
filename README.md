# Self-managed Elastic Stack

A production-ready, containerized Elastic Stack deployment with a 3-node Elasticsearch cluster, Kibana, Fleet Server, and Elastic Agent. This stack implementation for auditing logs in distributed environments. 

![audit-logs-lifecycle.png](docs/images/audit-logs-app-lifecycle.png)

## Prerequisites

For production deployments on Linux, ensure the host system is properly tuned (e.g., swap disabled, file descriptors increased, and memory locks configured) according to the [Elasticsearch System Configuration guide](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/important-system-configuration).

To streamline this configuration (check carefully before apply). 
- **Manual configuration:** Use `scripts/set_important_es_sysconfig.sh` to apply recommended settings.
- **Automated configuration:** Use the [Ansible playbooks](./ansible/) for consistent configuration across multiple nodes.

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


## Stack Deployment

### Automated (recommended)

Copy and configure the environment file, then run the setup script:
```bash
cp .env.example .env

# Fill some important variables in .env
ELASTIC_PASSWORD=
KIBANA_PASSWORD=

# openssl rand -hex -32
KIBANA_ENCRYPTION_KEY=
KIBANA_REPORTING_KEY=
KIBANA_SECURITY_KEY=
MONGO_DB_USERNAME=
MONGO_DB_PASSWORD=
# MINIO_ROOT_USER=
# MINIO_ROOT_PASSWORD=
```

```bash
bash setup_elastic_stack.sh
```
The script handles all steps end-to-end: building images, waiting for health checks, creating the Fleet Server service token, fetching the agent enrollment token, and starting Fleet Server and Elastic Agent in the correct order.

**Options:**

```bash
bash setup_elastic_stack.sh --rebuild     # full teardown + rebuild
bash setup_elastic_stack.sh --fleet-only  # redeploy Fleet Server + Agent only
```

### Manual deployment guide

For a step-by-step walkthrough with explanations, see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

### Useful scripts

```bash
bash scripts/check_health.sh                # health check all services + verify token type
bash scripts/cleanup_offline_agents.sh      # unenroll all offline agents
bash scripts/rotate_fleet_server_token.sh   # rotate the Fleet Server service token
bash scripts/get_agent_enrollment_token.sh  # fetch and update agent enrollment token
bash scripts/setup_elastic_templates.sh     # apply ILM policies, component templates, and index templates
bash scripts/import_kibana_dashboard.sh     # apply dashboard template
```

### Log Collection Setup

1. Access the Kibana UI at `https://localhost:5601`.
2. Log in with username `elastic` and the password configured in your `.env` file.
3. Navigate to **Fleet** > **Agent policies** and select the **General Agent Policy**.
![kibana-fleet-agent-policy-1.png](docs/images/kibana-fleet-agent-policy-1.png)
4. Click **Add integration** and search for **Custom Logs**. Configure it (e.g., as a Filestream) to read your application logs. Ensure the dataset or data stream is set to match your expected pattern (e.g., `logs-audit-*`).
![kibana-fleet-agent-policy-2.png](docs/images/kibana-fleet-agent-policy-2.png)


**Note on Pre-configurations (CI/CD):** If you need to pre-configure Elasticsearch templates or Kibana dashboards, modify the JSON/NDJSON files in the `assets/` directory. These are used by the automated setup scripts to bootstrap the environment.

```text
assets/
├── elasticsearch/
│   ├── component-templates/
│   ├── data-stream/
│   ├── ilm-policies/
│   ├── index-templates/
│   └── ingest-pipelines/
└── kibana/
    ├── dashboards/
    ├── index-pattern/
    └── visualizations/
```

## Exploring Audit Logs

Since the dashboard templates and index configurations are applied automatically during setup, you can immediately begin analyzing data.

### 1. Verify Data Ingestion
Navigate to **Analytics** > **Discover**. Select the `logs-audit-*` data view. You can use KQL (Kibana Query Language) to search and filter incoming log events.
![kibana-discover.png](docs/images/kibana-discover.png)

### 2. View Dashboards
Navigate to **Analytics** > **Dashboards** and open the pre-built Audit Logs dashboard. You can customize existing panels or create new visualizations based on your requirements.
![kibana-audit-logs-dashboard.png](docs/images/kibana-audit-logs-dashboard.png)

## Visualizing Additional Data Sources

To ingest and visualize entirely new types of data beyond the built-in audit logs, from Home to navigate **Stack Management** and follow the standard Elastic data management workflow:

1. **Define Data Rules:** First, establish how Elasticsearch should process and store the new data. Create an Index Lifecycle Policy (ILM), Index Template, and (if necessary) an Ingest Pipeline tailored to your new data source.
![kibana-index-template-setup.png](docs/images/kibana-index-template-setup.png)

2. **Create a Data View:** Make the new indices searchable in Kibana. Navigate to **Stack Management** > **Data Views** and create a view matching your new index pattern.
![kibana-data-view.png](docs/images/kibana-data-view.png)

3. **Analyze:** Return to **Analytics** > **Discover** or **Dashboards** to query the new data and build custom visualizations.

## Further development

Currently, the S3-compatible snapshot repository setup with MinIO (`storage-compose.yml`) is a manual post-deployment step. To fully automate this, future development should consider:
- Incorporating the startup of MinIO services (`storage-compose.yml`) into the main deployment flow.
- Integrating `scripts/setup_minio_repository.sh` into `setup_elastic_stack.sh` to automatically inject S3 credentials into the Elasticsearch keystore and register the repository via API.