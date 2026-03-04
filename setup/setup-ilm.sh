#!/bin/bash

# 1. Tạo Policy: "crypto_policy"
# - Giữ dữ liệu nóng trong 30 ngày (Hot)
# - Xóa dữ liệu sau 90 ngày (Delete)
curl -X PUT "http://localhost:9200/_ilm/policy/crypto_policy" -H 'Content-Type: application/json' -d'
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_age": "30d",
            "max_size": "50gb"
          }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}'

# 2. Tạo Index Template: Áp dụng Policy này cho tất cả index có tên bắt đầu bằng "crypto-*"
curl -X PUT "http://localhost:9200/_index_template/crypto_template" -H 'Content-Type: application/json' -d'
{
  "index_patterns": ["crypto-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "crypto_policy",
      "index.lifecycle.rollover_alias": "crypto-data"
    }
  }
}'

# 3. Bootstrap Index đầu tiên (Bước khởi tạo quan trọng)
# Tạo index đầu tiên là "crypto-000001" và gán Alias "crypto-data" cho nó
curl -X PUT "http://localhost:9200/crypto-000001" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "crypto-data": {
      "is_write_index": true
    }
  }
}'