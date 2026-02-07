"""
Synchronization Service
Handles syncing local files to the database.
"""

import os
import hashlib
from typing import List, Optional
from datetime import datetime
from sqlalchemy.orm import Session
from app.models.database import Ebook, SyncLog
from app.models.schemas import SyncResponse
from app.services.metadata_service import metadata_service

class SyncService:
    """Service for synchronizing ebook libraries"""
    
    SUPPORTED_EXTENSIONS = {'.epub', '.pdf', '.mobi'}

    def __init__(self):
        self._status = {
            "is_active": False,
            "status": "idle",
            "stage": None,
            "current_file": None,
            "books_processed": 0,
            "books_added": 0,
            "books_updated": 0,
            "books_failed": 0
        }

    def get_status(self) -> dict:
        return self._status

    def _reset_status(self):
        self._status = {
            "is_active": True,
            "status": "scanning",
            "stage": "initializing",
            "current_file": None,
            "books_processed": 0,
            "books_added": 0,
            "books_updated": 0,
            "books_failed": 0
        }

    def _update_status(self, **kwargs):
        self._status.update(kwargs)

    def set_initializing(self):
        """Mark sync as initializing before background task starts"""
        self._status.update({
            "is_active": True,
            "status": "initializing",
            "stage": "starting...",
            "current_file": None
        })

    async def sync_local_folder(self, path: str, full_sync: bool, db: Session) -> SyncResponse:
        if not os.path.exists(path) or not os.path.isdir(path):
            return SyncResponse(
                status="failed",
                provider="local",
                books_processed=0,
                books_added=0,
                books_updated=0,
                books_failed=0,
                duration_seconds=0.0,
                error_message=f"Path does not exist: {path}"
            )
        
        self._reset_status()
        self._update_status(stage="scanning directory")
        print(f"DEBUG: SyncService scanning directory: {path}")

        start_time = datetime.now()
        
        try:
            for root, _, files in os.walk(path):
                for file in files:
                    file_path = os.path.join(root, file)
                    ext = os.path.splitext(file)[1].lower()
                    
                    if ext in self.SUPPORTED_EXTENSIONS:
                        self._update_status(
                            stage="processing file",
                            current_file=file
                        )
                        await self._process_file(file_path, ext, db)
                        self._status["books_processed"] += 1
                        
            # Commit changes
            db.commit()
            duration = (datetime.now() - start_time).total_seconds()
            
            self._update_status(
                is_active=False,
                status="completed",
                stage=None,
                current_file=None
            )
            
            return SyncResponse(
                status="completed",
                provider="local",
                books_processed=self._status["books_processed"],
                books_added=self._status["books_added"],
                books_updated=self._status["books_updated"],
                books_failed=self._status["books_failed"],
                duration_seconds=duration
            )
            
        except Exception as e:
            print(f"Sync failed: {e}")
            db.rollback()
            self._update_status(
                is_active=False,
                status="failed",
                stage=str(e)
            )
            return SyncResponse(
                status="failed",
                provider="local",
                books_processed=self._status["books_processed"],
                books_added=self._status["books_added"],
                books_updated=self._status["books_updated"],
                books_failed=self._status["books_failed"],
                duration_seconds=(datetime.now() - start_time).total_seconds(),
                error_message=str(e)
            )

    async def _process_file(self, file_path: str, ext: str, db: Session):
        """Process a single file: check exist, extract metadata, add to DB"""
        try:
            # simple duplicate check
            existing = db.query(Ebook).filter(Ebook.cloud_file_path == file_path).first()
            if existing:
                return

            file_size = os.path.getsize(file_path)
            
            # Extract metadata
            self._update_status(stage="extracting metadata")
            metadata = await metadata_service.read_metadata(file_path)
            
            new_ebook = None
            if metadata:
                new_ebook = Ebook(
                    title=metadata.title or os.path.basename(file_path),
                    author=metadata.author or "Unknown",
                    description=metadata.description,
                    publisher=metadata.publisher,
                    language=metadata.language,
                    published_date=metadata.date,
                    category=metadata.subjects[0] if metadata.subjects else None,
                    file_format=ext.lstrip('.'),
                    file_size=file_size,
                    cloud_provider="local",
                    cloud_file_id=file_path,
                    cloud_file_path=file_path,
                    is_synced=True,
                    sync_status="synced",
                    last_synced=datetime.now()
                )
            else:
                 # Minimal info fallback
                new_ebook = Ebook(
                    title=os.path.basename(file_path),
                    file_format=ext.lstrip('.'),
                    file_size=file_size,
                    cloud_provider="local",
                    cloud_file_id=file_path,
                    cloud_file_path=file_path,
                    is_synced=True,
                    sync_status="synced",
                    last_synced=datetime.now()
                )
            
            db.add(new_ebook)
            self._status["books_added"] += 1

        except Exception as e:
            print(f"Failed to process {file_path}: {e}")
            self._status["books_failed"] += 1

sync_service = SyncService()
