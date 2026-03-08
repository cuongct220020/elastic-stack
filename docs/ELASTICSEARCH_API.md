# Elasticsearch API Cookbook

A practical reference for common Elasticsearch API operations used when working with this stack. All examples use `curl` against `es-01` from outside the container. Replace `$ELASTIC_PASSWORD` with the value from your `.env` file.

```bash
# Shorthand used throughout this file
ES="https://localhost:9200"
AUTH="-u elastic:$ELASTIC_PASSWORD --cacert /path/to/certs/ca/ca.crt"
```

Alternatively, use **Kibana Dev Tools** (Management > Dev Tools) to run any of these queries without dealing with curl, certificates, or auth headers — just paste the method and path directly.


## Cluster

### Check cluster health

```bash
curl -s $ES/_cluster/health?pretty $AUTH
```

Status meanings:
- `green` — all primary and replica shards are assigned
- `yellow` — all primaries assigned, but some replicas are not (common on a fresh single-node setup or when a node is down)
- `red` — one or more primary shards are not assigned; data may be missing

### List all nodes

```bash
curl -s "$ES/_cat/nodes?v&h=name,role,heap.percent,ram.percent,cpu,load_1m,node.role" $AUTH
```

### Check shard allocation

```bash
curl -s "$ES/_cat/shards?v&s=state" $AUTH
```

Useful when cluster is yellow — look for shards with state `UNASSIGNED` and check the reason:

```bash
curl -s "$ES/_cluster/allocation/explain?pretty" $AUTH
```

### Check cluster settings

```bash
curl -s "$ES/_cluster/settings?pretty&include_defaults=false" $AUTH
```


## Indices and Data Streams

### List all indices

```bash
curl -s "$ES/_cat/indices?v&s=index" $AUTH
```

### List all data streams

```bash
curl -s "$ES/_data_stream?pretty" $AUTH
```

### Inspect a specific data stream

```bash
curl -s "$ES/_data_stream/logs-audit-app?pretty" $AUTH
```

### Get data stream stats (document count, store size)

```bash
curl -s "$ES/_data_stream/logs-audit-app/_stats?pretty" $AUTH
```

### List backing indices of a data stream

```bash
curl -s "$ES/_data_stream/logs-audit-app?pretty" $AUTH | jq '.data_streams[].indices'
```

### Delete a data stream (deletes all backing indices and documents)

```bash
curl -X DELETE "$ES/_data_stream/logs-audit-app" $AUTH
```

Use this when the data stream was created before the index template was applied and you need to recreate it with correct mappings.


## Mappings and Templates

### Check the mapping of a data stream

```bash
curl -s "$ES/logs-audit-app/_mapping?pretty" $AUTH
```

### Check which index template applies to a given index name

```bash
curl -s "$ES/_index_template/audit-logs-template?pretty" $AUTH
```

### List all component templates

```bash
curl -s "$ES/_component_template?pretty" $AUTH
```

### Simulate what template would apply to a given index name

```bash
curl -s "$ES/_index_template/_simulate_index/logs-audit-app?pretty" $AUTH
```

Useful for verifying that settings and mappings are applied as expected before the first document is written.


## Ingest Pipelines

### List all ingest pipelines

```bash
curl -s "$ES/_ingest/pipeline?pretty" $AUTH
```

### Inspect a specific pipeline

```bash
curl -s "$ES/_ingest/pipeline/audit-logs-pipeline?pretty" $AUTH
```

### Test a pipeline against a sample document

```bash
curl -X POST "$ES/_ingest/pipeline/audit-logs-pipeline/_simulate?pretty" $AUTH \
  -H "Content-Type: application/json" \
  -d '{
    "docs": [
      {
        "_source": {
          "message": "{\"@timestamp\":\"2026-03-07T10:00:21Z\",\"event\":{\"action\":\"create_doc\"},\"user\":{\"id\":\"alice\"},\"source\":{\"ip\":\"172.18.0.1\"}}"
        }
      }
    ]
  }'
```

This is the fastest way to verify that the pipeline parses and transforms documents correctly before committing to a full ingestion run.


## ILM (Index Lifecycle Management)

### Check the ILM policy

```bash
curl -s "$ES/_ilm/policy/audit-logs-policy?pretty" $AUTH
```

### Check the current ILM phase of a data stream's backing indices

```bash
curl -s "$ES/_cat/indices/logs-audit-app-*?v&h=index,ilm.phase,ilm.action,ilm.step" $AUTH
```

### Check ILM status for a specific index

```bash
curl -s "$ES/logs-audit-app-000001/_ilm/explain?pretty" $AUTH
```

### Manually trigger ILM to move an index to the next step

```bash
curl -X POST "$ES/_ilm/move/logs-audit-app-000001" $AUTH \
  -H "Content-Type: application/json" \
  -d '{
    "current_step": { "phase": "hot", "action": "rollover", "name": "check-rollover-ready" },
    "next_step":    { "phase": "warm", "action": "forcemerge", "name": "forcemerge" }
  }'
```

Use this in development to test lifecycle transitions without waiting for the real age/size thresholds.

### Manually trigger a rollover

```bash
curl -X POST "$ES/logs-audit-app/_rollover" $AUTH
```


## Querying Documents

### Search all documents in a data stream

```bash
curl -s "$ES/logs-audit-app/_search?pretty" $AUTH \
  -H "Content-Type: application/json" \
  -d '{"query": {"match_all": {}}, "size": 5}'
```

### Filter by a specific user

```bash
curl -s "$ES/logs-audit-app/_search?pretty" $AUTH \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "term": { "user.id": "alice" }
    }
  }'
```

### Filter by action and time range

```bash
curl -s "$ES/logs-audit-app/_search?pretty" $AUTH \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "bool": {
        "must": [
          { "term": { "event.action": "soft_delete_doc" } },
          { "range": { "@timestamp": { "gte": "now-24h" } } }
        ]
      }
    }
  }'
```

### Count events grouped by action (aggregation)

```bash
curl -s "$ES/logs-audit-app/_search?pretty" $AUTH \
  -H "Content-Type: application/json" \
  -d '{
    "size": 0,
    "aggs": {
      "actions": {
        "terms": { "field": "event.action" }
      }
    }
  }'
```

### Find cross-user actions (user modifying another user's document)

```bash
curl -s "$ES/logs-audit-app/_search?pretty" $AUTH \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "exists": { "field": "user.target.id" }
    }
  }'
```


## Index Operations

### Force a rollover on a data stream

```bash
curl -X POST "$ES/logs-audit-app/_rollover" $AUTH
```

### Force-merge an index (reduce segment count)

```bash
curl -X POST "$ES/logs-audit-app-000001/_forcemerge?max_num_segments=1" $AUTH
```

### Make an index read-only

```bash
curl -X PUT "$ES/logs-audit-app-000001/_settings" $AUTH \
  -H "Content-Type: application/json" \
  -d '{"index.blocks.write": true}'
```

### Refresh an index (make recently indexed documents searchable immediately)

```bash
curl -X POST "$ES/logs-audit-app/_refresh" $AUTH
```