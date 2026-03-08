FROM nginx:1.25

# Cài đặt openssl để sinh chứng chỉ tự ký
RUN apt-get update && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

# Tạo thư mục chứa chứng chỉ
RUN mkdir -p /etc/nginx/ssl

# Sinh chứng chỉ tự ký (Self-Signed Certificate) có giá trị 365 ngày
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/self-signed.key \
    -out /etc/nginx/ssl/self-signed.crt \
    -subj "/C=VN/ST=Hanoi/L=Hanoi/O=DemoApp/OU=IT/CN=localhost"

# Copy file cấu hình (nếu bạn dùng lệnh COPY trong Dockerfile thay vì bind mount)
# Trong compose bạn đang bind mount nginx.conf nên có thể bỏ qua bước COPY ở đây
