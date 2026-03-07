import logging
import ecs_logging
import os

def get_audit_logger():
    logger = logging.getLogger("audit-app")
    if not logger.handlers:
        logger.setLevel(logging.INFO)

        # Đảm bảo thư mục log tồn tại
        log_dir = '/var/log/demo-app'
        if not os.path.exists(log_dir):
            try:
                os.makedirs(log_dir, exist_ok=True)
            except Exception:
                # Nếu không tạo được (vd: local dev), dùng thư mục hiện tại
                log_dir = '.'
        
        log_path = os.path.join(log_dir, 'audit_simulation.json')

        # Ghi log ra file định dạng JSON
        file_handler = logging.FileHandler(log_path)
        file_handler.setFormatter(ecs_logging.StdlibFormatter())
        logger.addHandler(file_handler)

        # Ghi log ra console để dễ debug qua `docker compose logs`
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(ecs_logging.StdlibFormatter())
        logger.addHandler(console_handler)
        
    return logger

# Create an instance logger to share across the entire app
audit_logger = get_audit_logger()
