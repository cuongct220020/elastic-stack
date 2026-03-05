#!/bin/bash

curl -sf \
  --cacert <(docker exec es-01 cat config/certs/ca/ca.crt) \
  -u "elastic:cuongct123123" \
  "https://localhost:9200/api/fleet/enrollment_api_keys" \
  -H "kbn-xsrf: true"