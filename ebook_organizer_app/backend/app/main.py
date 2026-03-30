"""
FastAPI Backend for Ebook Organizer
Handles cloud storage integration, metadata extraction, and ebook management.
Deployable headless on Raspberry Pi 5 with web UI access.
"""

import os
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.exceptions import RequestValidationError
from pydantic import ValidationError
from contextlib import asynccontextmanager

from app.routes import ebooks, cloud, metadata, sync, conversion, organization
from app.routes import watcher as watcher_routes
from app.services.database import init_db
from app.logging_config import logger
from app.config import settings
from app.auth import verify_api_key
from app.middleware import (
    RequestLoggingMiddleware,
    http_exception_handler,
    validation_exception_handler,
    generic_exception_handler,
)
from app.rate_limit import RateLimitMiddleware


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events"""
    # Startup
    logger.info("Starting Ebook Organizer Backend...")
    init_db()
    logger.info("Database initialized")
    if settings.API_KEY:
        logger.info("API-key authentication is ENABLED")
    else:
        logger.info("API-key authentication is DISABLED (open access)")

    # Start file watcher if enabled
    if settings.WATCH_ENABLED:
        try:
            from app.services.watcher_service import watcher_service
            watcher_service.start()
            logger.info(f"File watcher started — monitoring: {settings.WATCH_DIR}")
        except Exception as e:
            logger.warning(f"File watcher failed to start: {e}")

    yield

    # Shutdown
    logger.info("Shutting down Ebook Organizer Backend...")
    try:
        from app.services.watcher_service import watcher_service
        watcher_service.stop()
    except Exception:
        pass


# Apply API-key dependency globally to all routes
app = FastAPI(
    title="Ebook Organizer API",
    description="Backend API for multi-platform ebook organization with cloud storage",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
    dependencies=[Depends(verify_api_key)],
)

# Exception Handlers
app.add_exception_handler(HTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(ValidationError, validation_exception_handler)
app.add_exception_handler(Exception, generic_exception_handler)

# Request Logging Middleware
app.add_middleware(RequestLoggingMiddleware)

# Rate Limiting Middleware
app.add_middleware(RateLimitMiddleware)

# CORS Configuration — allow LAN access for Pi deployment
# Using wildcard for local network (Pi is not internet-exposed)
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1|192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API Routers
app.include_router(ebooks.router, prefix="/api/ebooks", tags=["Ebooks"])
app.include_router(cloud.router, prefix="/api/cloud", tags=["Cloud Storage"])
app.include_router(metadata.router, prefix="/api/metadata", tags=["Metadata"])
app.include_router(sync.router, prefix="/api/sync", tags=["Synchronization"])
app.include_router(conversion.router, prefix="/api/conversion", tags=["Conversion"])
app.include_router(organization.router, prefix="/api/organization", tags=["Organization"])
app.include_router(watcher_routes.router, prefix="/api/watcher", tags=["Watcher"])

# Mount static covers directory
os.makedirs(settings.COVERS_DIR, exist_ok=True)
app.mount("/static/covers", StaticFiles(directory=settings.COVERS_DIR), name="covers")

# Mount web UI (must be after API routes to avoid conflicts)
# html=True enables index.html fallback
web_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "static", "web")
if os.path.exists(web_dir):
    app.mount("/web", StaticFiles(directory=web_dir, html=True), name="web-ui")
    logger.info(f"Web UI mounted at /web from {web_dir}")


@app.get("/")
async def root():
    """Root endpoint — redirect to web UI or show API info"""
    return {
        "status": "online",
        "service": "Ebook Organizer API",
        "version": "1.0.0",
        "web_ui": "/web/",
        "docs": "/docs",
    }


@app.get("/health")
async def health_check():
    """Detailed health check endpoint for monitoring"""
    from app.services.watcher_service import watcher_service

    return {
        "status": "healthy",
        "version": "1.0.0",
        "environment": "development" if settings.DEBUG else "production",
        "database": "connected",
        "watcher": {
            "running": watcher_service.status["running"],
            "files_processed": watcher_service.status["files_processed"],
        },
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
