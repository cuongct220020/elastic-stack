# Checklist: Triển khai Elastic Observability

Tài liệu này đóng vai trò là bản thiết kế (blueprint) và danh sách kiểm tra (checklist) để biến hệ thống hiện tại (Elasticsearch, Kibana, Fleet, `demo-app`) thành một hệ thống có khả năng **Observability** (Quan sát) toàn diện, bao gồm cả 3 trụ cột: **Logs, Metrics, và Traces (APM)**.

---

## Giai đoạn 1: Chuẩn bị Cơ sở hạ tầng (Infrastructure Observability)
Mục tiêu: Thu thập Metrics (CPU, RAM, Network) và Logs từ Docker, Nginx, MongoDB.

- [ ] **1.1. Cấu hình Elastic Agent nhận diện Docker**
  - [ ] Đảm bảo Elastic Agent container có quyền truy cập vào file `docker.sock` của máy host (mount volume `- /var/run/docker.sock:/var/run/docker.sock:ro` trong file `fleet-compose.yml`).
  - [ ] Trên Kibana Fleet, cài đặt **Docker Integration**. Cấu hình để thu thập cả `metrics` (stat của container) và `logs` (console output của `demo-app` và `mongodb`).

- [ ] **1.2. Cấu hình giám sát Nginx (Nginx Integration)**
  - [ ] Mở file `nginx/config/nginx.conf`. Thêm một block `server` hoặc `location` ẩn để bật tính năng `stub_status` của Nginx (giúp phơi bày metrics).
    ```nginx
    server {
        listen 8080;
        location /nginx_status {
            stub_status on;
            access_log off;
            allow 127.0.0.1; # Chỉ cho phép Elastic Agent trong cùng mạng gọi vào
            allow 172.16.0.0/12; # Dải mạng Docker
            deny all;
        }
    }
    ```
  - [ ] Trên Kibana Fleet, cài đặt **Nginx Integration**. Trỏ đường dẫn metrics về `http://nginx:8080/nginx_status`.
  - [ ] Cấu hình Nginx Integration thu thập Access Logs và Error Logs. Đảm bảo parse đúng cấu trúc log.

- [ ] **1.3. Cấu hình giám sát MongoDB (MongoDB Integration)**
  - [ ] Tạo một user chỉ có quyền Read (monitor) trong MongoDB dành riêng cho Agent.
  - [ ] Trên Kibana Fleet, cài đặt **MongoDB Integration**. Nhập URI kết nối vào MongoDB để Elastic Agent bắt đầu kéo các chỉ số về QPS, Memory, Connections.

---

## Giai đoạn 2: Tích hợp Application Performance Monitoring (APM)
Mục tiêu: Đo lường thời gian xử lý của từng API, vẽ bản đồ truy vết (Distributed Tracing), và bắt các Exception (lỗi) từ code Python.

- [ ] **2.1. Khởi chạy APM Server thông qua Fleet**
  - [ ] Trong giao diện Kibana -> Fleet -> Agent Policies -> Chọn policy của Fleet Server.
  - [ ] Thêm Integration **Elastic APM**. Cấu hình để APM Server lắng nghe ở port `8200`.
  - [ ] Sửa file cấu hình docker compose chứa Fleet (ví dụ: `fleet-compose.yml`), phơi (expose) port `8200:8200` ra ngoài mạng Docker network chung để `demo-app` có thể gọi tới.

- [ ] **2.2. Nhúng APM Agent vào mã nguồn FastAPI (`demo-app`)**
  - [ ] Mở file `demo-app/requirements.txt`, thêm package: `elastic-apm[fastapi]==6.20.0` (hoặc bản mới nhất).
  - [ ] Mở `demo-app/config.py`, thêm các biến môi trường cho APM:
    ```python
    ELASTIC_APM_SERVER_URL = os.getenv("ELASTIC_APM_SERVER_URL", "http://fleet-server:8200")
    ELASTIC_APM_SECRET_TOKEN = os.getenv("ELASTIC_APM_SECRET_TOKEN", "")
    ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
    ```
  - [ ] Mở file `demo-app/main.py` và nhúng middleware APM:
    ```python
    from elasticapm.contrib.starlette import make_apm_client, ElasticAPM
    from config import ELASTIC_APM_SERVER_URL, ENVIRONMENT

    apm_client = make_apm_client({
        'SERVICE_NAME': 'demo-fastapi-audit',
        'SERVER_URL': ELASTIC_APM_SERVER_URL,
        'ENVIRONMENT': ENVIRONMENT,
    })
    app.add_middleware(ElasticAPM, client=apm_client)
    ```

- [ ] **2.3. Log Correlation (Gắn kết APM Traces và JSON Logs)**
  - Mục đích: Khi đang xem một Trace chậm trên Kibana, có thể bấm xem ngay dòng Log nào được in ra trong lúc xử lý Trace đó.
  - [ ] Thư viện `ecs_logging` trong file `demo-app/logger.py` thường tự động xử lý việc này nếu APM Agent đang chạy. Hãy kiểm tra file `audit_simulation.json` xem các trường `trace.id` và `transaction.id` có xuất hiện khi một request gọi qua FastAPI không. Nếu không, cần config thêm formatter của thư viện logging.

---

## Giai đoạn 3: Giám sát Uptime & Trải nghiệm người dùng (Synthetics)
Mục tiêu: Đóng vai người dùng bên ngoài, liên tục "ping" vào hệ thống để báo cáo trạng thái Sống/Chết (Up/Down) và độ trễ phản hồi.

- [ ] **3.1. Thiết lập Elastic Synthetics (Uptime)**
  - [ ] Trên Kibana -> Observability -> Uptime -> Add a monitor.
  - [ ] Cấu hình một **HTTP Monitor** (ping mỗi 1 phút hoặc 3 phút).
  - [ ] URL cần monitor: `https://<domain-cua-ban>/health` (gọi vào endpoint `/health` mà ta đã tạo trong FastAPI).
  - [ ] Thiết lập điều kiện: Nếu HTTP status trả về khác `200` hoặc thời gian phản hồi (latency) > `2000ms`, đánh dấu là DOWN.

---

## Giai đoạn 4: Thiết lập Cảnh báo (Alerting) & Bảng điều khiển (Dashboards)
Mục tiêu: Biến dữ liệu thu thập được thành giá trị thực tế (trực quan hóa và cảnh báo tự động).

- [ ] **4.1. Xây dựng Dashboards tổng hợp**
  - [ ] Tạo một Dashboard "Nginx Overview" lấy dữ liệu từ Nginx Integration.
  - [ ] Tạo một Dashboard "Audit Logs Security" chứa biểu đồ Pie chart về các hành động (`event.action`), Data table chứa danh sách IP gọi API, và số lượng User tham gia hệ thống.
  - [ ] Tạo một Dashboard "System Health" hiển thị CPU/RAM của các server chạy Docker.

- [ ] **4.2. Cấu hình Alerts (Kibana Rules)**
  - [ ] **Alert 1 (Hạ tầng):** Báo động qua Slack/Email nếu CPU của container `demo-app` vượt quá 80% trong 5 phút.
  - [ ] **Alert 2 (APM):** Báo động nếu tỷ lệ lỗi (Error Rate) của FastAPI vượt quá 5% tổng số request.
  - [ ] **Alert 3 (Bảo mật/Audit Logs):** Báo động ngay lập tức nếu phát hiện sự kiện `event.action: "user_deleted"` hoặc `event.action: "role_updated"` từ Audit Logs.
  - [ ] **Alert 4 (Uptime):** Báo động ngay khi Synthetics Monitor báo trạng thái DOWN (trang web sập).
