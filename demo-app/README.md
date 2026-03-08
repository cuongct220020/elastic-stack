# FastAPI Documentation Management App

Bài toán ở đây là một kho dữ liệu tập trung, và ai cũng có thể xem trong DB hiện tại có bao nhiêu document,
ai cũng có quyền tạo mới document, ai cũng có toàn quyền đối document, ví dụ như ai cũng có quyền chỉnh sửa tài liệu của người khác, thậm chí là xoá.
Và mục tiêu đặt ra là chúng ta sẽ audit hành vi của người dùng. 
ý tưởng ở đây là nếu một tài liệu bị xoá nó chỉ bị đánh dấu là xoá và không được sử dụng nữa nhưng trong DB vẫn còn. Endpoint GET thì có nhiều parameter, 1 là list những document mà mình sở hữu, 2 list cả những cái bị xoá. 


Audit logs often basd on 5W / 6W mindset: 
```
Who    → user.id
What   → event.action
When   → @timestamp
Where  → source.ip
Why    → reason (optional)
How    → event.type / http.method
```

Todolist: 
- Định nghĩa lại schema, index template, component template cho bài toán audit logs.
- Triển khai FastAPI application. 
- Phân tích Logs trên Kibana. 

Lưu ý về việc ghi log:
- Với Nginx, MongoDB thì không cần ghi log ra file. 
- Với Demo-app thì các logs liên quan đến vòng đời ứng dụng thì ghi ra console, 
còn các logs liên quan đến audit logs thì khi ra file .json để 

## Audit Log Document Example

```
{
  "@timestamp": "2026-03-07T10:00:21Z",

  "event": {
    "action": "create_document",
    "category": "database",
    "type": "creation",
    "outcome": "success"
  },

  "user": {
    "id": "cuong"
    "target": "cuong"
  },

  "source": {
    "ip": "172.18.0.1"
  },

  "http": {
    "request": {
      "method": "POST"
    }
  },

  "url": {
    "path": "/documents"
  },

  "service": {
    "name": "document-api"
  },

  "resource": {
    "id": "65f1a9c8",
    "type": "document",
    "name": "document title"
  }
}
```

# 4 endpoint duy nhất

| Method | Endpoint       | Action          |
| ------ | -------------- | --------------- |
| POST   | /documents     | create document |
| GET    | /documents     | list documents  |
| PUT    | /documents/:id | update document |
| DELETE | /documents/:id | delete document |



# 9. Dashboard Kibana đơn giản

Sau khi ingest logs, bạn có thể show:

- actions per minute

- action distribution (pie chart)

- activity timeline (requests over time)

```
docker volume create app-logs
```