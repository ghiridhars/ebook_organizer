"""
Synchronization Service
Handles syncing local files and Google Drive files to the database.
"""

import os
import logging
import tempfile
from typing import List, Optional
from datetime import datetime
from sqlalchemy.orm import Session
from app.models.database import Ebook, CloudConfig, SyncLog
from app.models.schemas import SyncResponse
from app.services.metadata_service import metadata_service

logger = logging.getLogger(__name__)

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
            "books_skipped": 0,
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
            "books_skipped": 0,
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
        logger.debug(f"SyncService scanning directory: {path}")

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
            logger.error(f"Sync failed: {e}")
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
            logger.error(f"Failed to process {file_path}: {e}")
            self._status["books_failed"] += 1

    # ----- Google Drive sync -------------------------------------------

    async def sync_google_drive(
        self, folder_id: str, full_sync: bool, db: Session
    ) -> SyncResponse:
        """Sync ebooks from a Google Drive folder into the database.

        1. List ebook files in the Drive folder
        2. For each file not yet in DB (by cloud_file_id):
           a. Download to a temp path
           b. Extract metadata
           c. Classify
           d. Create Ebook record
           e. Delete temp file
        3. Log results to SyncLog
        """
        import json
        from app.services.cloud_provider_service import get_provider

        self._reset_status()
        self._update_status(stage="connecting to Google Drive")
        start_time = datetime.now()

        # Load stored OAuth tokens
        config = db.query(CloudConfig).filter(
            CloudConfig.provider == "google_drive"
        ).first()
        if not config or not config.is_authenticated:
            return SyncResponse(
                status="failed",
                provider="google_drive",
                books_processed=0,
                books_added=0,
                books_updated=0,
                books_failed=0,
                duration_seconds=0.0,
                error_message="Google Drive is not authenticated. Connect it first.",
            )

        try:
            adapter = get_provider("google_drive")
            adapter.set_credentials(json.loads(config.credentials_encrypted))

            # Set up token refresh callback to persist refreshed tokens
            def _on_refresh(new_tokens):
                merged = {**json.loads(config.credentials_encrypted), **new_tokens}
                config.credentials_encrypted = json.dumps(merged)
                adapter.set_credentials(merged)
                try:
                    db.commit()
                except Exception:
                    db.rollback()

            adapter._token_refresh_callback = _on_refresh

            # List ebook files in the selected folder
            self._update_status(stage="listing files on Drive")
            cloud_files = await adapter.list_files(folder_path=folder_id)
            logger.info(f"Found {len(cloud_files)} ebook(s) in Drive folder {folder_id}")

            for cf in cloud_files:
                self._update_status(
                    stage="processing file",
                    current_file=cf.name,
                )

                try:
                    # Dedup check by cloud_file_id
                    existing = db.query(Ebook).filter(
                        Ebook.cloud_file_id == cf.file_id
                    ).first()

                    if existing and not full_sync:
                        # Incremental: skip if Drive file hasn't changed
                        if (
                            existing.cloud_modified_time
                            and cf.modified_at
                            and cf.modified_at <= existing.cloud_modified_time
                        ):
                            self._status["books_skipped"] += 1
                            self._status["books_processed"] += 1
                            continue

                    # Download to temp for metadata extraction
                    ext = os.path.splitext(cf.name)[1].lower()
                    self._update_status(stage="downloading for metadata")

                    with tempfile.NamedTemporaryFile(
                        suffix=ext, delete=False
                    ) as tmp:
                        tmp_path = tmp.name

                    try:
                        await adapter.download_file(cf.file_id, tmp_path)

                        # Extract metadata
                        self._update_status(stage="extracting metadata")
                        metadata = await metadata_service.read_metadata(tmp_path)

                        # Classify
                        category = None
                        sub_genre = None
                        try:
                            from app.services.metadata_classifier import classify_book
                            result = classify_book(tmp_path, metadata)
                            if result:
                                category = result.get("category")
                                sub_genre = result.get("sub_genre")
                        except Exception as cls_err:
                            logger.warning(
                                f"Classification failed for {cf.name}: {cls_err}"
                            )
                    finally:
                        # Always clean up temp file
                        if os.path.exists(tmp_path):
                            os.unlink(tmp_path)

                    if existing:
                        # Full sync or file changed: update existing record
                        if metadata:
                            existing.title = metadata.title or existing.title
                            existing.author = metadata.author or existing.author
                            existing.description = metadata.description or existing.description
                            existing.publisher = metadata.publisher or existing.publisher
                            existing.language = metadata.language or existing.language
                            existing.published_date = metadata.date or existing.published_date
                        if category:
                            existing.category = category
                        if sub_genre:
                            existing.sub_genre = sub_genre
                        existing.file_size = cf.size
                        existing.last_synced = datetime.now()
                        existing.cloud_modified_time = cf.modified_at
                        existing.sync_status = "synced"
                        self._status["books_updated"] += 1
                    else:
                        # New book
                        ebook_kwargs = dict(
                            title=cf.name,
                            file_format=ext.lstrip("."),
                            file_size=cf.size,
                            cloud_provider="google_drive",
                            cloud_file_id=cf.file_id,
                            cloud_file_path=cf.path,
                            category=category,
                            sub_genre=sub_genre,
                            is_synced=True,
                            sync_status="synced",
                            last_synced=datetime.now(),
                            cloud_modified_time=cf.modified_at,
                        )
                        if metadata:
                            ebook_kwargs.update(
                                title=metadata.title or cf.name,
                                author=metadata.author or "Unknown",
                                description=metadata.description,
                                publisher=metadata.publisher,
                                language=metadata.language,
                                published_date=metadata.date,
                            )

                        db.add(Ebook(**ebook_kwargs))
                        self._status["books_added"] += 1

                    self._status["books_processed"] += 1

                except Exception as file_err:
                    from app.services.cloud_provider_service import (
                        DriveAuthError, DriveRateLimitError, DriveNotFoundError,
                    )
                    if isinstance(file_err, DriveAuthError):
                        logger.error(
                            f"Auth error processing {cf.name} (HTTP {file_err.status_code}): {file_err}"
                        )
                    elif isinstance(file_err, DriveRateLimitError):
                        logger.warning(f"Rate limited on {cf.name}, skipping")
                    elif isinstance(file_err, DriveNotFoundError):
                        logger.warning(f"Drive file {cf.name} not found (maybe deleted)")
                    else:
                        logger.error(
                            f"Failed to process Drive file {cf.name}: {file_err}",
                            exc_info=True,
                        )
                    self._status["books_failed"] += 1
                    self._status["books_processed"] += 1

            db.commit()
            duration = (datetime.now() - start_time).total_seconds()

            # Write audit log
            sync_log = SyncLog(
                cloud_provider="google_drive",
                operation="full_sync" if full_sync else "incremental",
                status="success",
                books_processed=self._status["books_processed"],
                books_added=self._status["books_added"],
                books_updated=self._status["books_updated"],
                books_failed=self._status["books_failed"],
                completed_at=datetime.now(),
                duration_seconds=duration,
            )
            db.add(sync_log)
            db.commit()

            # Update CloudConfig last_sync and folder_path
            config.last_sync = datetime.now()
            config.folder_path = folder_id
            db.commit()

            self._update_status(
                is_active=False,
                status="completed",
                stage=None,
                current_file=None,
            )

            return SyncResponse(
                status="completed",
                provider="google_drive",
                books_processed=self._status["books_processed"],
                books_added=self._status["books_added"],
                books_updated=self._status["books_updated"],
                books_failed=self._status["books_failed"],
                duration_seconds=duration,
            )

        except Exception as e:
            logger.error(f"Google Drive sync failed: {e}")
            db.rollback()
            duration = (datetime.now() - start_time).total_seconds()
            self._update_status(
                is_active=False,
                status="failed",
                stage=str(e),
            )
            return SyncResponse(
                status="failed",
                provider="google_drive",
                books_processed=self._status["books_processed"],
                books_added=self._status["books_added"],
                books_updated=self._status["books_updated"],
                books_failed=self._status["books_failed"],
                duration_seconds=duration,
                error_message=str(e),
            )

sync_service = SyncService()
