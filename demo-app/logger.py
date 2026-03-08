import logging
import ecs_logging
import os
import socket

from fastapi import Request
from schemas import DocumentSchema

def get_audit_logger():
    logger = logging.getLogger("audit-app")
    if not logger.handlers:
        logger.setLevel(logging.INFO)

        log_dir = os.getenv("APP_LOG_DIR", '/var/log/demo-app')
        
        if not os.path.exists(log_dir):
            try:
                os.makedirs(log_dir, exist_ok=True)
            except Exception:
                # Fallback to current directory for local dev outside docker
                log_dir = '.'
        
        # Generate a unique log file per container instance based on hostname
        # This prevents write-conflicts when scaling demo-app=3
        hostname = socket.gethostname()
        log_path = os.path.join(log_dir, f'logs_audit_{hostname}.json')

        # Write to JSON file formatted by ecs_logging
        file_handler = logging.FileHandler(log_path)
        file_handler.setFormatter(ecs_logging.StdlibFormatter())
        logger.addHandler(file_handler)

        # Write to console for easy debugging via `docker compose logs`
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(ecs_logging.StdlibFormatter())
        logger.addHandler(console_handler)
        
    return logger

# Create an instance logger to share across the entire app
audit_logger = get_audit_logger()

def log_audit_event(
    action: str,
    request: Request,
    user_id: str,
    document: DocumentSchema | None,
    outcome: str = "success",
    message: str = ""
):
    """
    Helper function to generate and record an ECS-compliant audit log.
    """
    
    # 1. Extract Real IP (Handles Nginx reverse proxy 'X-Forwarded-For')
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        client_ip = forwarded_for.split(',')[0].strip()
    else:
        client_ip = request.client.host if request.client else "unknown"

    # 2. Build the ECS extra dictionary
    ecs_extra = {
        "event": {
            "action": action, 
            "category": ["database", "web"],
            "type": ["access", "change"] if document else ["access"],
            "outcome": outcome
        },
        "user": {
            "id": user_id
        },
        "source": {
            "ip": client_ip
        },
        "http": {
            "request": {
                "method": request.method
            }
        },
        "url": {
            "path": request.url.path
        },
        "user_agent": {
            "original": request.headers.get("User-Agent", "unknown")
        },
        "service": {
            "name": "document-api"
        }
    }

    # 3. Add Resource & Target details if a document is involved
    if document:
        ecs_extra["resource"] = {
            "id": document.id,
            "type": "document",
            "name": document.title
        }
        
        # Cross-user action tracking (A modifies B's document)
        if document.owner_id != user_id:
            ecs_extra["user"]["target"] = {"id": document.owner_id}
            
        # Track the current state of the document (Soft Delete)
        ecs_extra["labels"] = {
            "is_deleted": document.is_deleted
        }

    # 4. Generate the log entry
    log_message = message or f"User '{user_id}' performed '{action}'"
    if document:
         log_message += f" on document '{document.id}'"

    audit_logger.info(log_message, extra=ecs_extra)