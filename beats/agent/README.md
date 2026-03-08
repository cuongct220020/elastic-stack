# Elastic Agent

Elastic Agent is the data collection layer of the stack. It enrolls with Fleet Server, receives its policy, and executes integrations — tailing log files, collecting system metrics, shipping events to Elasticsearch.

## How It Works

On startup, the Elastic Agent container:

1. Connects to Fleet Server using the enrollment token
2. Registers itself as an agent under the policy associated with that token
3. Downloads the policy from Fleet Server
4. Starts executing all integrations defined in the policy
5. Periodically checks in with Fleet Server to report health and receive policy updates

All configuration is managed through the Fleet UI in Kibana. There are no local config files to edit — the agent receives everything from Fleet Server at runtime.

## Authentication — Enrollment Token

Elastic Agent authenticates to Fleet Server using an **enrollment token**. Unlike the Fleet Server service token, enrollment tokens are scoped to a specific agent policy. An agent that enrolls with a token gets exactly the policy that token is associated with.

The enrollment token is fetched during initial setup:

```bash
bash scripts/get_agent_enrollment_token.sh
```

The script writes the token to `.env` as `ELASTIC_AGENT_ENROLLMENT_TOKEN`. To fetch a token manually:

```bash
# List all enrollment tokens
curl -s https://localhost:9200/.fleet-enrollment-api-keys/_search?pretty \
  -u elastic:$ELASTIC_PASSWORD \
  --cacert config/certs/ca/ca.crt
```

Enrollment tokens can be created and revoked in Kibana under **Fleet > Enrollment Tokens**.

## Volume Mounts

The Elastic Agent container mounts several paths to enable log and metric collection:

| Mount | Purpose |
|---|---|
| `certs:/usr/share/elastic-agent/config/certs:ro` | CA certificate for verifying Fleet Server and Elasticsearch TLS |
| `app-logs:/usr/share/app-logs:ro` | Audit log files written by `demo-app` |
| `/var/log:/var/log:ro` | Host system logs |
| `/var/run/docker.sock:/var/run/docker.sock:ro` | Docker socket for container metrics and log collection |

The `app-logs` volume is shared with the `demo-app` containers. The agent reads log files from this volume and ships them to Elasticsearch based on the Custom Logs integration configured in the agent policy.

The Docker socket mount gives the agent visibility into all running containers on the host — container names, images, resource usage, and stdout/stderr logs. This requires the agent to run as `root`, which is set in the compose file.

## Scaling

Multiple agent instances can run simultaneously. Because `elastic-agent` has no `container_name` in `fleet-compose.yml`, Docker allows horizontal scaling:

```bash
docker compose -f fleet-compose.yml up -d --scale elastic-agent=3
```

Each instance enrolls independently and appears as a separate agent in Fleet. All instances receive the same policy. This is useful when monitoring multiple hosts or when the volume of logs requires more than one agent to keep up with ingestion.

When scaling, each agent instance gets a unique agent ID assigned by Fleet Server. Removing a scaled-down instance leaves an offline agent entry in Fleet — clean these up with:

```bash
bash scripts/cleanup_offline_agents.sh
```

## Managing Agent Policies in Kibana

An agent policy defines what an agent collects. Policies are managed in **Fleet > Agent Policies** in Kibana.

Each policy contains one or more integrations. An integration is a pre-configured input (for example: Custom Logs, System metrics, Docker metrics). When you add or modify an integration in a policy, Fleet Server pushes the updated policy to all enrolled agents within seconds — no restart required.

For the audit logs pipeline specifically, the Custom Logs integration is added to the agent policy with the log file path pointing to the `app-logs` volume mount. See [docs/AUDIT_LOGS_SETUP.md](../../docs/AUDIT_LOGS_SETUP.md) for the full configuration.

## Useful Commands

Check agent status in Fleet (via Elasticsearch):

```bash
curl -s https://localhost:9200/.fleet-agents/_search?pretty \
  -u elastic:$ELASTIC_PASSWORD \
  --cacert config/certs/ca/ca.crt \
  | jq '.hits.hits[]._source | {id: .agent.id, status: .last_checkin_status, policy: .policy_id}'
```

Check agent container logs:

```bash
docker compose -f fleet-compose.yml logs elastic-agent --tail=50
```

Force the agent to re-enroll (useful after a token rotation):

```bash
docker compose -f fleet-compose.yml up -d --force-recreate elastic-agent
```

## Troubleshooting

**Agent enrolls but no data appears in Elasticsearch:**
- Check that the log file path in the Custom Logs integration matches the actual mount path inside the container (`/usr/share/app-logs/logs_audit_*.json`)
- Confirm the `app-logs` volume is mounted and contains files: `docker exec <agent-container> ls /usr/share/app-logs/`
- Check agent logs for file access errors: `docker compose -f fleet-compose.yml logs elastic-agent`

**Agent status shows "Unhealthy" in Fleet:**
- The agent may have lost connectivity to Fleet Server or Elasticsearch
- Check that Fleet Server is healthy: `curl -sf --cacert config/certs/ca/ca.crt https://localhost:8220/api/status`
- Restart the agent container: `docker compose -f fleet-compose.yml restart elastic-agent`

**Agent appears as offline after scaling down:**
- Run `bash scripts/cleanup_offline_agents.sh` to unenroll stale agents from Fleet

## Further Reading

- Fleet Server setup: [beats/fleet/README.md](../fleet/README.md)
- Audit logs integration configuration: [docs/AUDIT_LOGS_SETUP.md](../../docs/AUDIT_LOGS_SETUP.md)
- Full deployment walkthrough: [docs/DEPLOYMENT.md](../../docs/DEPLOYMENT.md)