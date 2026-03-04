import logging
import ecs_logging
import time
from random import randint

logger = logging.getLogger("audit-sim")
logger.setLevel(logging.INFO)
handler = logging.FileHandler('audit_simulation.json')
handler.setFormatter(ecs_logging.StdlibFormatter())
logger.addHandler(handler)

while True:
    # Mô phỏng các sự kiện kiểm toán khác nhau
    logger.info("User 'admin' changed system configuration",
                extra={"event.action": "config_change", "user.name": "admin"})
    time.sleep(randint(1, 5))