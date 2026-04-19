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

    try:
        if provider == "local" or (provider == "all" and local_path):
            if local_path:
                 logger.debug(f"Starting local sync for {local_path}")
                 await sync_service.sync_local_folder(local_path, full_sync, db)
            else:
                 logger.debug("local_path is empty, skipping local sync")

        if provider == "google_drive":
            if folder_id:
                logger.debug(f"Starting Google Drive sync for folder {folder_id}")
                await sync_service.sync_google_drive(folder_id, full_sync, db)
            else:
                logger.debug("folder_id is empty, skipping Google Drive sync")

        if provider == "onedrive":
            if folder_id:
                logger.debug(f"Starting OneDrive sync for folder {folder_id}")
                await sync_service.sync_onedrive(folder_id, full_sync, db)
            else:
                logger.debug("folder_id is empty, skipping OneDrive sync")

        if provider == "all":
            # For "all" cloud providers, look up each provider's stored folder from DB
            from app.models.database import CloudConfig
            for cloud_provider in ("google_drive", "onedrive"):
                config = db.query(CloudConfig).filter(
                    CloudConfig.provider == cloud_provider
                ).first()
                if config and config.is_authenticated and config.folder_path:
                    logger.debug(f"Starting {cloud_provider} sync for stored folder {config.folder_path}")
                    if cloud_provider == "google_drive":
                        await sync_service.sync_google_drive(config.folder_path, full_sync, db)
                    else:
                        await sync_service.sync_onedrive(config.folder_path, full_sync, db)
    except Exception as e:
        logger.error(f"perform_sync error: {e}", exc_info=True)
    finally:
        # Ensure status is always reset even if no sync ran or an unexpected error occurred
        status = sync_service.get_status()
        if status.get("is_active"):
            sync_service._update_status(is_active=False, status="completed", stage=None)

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
    if provider in ("local", "all", "google_drive", "onedrive"):
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


