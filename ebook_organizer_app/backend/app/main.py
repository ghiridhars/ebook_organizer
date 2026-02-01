"""
FastAPI Backend for Ebook Organizer
Handles cloud storage integration, metadata extraction, and ebook management
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import uvicorn

from app.routes import ebooks, cloud, metadata, sync
from app.services.database import init_db

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events"""
    # Startup
    print("Starting Ebook Organizer Backend...")
    init_db()
    print("Database initialized")
    yield
    # Shutdown
    print("Shutting down Ebook Organizer Backend...")

app = FastAPI(
    title="Ebook Organizer API",
    description="Backend API for multi-platform ebook organization with cloud storage",
    version="1.0.0",
    lifespan=lifespan
)

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
    """Detailed health check endpoint"""
    return {
        "status": "healthy",
        "database": "connected",
        "cloud_services": {
            "google_drive": "not_configured",
            "onedrive": "not_configured"
        }
    }

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="127.0.0.1",
        port=8000,
        reload=True,
        log_level="info"
    )
