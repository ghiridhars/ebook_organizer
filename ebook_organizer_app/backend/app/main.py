"""
FastAPI Backend for Ebook Organizer
Handles cloud storage integration, metadata extraction, and ebook management
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from pydantic import ValidationError
from contextlib import asynccontextmanager

from app.routes import ebooks, cloud, metadata, sync
from app.services.database import init_db
from app.logging_config import logger
from app.middleware import (
    RequestLoggingMiddleware,
    http_exception_handler,
    validation_exception_handler,
    generic_exception_handler,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events"""
    # Startup
    logger.info("Starting Ebook Organizer Backend...")
    init_db()
    logger.info("Database initialized")
    yield
    # Shutdown
    logger.info("Shutting down Ebook Organizer Backend...")


app = FastAPI(
    title="Ebook Organizer API",
    description="Backend API for multi-platform ebook organization with cloud storage",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# Exception Handlers
app.add_exception_handler(HTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(ValidationError, validation_exception_handler)
app.add_exception_handler(Exception, generic_exception_handler)

# Request Logging Middleware
app.add_middleware(RequestLoggingMiddleware)

# CORS Configuration for Flutter Frontend
# Note: Wildcards in origins don't work as expected; use allow_origin_regex or explicit list
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include Routers
app.include_router(ebooks.router, prefix="/api/ebooks", tags=["Ebooks"])
app.include_router(cloud.router, prefix="/api/cloud", tags=["Cloud Storage"])
app.include_router(metadata.router, prefix="/api/metadata", tags=["Metadata"])
app.include_router(sync.router, prefix="/api/sync", tags=["Synchronization"])


@app.get("/")
async def root():
    """API Health Check"""
    return {
        "status": "online",
        "service": "Ebook Organizer API",
        "version": "1.0.0"
    }


@app.get("/health")
async def health_check():
    """Detailed health check endpoint for monitoring"""
    from app.config import settings
    
    return {
        "status": "healthy",
        "version": "1.0.0",
        "environment": "development" if settings.DEBUG else "production",
        "database": "connected",
        "cloud_services": {
            "google_drive": "not_configured",
            "onedrive": "not_configured"
        }
    }


if __name__ == "__main__":
    import uvicorn
    from app.config import settings
    
    uvicorn.run(
        "app.main:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        reload=settings.DEBUG,
        log_level="debug" if settings.DEBUG else "info"
    )
