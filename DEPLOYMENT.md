# Manual Deployment Guide

## Prereqs (chạy 1 lần trên host)
Nếu không 

```bash
# Tăng vm.max_map_count cho Elasticsearch (Linux Only)
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# Kiểm tra Docker Compose plugin
docker compose version   # cần >= 2.20
```


## Phase 1 — Bootstrap Core (Elasticsearch + Kibana)

### Bước 1 — Chuẩn bị .env

```bash
# Đổi passwords mạnh hơn trong production
vi .env

# Tạo 3 encryption keys khác nhau (QUAN TRỌNG với production)
openssl rand -hex 32   # chạy 3 lần, paste vào KIBANA_ENCRYPTION_KEY / REPORTING_KEY / SECURITY_KEY
```

### Bước 2 — Build images

```bash
docker compose -f elk-multi-node-cluster.yml build
docker compose -f fleet-compose.yml build

```

### Bước 3 — Khởi động Phase 1

```bash
docker compose -f elk-multi-node-cluster.yml up -d
```


### Bước 6 — Lấy Fleet Server Service Token

**Cách 1 — qua API (khuyến nghị cho automation):**

```bash
docker exec es-01 curl -sf -X POST \
  --cacert config/certs/ca/ca.crt \
  -u "elastic:cuongct123123" \
  "https://localhost:9200/_security/service/elastic/fleet-server/credential/token/fleet-token-1" \
  | python3 -m json.tool
```

Copy giá trị `token.value` → paste vào `FLEET_SERVER_SERVICE_TOKEN` trong `.env`.

**Cách 2 — qua Kibana UI:**
1. Kibana → Management → Fleet → Settings
2. Click **Generate service token**
3. Copy token → paste vào `.env`

### Bước 7 — Tạo Fleet Server Policy trên Kibana

1. Kibana → Fleet → Agent policies → **Create agent policy**
2. Đặt tên: `fleet-server-policy`
3. Không cần thêm integrations cho Fleet Server
4. Copy Policy ID → paste vào `FLEET_SERVER_POLICY_ID` trong `.env` (nếu khác default)

### Bước 8 — Khởi động Fleet Server

```bash
docker compose -f fleet-compose.yml up -d fleet-server

# Theo dõi log
docker logs -f fleet-server
# Kỳ vọng: "State changed to HEALTHY"
```

### Bước 9 — Lấy Enrollment Token cho Elastic Agent

1. Kibana → Fleet → Enrollment tokens
2. Click **Create enrollment token**
3. Chọn policy cho agent (ví dụ: `audit-log-policy`)
4. Copy token → paste vào `ELASTIC_AGENT_ENROLLMENT_TOKEN` trong `.env`

**Hoặc qua API:**
```bash
curl -sf \
  --cacert <(docker exec es-01 cat config/certs/ca/ca.crt) \
  -u "elastic:cuongct123123" \
  "https://localhost:9200/api/fleet/enrollment_api_keys" \
  -H "kbn-xsrf: true"
```

### Bước 10 — Deploy Elastic Agents

```bash
# Deploy 1 agent (mặc định)
docker compose -f fleet-compose.yml up -d elastic-agent

# Scale lên nhiều agents
docker compose -f fleet-compose.yml up -d --scale elastic-agent=3
```

### Bước 11 — Xác nhận agents đã enrolled

```bash
# Kiểm tra trong Kibana
# Fleet → Agents — phải thấy agent(s) với status "Healthy"

# Hoặc qua API
curl -sf \
  -u "elastic:cuongct123123" \
  "https://localhost:9200/api/fleet/agents" | python3 -m json.tool
```

---

## Thiết lập Audit Log Integration

### Bước 12 — Thêm System / Audit integration

1. Kibana → Fleet → Agent policies → chọn policy của agent
2. **Add integration** → tìm **"System"** hoặc **"Auditd Logs"**
3. Cấu hình đường dẫn log (mặc định `/var/log/audit/audit.log`)
4. Save → agents sẽ tự nhận config mới

---

## Vận hành thường ngày

```bash
# Xem status tất cả
docker compose -f fleet-compose.yml ps

# Restart một service
docker compose restart kibana

# Xem logs realtime
docker compose logs -f es-01
docker logs -f fleet-server

# Scale agents
docker compose -f fleet-compose.yml up -d --scale elastic-agent=5

# Dừng toàn bộ (giữ data)
docker compose down
docker compose -f fleet-compose.yml down

# Xoá hoàn toàn (XOÁ DATA — cẩn thận!)
docker compose down -v
```

---

## Troubleshooting

| Triệu chứng | Nguyên nhân thường gặp | Fix |
|-------------|----------------------|-----|
| ES không green | `vm.max_map_count` thấp | `sudo sysctl -w vm.max_map_count=262144` |
| Setup loop | ES chưa ready | Đợi thêm, xem `docker logs elastic-setup` |
| Fleet UNHEALTHY | Token sai / hết hạn | Tạo lại service token |
| Agent không enroll | Enrollment token sai | Tạo lại token trong Kibana |
| OOM kill | Heap quá lớn | Giảm `ES_HEAP_SIZE`, tăng `ES_MEM_LIMIT` |

### Reset hoàn toàn (dev/test)

```bash
docker compose -f docker-compose.fleet.yml down -v 2>/dev/null; true
docker compose down -v
docker volume prune -f
```

cuongct090_04@MacBook-Air-cua-Cuong-CT elastic-stack % docker cp es-01:/usr/share/elasticsearch/config/certs/ca/ca.crt /tmp/ca.crt

Successfully copied 3.07kB to /tmp/ca.crt
cuongct090_04@MacBook-Air-cua-Cuong-CT elastic-stack % openssl x509 -fingerprint -sha256 -noout -in /tmp/ca.crt | sed 's/.*=//' | tr -d ':'
93BD388E323A8DB9963861B0CC8A0F85BC00E97CC15A0BB938A233041A99ED05
