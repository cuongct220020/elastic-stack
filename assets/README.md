# Elasticsearch Configuration — Audit Logs

This directory contains all Elasticsearch configuration assets for the audit logs pipeline: ILM policies, component templates, index templates, and ingest pipelines.

The deployment script `scripts/setup_elastic_templates.sh` applies all of these to a running cluster in the correct order.


## Why Audit Logs Need a Dedicated Design

Audit log data has specific characteristics that require deliberate configuration:

- **Append-only.** Events are facts. They are never updated or corrected after being written.
- **Time-series.** Every query is anchored to `@timestamp`. Data access patterns change predictably over time: recent data is queried often, older data rarely.
- **Compliance retention.** Logs must be kept for a defined period before deletion — not indefinitely, but not arbitrarily either.
- **High write volume, low read volume on old data.** The storage and performance strategy should reflect this asymmetry.

These characteristics map to three Elasticsearch features used here: data streams (for time-series write management), ILM (for automated lifecycle transitions), and component templates with explicit mappings (for consistent field types and storage efficiency).


## Apply Order

Resources must be created in this order because each step depends on the previous one:

```
1. Ingest pipeline     → processes documents before indexing
2. ILM policy          → referenced by settings component template
3. Component templates → referenced by index template
4. Index template      → applied when the data stream is created
5. Data stream         → created automatically on first document write
```

Run the deployment script to apply all steps:

```bash
bash scripts/setup_elastic_templates.sh
```


## Ingest Pipeline — `audit-logs-pipeline`

**Endpoint:** `PUT _ingest/pipeline/audit-logs-pipeline`

The Elastic Agent ships each log line as a raw string in the `message` field. The pipeline transforms it into a structured document before indexing.

**Processors:**

1. `json` — parses `message` as JSON and merges all keys into the document root, so ECS fields like `event.action` and `user.id` are promoted to top-level and matched against the explicit mappings.
2. `user_agent` — expands `user_agent.original` into structured sub-fields (`user_agent.name`, `user_agent.os.name`, `user_agent.device.name`), enabling OS and browser breakdowns in Kibana without any changes to the application.
3. `remove` — strips `message`, `agent`, and `log.file.path` after parsing. These fields are noise in the final stored document and would consume storage without providing analytical value.


## ILM Policy — `audit-logs-policy`

**Endpoint:** `PUT _ilm/policy/audit-logs-policy`

Defines the full lifecycle of a backing index from creation to deletion.

| Phase | Trigger | Actions | Rationale |
|---|---|---|---|
| Hot | Immediately | Rollover at 50 GB or 30 days | Keeps the active write index bounded. Recent events are queried frequently; the hot tier should stay lean and fast. |
| Warm | 30 days after rollover | Force-merge to 1 segment, mark read-only | The index is now static — no more writes. Force-merging reduces open file handles and improves read performance on a fixed dataset. Read-only is consistent with the append-only nature of audit data. |
| Cold | 90 days after rollover | Deprioritize (priority 0) | Rarely accessed but must remain searchable. Cluster resources are redirected to hot and warm tiers. At this stage, indices can optionally be moved to a snapshot repository (MinIO) to free primary storage. |
| Delete | 365 days after rollover | Delete permanently | Default one-year retention window. To extend retention, update only the `min_age` on this phase. |

### MinIO and the Cold/Frozen Tier

`storage-compose.yml` brings up a MinIO instance configured as an S3-compatible snapshot repository. When indices reach the cold phase, Elasticsearch can take a searchable snapshot and store it in MinIO, then remove the local copy. This decouples long-term retention from primary cluster storage.

The MinIO bucket and Elasticsearch snapshot repository registration are set up separately after MinIO is running. The ILM policy and MinIO are independent — the policy works without MinIO, and MinIO can be added later to reduce storage costs on aged indices.


## Component Templates

The index template is split into two component templates to separate operational settings from field mappings. This makes it easier to reuse either component across multiple index templates in future (for example, a separate nginx logs template could share the same settings component).

### Settings — `audit-logs-settings`

**Endpoint:** `PUT _component_template/audit-logs-settings`

| Setting | Value | Reason |
|---|---|---|
| `number_of_shards` | 1 | Sufficient for the expected write volume of a single application |
| `number_of_replicas` | 1 | One replica provides read redundancy and tolerates a single node failure |
| `refresh_interval` | 5s | Relaxed from the 1s default to reduce I/O pressure. Near-real-time visibility with a few seconds delay is acceptable for audit use. |
| `codec` | best_compression | Audit logs contain highly repetitive keyword fields. Compression yields significant storage savings at minimal CPU cost. |
| `index.lifecycle.name` | audit-logs-policy | Attaches the ILM policy to every backing index created under this template. |
| `index.default_pipeline` | audit-logs-pipeline | Ensures every incoming document passes through the ingest pipeline. |

### Mappings — `audit-logs-mappings`

**Endpoint:** `PUT _component_template/audit-logs-mappings`

Explicit mappings are used instead of dynamic mapping for two reasons: to prevent type conflicts if field names are reused with different value types in future, and to ensure semantically meaningful types like `ip` are applied rather than defaulting to `keyword`.

Key mapping decisions:

- `source.ip` is mapped as `ip` (not `keyword`) to support CIDR range queries and IP subnet filtering in Kibana.
- `resource.name` is mapped as `text` with a `.raw` keyword sub-field. The `text` field enables full-text search on document titles; the `.raw` sub-field enables exact-match aggregations such as grouping events by document name in a Kibana visualization.
- All other string fields (`event.action`, `user.id`, `event.outcome`, etc.) are `keyword` because they are used exclusively for filtering and aggregation, not full-text search.


## Index Template — `audit-logs-template`

**Endpoint:** `PUT _index_template/audit-logs-template`

```json
{
  "index_patterns": ["logs-audit-*"],
  "data_stream": {},
  "priority": 500,
  "composed_of": ["audit-logs-settings", "audit-logs-mappings"]
}
```

The `logs-audit-*` pattern matches the data stream name used by the Elastic Agent integration. `priority: 500` ensures this template takes precedence over any lower-priority built-in templates that also match the `logs-*` namespace.

The `data_stream: {}` declaration tells Elasticsearch to treat matching indices as a data stream rather than a regular index. This enables automatic rollover management via ILM and ensures documents are always written to the current active backing index.


## Data Stream

The data stream `logs-audit-app` is created automatically when the first document is indexed. It does not need to be created manually.

To inspect the data stream after logs start flowing:

```bash
GET _data_stream/logs-audit-*
GET _data_stream/logs-audit-app/_stats
```