from contextlib import asynccontextmanager
from fastapi import FastAPI

from database import db_instance
from logger import audit_logger
from routers import items

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Hệ thống khởi động
    db_instance.connect()
    audit_logger.info("Application startup: Connected to MongoDB", extra={"event.action": "app_startup", "event.category": ["process"]})
    
    yield
    
    # Hệ thống tắt
    db_instance.close()
    audit_logger.info("Application shutdown: Disconnected from MongoDB", extra={"event.action": "app_shutdown", "event.category": ["process"]})

app = FastAPI(lifespan=lifespan, title="Demo Audit CRUD App")

# Đăng ký các module API
app.include_router(items.router)

@app.get("/health", tags=["System"])
async def health_check():
    """Endpoint dùng cho Docker/Nginx healthcheck"""
    return {"status": "ok", "message": "Service is running"}