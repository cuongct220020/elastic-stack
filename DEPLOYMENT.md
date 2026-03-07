# Manual Deployment Guide

```bash
docker compose -f elk-multi-node-cluster.yml build
docker compose -f fleet-compose.yml build

docker compose -f elk-multi-node-cluster.yml up -d
docker compose -f fleet-compose.yml up -d

docker compose -f elk-multi-node-cluster.yml up -d --build
docker compose -f fleet-compose.yml up -d --build
```

```bash
export ELASTIC_PASSWORD=$(grep ^ELASTIC_PASSWORD .env | cut -d= -f2)

CA_PATH=$(docker inspect es-01 --format='{{range .Mounts}}{{if eq .Destination "/usr/share/elasticsearch/config/certs"}}{{.Source}}{{end}}{{end}}')/ca/ca.crt

# Delete token
curl -sk -u elastic:${ELASTIC_PASSWORD} \
  --cacert $CA_PATH \
  -X DELETE "https://localhost:9200/_security/service/elastic/fleet-server/credential/token/fleet-token" \
  | python3 -m json.tool

# Create token
curl -sk -u elastic:${ELASTIC_PASSWORD} \
  --cacert $CA_PATH \
  -X POST "https://localhost:9200/_security/service/elastic/fleet-server/credential/token/fleet-token" \
  | python3 -m json.tool
```