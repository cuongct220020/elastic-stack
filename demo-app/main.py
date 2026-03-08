from contextlib import asynccontextmanager
from fastapi import FastAPI

from database import db_instance
from logger import audit_logger
from document_apis import router as document_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Start System
    db_instance.connect()
    audit_logger.info("Application startup: Connected to MongoDB", extra={"event.action": "app_startup", "event.category": ["process"]})
    
    yield
    
    # Shutdown System
    db_instance.close()
    audit_logger.info("Application shutdown: Disconnected from MongoDB", extra={"event.action": "app_shutdown", "event.category": ["process"]})

app = FastAPI(lifespan=lifespan, title="Demo Audit CRUD App")

# Register Route
app.include_router(document_router)

@app.get("/health", tags=["System"])
async def health_check():
    """This endpoint is for Docker/Nginx healthcheck"""
    return {"status": "ok", "message": "Service is running"}