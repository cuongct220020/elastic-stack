#!/bin/bash

docker exec es-01 curl -sf -X POST \
  --cacert config/certs/ca/ca.crt \
  -u "elastic:cuongct123123" \
  "https://localhost:9200/_security/service/elastic/fleet-server/credential/token/fleet-token-1" \
  | python3 -m json.tool