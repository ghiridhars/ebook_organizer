"""Watcher API endpoints — control the file watcher service."""

import logging
from fastapi import APIRouter, HTTPException
from app.services.watcher_service import watcher_service

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/status")
async def get_watcher_status():
    """Get current watcher status: running state, files processed, errors."""
    return watcher_service.status


@router.post("/start")
async def start_watcher():
    """Start the file watcher if it's stopped."""
    if watcher_service.status["running"]:
        return {"message": "Watcher is already running"}

    try:
        watcher_service.start()
        return {"message": "Watcher started", "status": watcher_service.status}
    except Exception as e:
        logger.error(f"Failed to start watcher: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to start watcher: {e}")


@router.post("/stop")
async def stop_watcher():
    """Stop the file watcher."""
    if not watcher_service.status["running"]:
        return {"message": "Watcher is not running"}

    watcher_service.stop()
    return {"message": "Watcher stopped", "status": watcher_service.status}


@router.get("/failed")
async def get_failed_files():
    """List files that failed processing."""
    files = watcher_service.get_failed_files()
    return {"failed_files": files, "count": len(files)}


@router.post("/retry/{filename}")
async def retry_failed_file(filename: str):
    """Retry processing a failed file."""
    success = await watcher_service.retry_failed(filename)
    if not success:
        raise HTTPException(status_code=404, detail=f"Failed file not found: {filename}")

    return {"message": f"File {filename} moved back to inbox for reprocessing"}
