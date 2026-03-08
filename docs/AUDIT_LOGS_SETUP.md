# Audit Logs Pipeline — Setup Guide

This guide walks through the complete setup of the audit logs pipeline, from starting the backend application to configuring Elastic Agent in Kibana to ship logs into Elasticsearch.

**Prerequisites:** The core Elastic Stack (`elk-multi-node-cluster.yml`) and Fleet stack (`fleet-compose.yml`) must already be running and healthy before starting these steps.


## Overview

```
demo-app writes JSON log files
        |
        v
Elastic Agent reads files → ships to Elasticsearch
        |
        v
Ingest pipeline parses and enriches each document
        |
        v
Data stream (logs-audit-*) stores indexed events
        |
        v
Kibana — query, visualize, alert
```

The setup has four stages:

1. Create the shared log volume and start the backend stack
2. Apply Elasticsearch templates to the cluster
3. Configure the Elastic Agent integration in Kibana
4. Verify logs are flowing


## Stage 1 — Start the Backend Stack

Create the shared Docker volume that the demo-app and Elastic Agent both mount:

```bash
docker volume create app-logs
```

Start the backend stack:

```bash
docker compose -f backend-compose.yml up -d
```

Wait for all services to be healthy:

```bash
docker compose -f backend-compose.yml ps
```

The `demo-app` service writes audit log files to `/var/log/demo-app/` inside the container, which maps to the `app-logs` volume. Each container instance writes to its own file named `logs_audit_<hostname>.json` to avoid write conflicts when scaling.

To scale demo-app horizontally:

```bash
docker compose -f backend-compose.yml up -d --scale demo-app=3
```


## Stage 2 — Apply Elasticsearch Templates

Run the deployment script from the project root. It applies resources to the cluster in the correct order: ingest pipeline, ILM policy, component templates, index template.

```bash
bash scripts/setup_elastic_templates.sh
```

Expected output:

```
--- 1. Deploying Ingest Pipelines ---
Deploying audit-logs-pipeline... SUCCESS

--- 2. Deploying ILM Policies ---
Deploying audit-logs-policy... SUCCESS

--- 3. Deploying Component Templates ---
Deploying audit-logs-settings... SUCCESS
Deploying audit-logs-mappings... SUCCESS

--- 4. Deploying Index Templates ---
Deploying audit-logs-template... SUCCESS
```

To verify in Kibana: go to **Stack Management > Index Management** and check that the component templates and index template are present. The data stream itself will be created automatically when the first document is indexed.

For details on what each template does and the design rationale, see [assets/README.md](../assets/README.md).


## Stage 3 — Configure Elastic Agent Integration in Kibana

This step tells the Elastic Agent where to find the audit log files and which data stream to write them into.

### 3.1 — Create a new agent policy (or reuse an existing one)

Go to **Fleet > Agent Policies** and either create a new policy (e.g. `audit-logs-policy`) or select an existing policy that already has your agent enrolled.

### 3.2 — Add a Custom Logs integration

Inside the agent policy, click **Add integration** and search for **Custom Logs** (the integration is listed as "Custom Logs" or "Log file").

Fill in the integration settings:

**Log file paths:**

```
/usr/share/app-logs/logs_audit_*.json
```

This path reflects how the `app-logs` volume is mounted inside the Elastic Agent container (`fleet-compose.yml` mounts it at `/usr/share/app-logs`).

**Dataset name:**

```
audit
```

This sets the dataset portion of the data stream name. Combined with the `logs` type and a namespace, Elasticsearch will write events to `logs-audit-<namespace>`, which matches the `logs-audit-*` pattern in the index template.

**Namespace:**

```
app
```

The resulting data stream name will be `logs-audit-app`.

**Advanced settings — Custom configurations (YAML):**

```yaml
parsers:
  - ndjson:
      target: ""
      add_error_key: true
      message_key: message
```

This tells the Elastic Agent filebeat input to parse each log line as NDJSON. The `message_key: message` setting places the raw JSON string into the `message` field, which the ingest pipeline then parses and promotes to the document root.

### 3.3 — Save and deploy

Click **Save integration**. Kibana will prompt you to deploy the updated policy to enrolled agents. Confirm the deployment.

The Elastic Agent will pick up the new configuration within a few seconds and begin tailing the log files.


## Stage 4 — Verify

### Generate some log events

Send a few requests to the demo-app through Nginx:

```bash
# Create a document
curl -X POST http://localhost/documents \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Document", "content": "Hello world", "owner_id": "alice"}'

# List documents
curl "http://localhost/documents?user_id=alice"
```

### Check in Kibana

Go to **Discover** and select the `logs-audit-app` data stream (or use the index pattern `logs-audit-*`).

You should see events with the following fields populated: `@timestamp`, `event.action`, `user.id`, `source.ip`, `resource.id`, `resource.name`.

To confirm the ingest pipeline ran correctly, check that:
- The `message` field is absent (removed by the pipeline)
- `user_agent.name` is present as a parsed sub-field (expanded by the pipeline)

### Check the data stream

```bash
GET _data_stream/logs-audit-app
GET _data_stream/logs-audit-app/_stats
```

### Check agent status

Go to **Fleet > Agents** and confirm the agent status is **Healthy** and the last activity timestamp is recent.


## Troubleshooting

**No documents appearing in Kibana:**
- Check the agent is enrolled and healthy in **Fleet > Agents**
- Confirm the log file path in the integration matches the actual mount path inside the agent container
- Run `docker compose -f fleet-compose.yml logs elastic-agent` to check for file access errors

**Documents appearing but fields are flat (not parsed):**
- The ingest pipeline may not have been applied. Re-run `bash scripts/setup_elastic_templates.sh`
- Confirm the index template was applied before the first document was indexed. If the data stream was created before the template existed, delete the data stream and re-index

**`source.ip` showing the Nginx container IP instead of the real client:**
- Nginx must be configured to pass the `X-Forwarded-For` header. The demo-app reads this header in `logger.py` to extract the real client IP.