"""Synchronization API endpoints"""

from fastapi import APIRouter, Depends, BackgroundTasks
from sqlalchemy.orm import Session
from app.services.database import get_db
from app.models import SyncRequest, SyncResponse, SyncStatus
from datetime import datetime

router = APIRouter()

async def perform_sync(provider: str, full_sync: bool, local_path: str, db: Session):
    """
    Background task to perform cloud synchronization
    """
    from app.services.sync_service import sync_service
    
    print(f"DEBUG: perform_sync called with provider={provider}, full_sync={full_sync}, local_path={local_path}")

    if provider == "local" or (provider == "all" and local_path):
        if local_path:
             print(f"DEBUG: Starting local sync for {local_path}")
             await sync_service.sync_local_folder(local_path, full_sync, db)
        else:
             print("DEBUG: local_path is empty, skipping local sync")
    else:
        print(f"DEBUG: Skipping sync. Conditions: provider={provider}, local_path={local_path}")
    
    # TODO: Add logic for other providers (Google Drive, OneDrive)
    pass

@router.post("/trigger", response_model=SyncResponse)
async def trigger_sync(
    sync_request: SyncRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    """
    Trigger synchronization with cloud storage
    """
    provider = sync_request.provider or "all"
    local_path = sync_request.local_path
    
    # Initialize sync status synchronously to prevent race condition
    if provider == "local" or (provider == "all" and local_path):
        from app.services.sync_service import sync_service
        sync_service.set_initializing()

    # Add background task
    background_tasks.add_task(perform_sync, provider, sync_request.full_sync, local_path, db)
    
    return SyncResponse(
        status="initiated",
        provider=provider,
        books_processed=0,
        books_added=0,
        books_updated=0,
        books_failed=0,
        duration_seconds=0.0,
        error_message=None
    )

@router.get("/status", response_model=SyncStatus)
async def get_sync_status(db: Session = Depends(get_db)):
    """
    Get current synchronization status
    """
    from app.services.sync_service import sync_service
    status = sync_service.get_status()
    # Ensure status dictionary matches SyncStatus schema
    # Pydantic will validate/convert, but we should be careful with structure
    return status


