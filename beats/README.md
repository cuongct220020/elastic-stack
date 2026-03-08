# Beats — Fleet Server and Elastic Agent

This directory contains the build contexts for Fleet Server and Elastic Agent, both of which run as containers managed by `fleet-compose.yml`.

## Directory Structure

```
beats/
  fleet/          # Fleet Server build context
    Dockerfile
  agent/          # Elastic Agent build context
    Dockerfile
```

## How Fleet Server and Elastic Agent Relate

Fleet Server and Elastic Agent are both built on the same Elastic Agent binary. The difference is the role each container plays:

- **Fleet Server** runs in server mode. It is the control plane — it receives policy updates from Kibana and distributes them to enrolled agents. There is one Fleet Server per deployment.
- **Elastic Agent** runs in agent mode. It enrolls with Fleet Server, receives its policy, and executes the actual data collection: tailing log files, collecting metrics, running integrations. Multiple agents can be deployed and scaled independently.

The separation exists so that the control plane (Fleet Server) and the data collection layer (Elastic Agent) can be scaled and updated independently.

## Deployment

Both services are defined in `fleet-compose.yml` and connect to the core stack via the shared `elastic-net` network. Fleet Server must be healthy before any Elastic Agent can enroll.

The `setup_elastic_stack.sh` script handles the correct startup order automatically, including generating the Fleet Server service token and fetching the agent enrollment token.

To scale Elastic Agent horizontally:

```bash
docker compose -f fleet-compose.yml up -d --scale elastic-agent=3
```

`elastic-agent` has no `container_name` set in the compose file specifically to allow this.

## Further Reading

- Fleet Server details: [beats/fleet/README.md](fleet/README.md)
- Elastic Agent details: [beats/agent/README.md](agent/README.md)
- Full deployment walkthrough: [docs/DEPLOYMENT.md](../docs/DEPLOYMENT.md)
- Audit logs pipeline setup: [docs/AUDIT_LOGS_SETUP.md](../docs/AUDIT_LOGS_SETUP.md)