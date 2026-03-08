# Elastic Stack Configuration Guide (Best Practices)

To manage audit logs efficiently in production, we use the **Composable Index Template** approach. This modular strategy ensures reusability and scalability.

## 1. Index Lifecycle Management (ILM)
Define how long data stays in the cluster before being deleted or moved to cheaper storage.

**Endpoint:** `PUT _ilm/policy/audit-logs-policy`
```json
{
  "policy": {
    "phases": {
      "hot": {
        "actions": { "rollover": { "max_primary_shard_size": "50gb", "max_age": "30d" } }
      },
      "delete": {
        "min_age": "90d",
        "actions": { "delete": {} }
      }
    }
  }
}
```

## 2. Component Templates
Reusable "building blocks" for settings and mappings. Use these to avoid duplicating configurations.

### A. Settings Component (Shards, Replicas, ILM)
**Endpoint:** `PUT _component_template/audit-settings`
```json
{
  "template": {
    "settings": {
      "index.lifecycle.name": "audit-logs-policy",
      "index.number_of_shards": 1,
      "index.number_of_replicas": 1
    }
  }
}
```

### B. Mappings Component (ECS Standard)
**Endpoint:** `PUT _component_template/audit-mappings`
```json
{
  "template": {
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "event.action": { "type": "keyword" },
        "user.name": { "type": "keyword" }
      }
    }
  }
}
```

## 3. Composable Index Template
Ties the components together and defines which indices/data streams they apply to.

**Endpoint:** `PUT _index_template/audit-logs-template`
```json
{
  "index_patterns": ["audit-logs*"],
  "data_stream": { },
  "composed_of": ["audit-settings", "audit-mappings"],
  "priority": 500
}
```

## 4. Data Streams (The Modern Way)
For time-series data (logs/metrics), always use **Data Streams** instead of raw indices. Data streams automatically manage rollovers via ILM.

*   **Create/Append:** `POST audit-logs-app/_doc`
*   **Stats:** `GET _data_stream/audit-logs-app`

---

## Expert Tips for "Think Smarter"
1.  **Always use ECS:** Stick to [Elastic Common Schema](https://www.elastic.co/guide/en/ecs/current/index.html) fields (e.g., `user.name`, not `userName`).
2.  **Avoid Mapping Explosions:** Set `index.mapping.total_fields.limit` if your logs have thousands of unique fields.
3.  **Use Refresh Intervals:** For high-volume logs, set `"index.refresh_interval": "30s"` to improve indexing performance.
4.  **Keyword vs Text:** Never use `text` for fields you only filter or aggregate (like `status` or `id`). Use `keyword`.