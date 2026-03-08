# Architecture Overview

This document explains the overall design of the stack — what each layer does, why it is structured the way it is, and how data flows from the application to Kibana.


## High-Level Components

```
[ demo-app (FastAPI) ]  -->  [ app-logs volume ]  -->  [ Elastic Agent ]
        |                                                      |
        v                                                      v
   [ MongoDB ]                                    [ Elasticsearch Cluster ]
                                                               |
[ nginx (reverse proxy) ]                                      v
                                                          [ Kibana ]
                                                               |
                                                     [ Fleet Server ]
                                                               |
                                                      [ Elastic Agent ]
```

The stack has two independent halves that connect through Elasticsearch:

- The **backend** (`backend-compose.yml`) — generates data
- The **Elastic stack** (`elk-multi-node-cluster.yml` + `fleet-compose.yml`) — collects, stores, and visualizes data

They share the `elastic-net` Docker network, which is the only connection point between them.


## Network Topology

Two Docker networks are used:

**`elastic-net`** — shared across all compose files. Every service that needs to communicate with Elasticsearch or Fleet Server is attached to this network: demo-app, nginx, Elastic Agent, Fleet Server, Kibana, all three ES nodes, and MinIO.

**`backend-net`** — internal to `backend-compose.yml`. Used only for communication between demo-app, MongoDB, and nginx. MongoDB is not exposed to `elastic-net` intentionally — it has no reason to be reachable by the Elastic stack.

The separation means that if the Elastic stack is not running, the backend can still function independently. And MongoDB is never reachable from the Elastic stack side, which reduces the network attack surface.


## Why a 3-Node Elasticsearch Cluster

A single Elasticsearch node is simpler to run but has no fault tolerance. If the node goes down, the entire stack is unavailable and data may be lost.

Three nodes is the minimum for a production-grade cluster for two reasons:

**Quorum.** Elasticsearch uses a quorum-based consensus protocol for master election and cluster state changes. With 3 master-eligible nodes, the cluster can tolerate 1 node failure and still reach quorum (2 out of 3). With 2 nodes, losing 1 means the remaining node cannot form a quorum and the cluster becomes read-only or unavailable.

**Shard replication.** With `number_of_replicas: 1`, each shard has one primary and one replica. On a 3-node cluster, Elasticsearch distributes primaries and replicas across different nodes — so losing any single node still leaves a full copy of the data available. On a single-node cluster, replicas cannot be assigned at all, which is why status stays yellow.

All three nodes in this stack are master-eligible and hold data. There are no dedicated master-only or data-only nodes. At this scale (3 nodes, moderate volume), role separation adds operational complexity without meaningful benefit.


## Why Fleet + Elastic Agent Instead of Filebeat

The older approach to shipping logs was to run Filebeat directly on each host, with a static config file defining what to tail and where to send it. This works, but it has a scaling problem: every time you need to change what is collected — add a new log path, change a parser, update a field mapping — you have to update the config file on every host and restart Filebeat.

Fleet + Elastic Agent solves this by centralizing policy management:

- Agent policies are defined once in Kibana
- Fleet Server distributes policy updates to all enrolled agents automatically
- No SSH, no config file edits, no restarts required for policy changes
- All agents report their health status back to Fleet, giving full visibility into collection health from a single UI

For a single-host setup the difference is small. For a multi-host or horizontally-scaled setup (like `--scale elastic-agent=3`), centralized management becomes essential.

The tradeoff is added infrastructure: Fleet Server is an extra service with its own startup dependencies, service token, and TLS configuration. The `setup_elastic_stack.sh` script exists specifically to manage this complexity.


## Why Data Streams Instead of Regular Indices

Regular indices are static — you create one, write to it, and query it. For time-series data like logs, this creates two problems: the index grows indefinitely, and there is no automated way to move older data to cheaper storage.

Data streams solve this by managing a sequence of backing indices automatically. From the application's perspective, there is one endpoint to write to (`logs-audit-app`). Elasticsearch handles:

- **Rollover** — creating a new backing index when the current one reaches a size or age threshold
- **Lifecycle transitions** — moving older backing indices through hot → warm → cold → delete phases via ILM
- **Query fan-out** — searches against the data stream automatically cover all backing indices

For audit logs specifically, the append-only and time-series nature of the data maps directly to this model. Events are never updated, queries are always time-bounded, and retention is a compliance requirement rather than a preference.


## Why MinIO

Elasticsearch's cold and frozen tiers support storing indices as **searchable snapshots** in an object storage repository. Instead of keeping old indices on primary SSD storage, Elasticsearch takes a snapshot, stores it in S3-compatible storage, and removes the local copy. The index remains searchable but reads are served from the snapshot repository.

MinIO provides an S3-compatible API running inside the same Docker network, so no external cloud storage is needed. It is configured with four data drives (`/data1` to `/data4`) to enable erasure coding — MinIO can tolerate losing up to 2 of the 4 drives without data loss.

In the current ILM policy, the cold phase does not yet have a searchable snapshot action configured. MinIO is deployed and ready, but the snapshot repository registration and the ILM action that uses it are the next step. The ILM policy's cold and delete phases work independently of MinIO today.


## Data Flow — Audit Logs End to End

```
1. HTTP request arrives at nginx
2. nginx forwards to demo-app (with X-Forwarded-For header)
3. demo-app handles the request, writes to MongoDB
4. demo-app writes an ECS-formatted JSON audit event to:
       /var/log/demo-app/logs_audit_<hostname>.json
       (mounted as the app-logs Docker volume)
5. Elastic Agent tails the log file from:
       /usr/share/app-logs/logs_audit_<hostname>.json
6. Elastic Agent ships the raw log line to Elasticsearch
7. Elasticsearch runs the audit-logs-pipeline ingest processor:
       a. json processor — parses message string into document fields
       b. user_agent processor — expands user_agent.original into sub-fields
       c. remove processor — drops message, agent, log.file.path
8. Elasticsearch indexes the document into the logs-audit-app data stream
       - index template applies mappings and settings
       - ILM policy governs the backing index lifecycle
9. Kibana queries the data stream for dashboards and Discover
```

Each step is independent: the demo-app does not know about Elasticsearch, Elastic Agent does not know about the application logic, and the ingest pipeline handles transformation without any changes to the agent or the application.


## Compose File Dependency Order

When bringing up the full stack, the correct order is:

```
1. elk-multi-node-cluster.yml   — Elasticsearch cluster + Kibana
2. storage-compose.yml          — MinIO (optional, for cold tier)
3. fleet-compose.yml            — Fleet Server + Elastic Agent
4. backend-compose.yml          — demo-app + MongoDB + nginx
```

Steps 2 and 4 can be started in any order relative to each other, but both require the Elasticsearch cluster (step 1) to be healthy first. Fleet Server (step 3) additionally requires Kibana to be healthy because it calls the Kibana API during initialization.

The `setup_elastic_stack.sh` script manages steps 1 and 3 automatically, including health check polling and token generation between steps.