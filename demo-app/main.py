import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI

from database import db_instance
from logger import audit_logger
from document_apis import router as document_router

# Use a standard logger for operational lifecycle events (stdout)
app_logger = logging.getLogger("uvicorn.error")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Start System
    db_instance.connect()
    app_logger.info("Application startup: Connected to MongoDB")
    
    yield
    
    # Shutdown System
    db_instance.close()
    app_logger.info("Application shutdown: Disconnected from MongoDB")

app = FastAPI(lifespan=lifespan, title="Demo Audit CRUD App")

# Register Route
app.include_router(document_router)

@app.get("/health", tags=["System"])
async def health_check():
    """This endpoint is for Docker/Nginx healthcheck"""
    return {"status": "ok", "message": "Service is running"}