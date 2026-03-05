FROM python:3.14-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Chạy ứng dụng FastAPI ở port 1337 (khớp với cấu hình nginx proxy_pass)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "1337"]