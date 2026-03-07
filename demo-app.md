Đúng hướng 👍. Vì mục tiêu của bạn chỉ là **thử nghiệm ELK cho audit logs**, nên backend **không nên giống production**. Ta cần **cực kỳ tối giản** để:

* dễ generate logs
* dễ ingest vào Elasticsearch
* dễ demo Kibana

Vì vậy ta **loại bỏ nhiều thứ rườm rà** như:

❌ authentication
❌ role
❌ verify workflow
❌ business logic phức tạp
❌ nhiều collection

Chỉ giữ:

* CRUD
* MongoDB
* Nginx
* structured logs

---

# 1. Nghiệp vụ tối giản của app

App chỉ quản lý **documents**.

Document chỉ có:

```json
{
  "_id": "ObjectId",
  "title": "string",
  "content": "string",
  "created_at": "timestamp"
}
```

Không có:

* user
* permission
* verification workflow

---

# 2. 4 endpoint duy nhất

| Method | Endpoint       | Action          |
| ------ | -------------- | --------------- |
| POST   | /documents     | create document |
| GET    | /documents     | list documents  |
| PUT    | /documents/:id | update document |
| DELETE | /documents/:id | delete document |

Đây là **CRUD chuẩn nhất**.

---

# 3. Audit log cực kỳ đơn giản

Mỗi request chỉ log:

```json
{
  "timestamp": "...",
  "method": "POST",
  "endpoint": "/documents",
  "action": "CREATE_DOCUMENT",
  "document_id": "...",
  "status": "SUCCESS"
}
```

Chỉ cần **5 field**.

| field       | purpose        |
| ----------- | -------------- |
| timestamp   | timeline       |
| action      | loại hành động |
| document_id | resource       |
| method      | HTTP method    |
| status      | SUCCESS/ERROR  |

Đủ để phân tích trên Kibana.

---

# 4. Kiến trúc hệ thống demo

Cực kỳ đơn giản:

```text
Client
   │
   ▼
Nginx
   │
   ▼
Backend API
   │
   ▼
MongoDB
```

Song song:

```text
Backend logs (stdout)
        │
        ▼
Elastic Agent
        │
        ▼
Elasticsearch
        │
        ▼
Kibana
```

---

# 5. Backend cực đơn giản (Node.js Express)

Một file duy nhất.

```javascript
const express = require("express")
const mongoose = require("mongoose")

const app = express()
app.use(express.json())

mongoose.connect("mongodb://mongo:27017/demo")

const Document = mongoose.model("Document", {
  title: String,
  content: String,
  created_at: Date
})

function log(event) {
  console.log(JSON.stringify({
    timestamp: new Date(),
    ...event
  }))
}
```

---

## Endpoint 1 — CREATE

```javascript
app.post("/documents", async (req, res) => {

  const doc = await Document.create({
    title: req.body.title,
    content: req.body.content,
    created_at: new Date()
  })

  log({
    action: "CREATE_DOCUMENT",
    document_id: doc._id,
    method: "POST",
    endpoint: "/documents",
    status: "SUCCESS"
  })

  res.json(doc)
})
```

---

## Endpoint 2 — READ

```javascript
app.get("/documents", async (req, res) => {

  const docs = await Document.find()

  log({
    action: "LIST_DOCUMENT",
    method: "GET",
    endpoint: "/documents",
    status: "SUCCESS"
  })

  res.json(docs)
})
```

---

## Endpoint 3 — UPDATE

```javascript
app.put("/documents/:id", async (req, res) => {

  const doc = await Document.findByIdAndUpdate(
    req.params.id,
    req.body
  )

  log({
    action: "UPDATE_DOCUMENT",
    document_id: req.params.id,
    method: "PUT",
    endpoint: "/documents/:id",
    status: "SUCCESS"
  })

  res.json(doc)
})
```

---

## Endpoint 4 — DELETE

```javascript
app.delete("/documents/:id", async (req, res) => {

  await Document.deleteOne({ _id: req.params.id })

  log({
    action: "DELETE_DOCUMENT",
    document_id: req.params.id,
    method: "DELETE",
    endpoint: "/documents/:id",
    status: "SUCCESS"
  })

  res.sendStatus(204)
})
```

---

# 6. Tại sao log ra stdout

Bạn nên **log ra stdout**:

```javascript
console.log(JSON.stringify(log))
```

vì Elastic Agent / Filebeat dễ thu thập:

```text
docker container logs
```

---

# 7. Nginx config đơn giản

Nginx chỉ làm reverse proxy.

```nginx
server {
  listen 80;

  location / {
    proxy_pass http://backend:3000;
  }
}
```

Nginx cũng sinh **access logs**.

Ví dụ:

```
POST /documents 200
GET /documents 200
DELETE /documents/123 204
```

→ ingest thêm vào ELK nếu muốn.

---

# 8. Data để demo Kibana

Bạn chỉ cần spam requests.

```bash
for i in {1..50}
do
curl -X POST localhost/documents \
-H "Content-Type: application/json" \
-d '{"title":"doc","content":"hello"}'
done
```

---

# 9. Dashboard Kibana đơn giản

Sau khi ingest logs, bạn có thể show:

### 1️⃣ actions per minute

```
CREATE_DOCUMENT
UPDATE_DOCUMENT
DELETE_DOCUMENT
```

---

### 2️⃣ action distribution

```
pie chart
```

---

### 3️⃣ activity timeline

```
requests over time
```

---

# 10. Cấu trúc repo đơn giản nhất

```text
elastic-stack/
│
├─ backend
│   └─ app.js
│
├─ nginx
│   └─ nginx.conf
│
├─ docker-compose.yml
│
└─ elastic
```

Backend chỉ **~80 dòng code**.

---

# 11. Triết lý demo ELK

App của bạn không phải product.

App chỉ là:

```text
log generator
```

để test:

* log ingestion
* log parsing
* dashboard Kibana

---

✅ **Tóm lại app tối giản sẽ có**

* 1 service backend
* 4 endpoints CRUD
* MongoDB
* Nginx
* structured JSON logs

Tổng code backend **<100 dòng**.

---

💡 Nếu bạn muốn, mình có thể giúp bạn luôn **thiết kế một repo demo ELK chuẩn mà DevOps hay dùng (chỉ ~5 phút chạy được toàn bộ stack)**.
Nó sẽ giúp **repo của bạn nhìn rất “xịn” khi demo với leader**.
