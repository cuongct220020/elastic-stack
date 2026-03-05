import logging
import ecs_logging

def get_audit_logger():
    logger = logging.getLogger("audit-app")
    if not logger.handlers:
        logger.setLevel(logging.INFO)

        # Ghi log ra file định dạng JSON (Filebeat sẽ đọc file này)
        file_handler = logging.FileHandler('audit_simulation.json')
        file_handler.setFormatter(ecs_logging.StdlibFormatter())
        logger.addHandler(file_handler)

        # Ghi log ra console để dễ debug qua `docker compose logs`
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(ecs_logging.StdlibFormatter())
        logger.addHandler(console_handler)
        
    return logger

# Tạo instance logger dùng chung cho toàn ứng dụng
audit_logger = get_audit_logger()
