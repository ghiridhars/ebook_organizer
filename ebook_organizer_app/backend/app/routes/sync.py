"""Synchronization API endpoints"""

import logging
from fastapi import APIRouter, Depends, BackgroundTasks
from sqlalchemy.orm import Session
from app.services.database import get_db
from app.models import SyncRequest, SyncResponse, SyncStatus
from datetime import datetime

logger = logging.getLogger(__name__)

router = APIRouter()

async def perform_sync(provider: str, full_sync: bool, local_path: str, folder_id: str, db: Session):
    """
    Background task to perform cloud synchronization
    """
    from app.services.sync_service import sync_service
    
    logger.debug(f"perform_sync called with provider={provider}, full_sync={full_sync}, local_path={local_path}, folder_id={folder_id}")

    if provider == "local" or (provider == "all" and local_path):
        if local_path:
             logger.debug(f"Starting local sync for {local_path}")
             await sync_service.sync_local_folder(local_path, full_sync, db)
        else:
             logger.debug("local_path is empty, skipping local sync")

    if provider == "google_drive" or (provider == "all" and folder_id):
        if folder_id:
            logger.debug(f"Starting Google Drive sync for folder {folder_id}")
            await sync_service.sync_google_drive(folder_id, full_sync, db)
        else:
            logger.debug("folder_id is empty, skipping Google Drive sync")

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
    folder_id = sync_request.folder_id
    
    # Initialize sync status synchronously to prevent race condition
    if provider in ("local", "all", "google_drive"):
        from app.services.sync_service import sync_service
        sync_service.set_initializing()

    # Add background task
    background_tasks.add_task(perform_sync, provider, sync_request.full_sync, local_path, folder_id, db)
    
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


