"""
Watchdog File Watcher Service

Monitors an inbox directory for new ebook files and automatically
processes them: extract metadata, classify, optionally convert MOBI→EPUB,
and organize into the library structure.
"""

import os
import time
import shutil
import asyncio
import logging
import threading
from datetime import datetime
from typing import Optional, Set
from pathlib import Path

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler, FileCreatedEvent

from app.config import settings

logger = logging.getLogger(__name__)

SUPPORTED_EXTENSIONS = {'.epub', '.pdf', '.mobi', '.azw', '.azw3'}


class EbookEventHandler(FileSystemEventHandler):
    """Handles file creation events for ebook files in the watch directory."""

    def __init__(self, watcher_service: 'WatcherService'):
        super().__init__()
        self._watcher = watcher_service
        self._processing: Set[str] = set()
        self._lock = threading.Lock()

    def on_created(self, event):
        if event.is_directory:
            return

        file_path = event.src_path
        ext = os.path.splitext(file_path)[1].lower()

        if ext not in SUPPORTED_EXTENSIONS:
            return

        # Prevent duplicate processing
        with self._lock:
            if file_path in self._processing:
                return
            self._processing.add(file_path)

        logger.info(f"New ebook detected: {os.path.basename(file_path)}")

        # Schedule processing with debounce (handles partial writes)
        threading.Thread(
            target=self._debounce_and_process,
            args=(file_path,),
            daemon=True
        ).start()

    def _debounce_and_process(self, file_path: str):
        """Wait for file write to complete, then process."""
        try:
            # Wait for debounce period
            time.sleep(settings.WATCH_DEBOUNCE_SECONDS)

            # Check file size stability (2 consecutive checks)
            if not self._wait_for_file_stability(file_path):
                logger.warning(f"File not stable after timeout: {file_path}")
                self._move_to_failed(file_path, "File write did not complete")
                return

            # Bridge to async context for processing
            loop = self._watcher.loop
            if loop and loop.is_running():
                future = asyncio.run_coroutine_threadsafe(
                    self._watcher.process_file(file_path),
                    loop
                )
                future.result(timeout=300)  # 5 min timeout per file
            else:
                logger.error("Event loop not available for processing")

        except Exception as e:
            logger.error(f"Failed to process {file_path}: {e}")
            self._move_to_failed(file_path, str(e))
        finally:
            with self._lock:
                self._processing.discard(file_path)

    def _wait_for_file_stability(self, file_path: str, timeout: int = 60) -> bool:
        """Wait until file size stops changing (write complete)."""
        start = time.time()
        prev_size = -1

        while time.time() - start < timeout:
            if not os.path.exists(file_path):
                return False

            current_size = os.path.getsize(file_path)
            if current_size == prev_size and current_size > 0:
                return True

            prev_size = current_size
            time.sleep(1.0)

        return False

    def _move_to_failed(self, file_path: str, error: str):
        """Move a failed file to the _failed directory."""
        try:
            failed_dir = os.path.join(settings.WATCH_DIR, "_failed")
            os.makedirs(failed_dir, exist_ok=True)

            filename = os.path.basename(file_path)
            dest = os.path.join(failed_dir, filename)

            # Handle name collision
            counter = 1
            base, ext = os.path.splitext(filename)
            while os.path.exists(dest):
                dest = os.path.join(failed_dir, f"{base}_{counter}{ext}")
                counter += 1

            if os.path.exists(file_path):
                shutil.move(file_path, dest)

            # Write error log alongside
            error_log = dest + ".error.txt"
            with open(error_log, 'w') as f:
                f.write(f"File: {filename}\n")
                f.write(f"Error: {error}\n")
                f.write(f"Timestamp: {datetime.now().isoformat()}\n")

            logger.info(f"Moved failed file to: {dest}")
        except Exception as e:
            logger.error(f"Failed to move file to _failed: {e}")


class WatcherService:
    """
    Singleton service that manages the watchdog Observer lifecycle
    and processes new ebook files through the ingest pipeline.
    """

    def __init__(self):
        self._observer: Optional[Observer] = None
        self._handler: Optional[EbookEventHandler] = None
        self._running = False
        self._files_processed = 0
        self._files_failed = 0
        self._last_processed: Optional[datetime] = None
        self._last_error: Optional[str] = None
        self.loop: Optional[asyncio.AbstractEventLoop] = None

    @property
    def status(self) -> dict:
        return {
            "running": self._running,
            "watch_dir": settings.WATCH_DIR,
            "files_processed": self._files_processed,
            "files_failed": self._files_failed,
            "last_processed": self._last_processed.isoformat() if self._last_processed else None,
            "last_error": self._last_error,
            "auto_organize": settings.AUTO_ORGANIZE,
            "auto_convert_mobi": settings.AUTO_CONVERT_MOBI,
        }

    def start(self):
        """Start watching the inbox directory."""
        if self._running:
            logger.warning("Watcher is already running")
            return

        watch_dir = settings.WATCH_DIR
        if not os.path.exists(watch_dir):
            os.makedirs(watch_dir, exist_ok=True)
            logger.info(f"Created watch directory: {watch_dir}")

        try:
            self.loop = asyncio.get_event_loop()
        except RuntimeError:
            self.loop = asyncio.new_event_loop()

        self._handler = EbookEventHandler(self)
        self._observer = Observer()
        self._observer.schedule(self._handler, watch_dir, recursive=False)
        self._observer.start()
        self._running = True
        logger.info(f"Watcher started — monitoring: {watch_dir}")

    def stop(self):
        """Stop watching."""
        if not self._running:
            return

        if self._observer:
            self._observer.stop()
            self._observer.join(timeout=10)
            self._observer = None

        self._running = False
        logger.info("Watcher stopped")

    async def process_file(self, file_path: str):
        """
        Process a single ebook file through the ingest pipeline:
        1. Extract metadata
        2. Classify
        3. Optionally convert MOBI→EPUB
        4. Save to database
        5. Optionally organize into library structure
        """
        from app.services.database import SessionLocal
        from app.services.metadata_service import metadata_service
        from app.models.database import Ebook

        filename = os.path.basename(file_path)
        ext = os.path.splitext(filename)[1].lower().lstrip('.')
        logger.info(f"Processing: {filename}")

        db = SessionLocal()
        try:
            # Check for duplicate
            existing = db.query(Ebook).filter(Ebook.cloud_file_path == file_path).first()
            if existing:
                logger.info(f"Already in database: {filename}")
                return

            # Step 1: Extract metadata
            metadata = await metadata_service.read_metadata(file_path)

            # Step 2: Classify
            category = None
            sub_genre = None
            try:
                from app.services.metadata_classifier import MetadataClassifier
                classifier = MetadataClassifier()
                classification = await classifier.classify_ebook(file_path)
                if classification:
                    category = classification.get('category')
                    sub_genre = classification.get('sub_genre')
            except Exception as e:
                logger.warning(f"Classification failed for {filename}: {e}")

            # Step 3: Optionally convert MOBI→EPUB
            converted_path = None
            if settings.AUTO_CONVERT_MOBI and ext in ('mobi', 'azw', 'azw3'):
                try:
                    converted_path = await self._convert_mobi_to_epub(file_path)
                    logger.info(f"Converted MOBI→EPUB: {converted_path}")
                except Exception as e:
                    logger.warning(f"MOBI conversion failed for {filename}: {e}")

            # Step 4: Save to database
            file_size = os.path.getsize(file_path)
            new_ebook = Ebook(
                title=metadata.title if metadata and metadata.title else os.path.splitext(filename)[0],
                author=metadata.author if metadata and metadata.author else "Unknown",
                description=metadata.description if metadata else None,
                publisher=metadata.publisher if metadata else None,
                language=metadata.language if metadata else None,
                published_date=metadata.date if metadata else None,
                category=category,
                sub_genre=sub_genre,
                file_format=ext,
                file_size=file_size,
                cloud_provider="local",
                cloud_file_id=file_path,
                cloud_file_path=file_path,
                is_synced=True,
                sync_status="synced",
                last_synced=datetime.now()
            )
            db.add(new_ebook)
            db.commit()
            db.refresh(new_ebook)

            # If converted, also add the EPUB version
            if converted_path and os.path.exists(converted_path):
                epub_size = os.path.getsize(converted_path)
                epub_ebook = Ebook(
                    title=new_ebook.title,
                    author=new_ebook.author,
                    description=new_ebook.description,
                    publisher=new_ebook.publisher,
                    language=new_ebook.language,
                    published_date=new_ebook.published_date,
                    category=category,
                    sub_genre=sub_genre,
                    file_format="epub",
                    file_size=epub_size,
                    cloud_provider="local",
                    cloud_file_id=converted_path,
                    cloud_file_path=converted_path,
                    is_synced=True,
                    sync_status="synced",
                    last_synced=datetime.now()
                )
                db.add(epub_ebook)
                db.commit()

            # Step 5: Extract cover (best-effort, Phase 3)
            try:
                from app.services.cover_service import cover_service
                await cover_service.extract_cover(file_path, new_ebook.id, db)
            except (ImportError, Exception) as e:
                logger.debug(f"Cover extraction skipped: {e}")

            # Step 6: Optionally organize into library structure
            if settings.AUTO_ORGANIZE:
                try:
                    await self._organize_file(file_path, new_ebook, db)
                except Exception as e:
                    logger.warning(f"Auto-organize failed for {filename}: {e}")

            self._files_processed += 1
            self._last_processed = datetime.now()
            logger.info(f"Successfully processed: {filename}")

        except Exception as e:
            self._files_failed += 1
            self._last_error = str(e)
            logger.error(f"Failed to process {filename}: {e}")
            db.rollback()
            raise
        finally:
            db.close()

    async def _convert_mobi_to_epub(self, file_path: str) -> Optional[str]:
        """Convert MOBI/AZW to EPUB using existing conversion logic."""
        from app.routes.conversion import convert_mobi_content

        epub_path = os.path.splitext(file_path)[0] + ".epub"
        if os.path.exists(epub_path):
            return epub_path

        try:
            result = convert_mobi_content(file_path, epub_path)
            if result and os.path.exists(epub_path):
                return epub_path
        except Exception as e:
            logger.warning(f"MOBI→EPUB conversion error: {e}")

        return None

    async def _organize_file(self, file_path: str, ebook, db):
        """Move file to organized library structure."""
        category = ebook.category or "Unclassified"
        sub_genre = ebook.sub_genre or ""
        author = ebook.author or "Unknown Author"

        # Sanitize folder names
        for char in '<>:"/\\|?*':
            category = category.replace(char, '_')
            sub_genre = sub_genre.replace(char, '_')
            author = author.replace(char, '_')

        # Build destination path
        dest_parts = [settings.LIBRARY_DIR, category]
        if sub_genre:
            dest_parts.append(sub_genre)
        dest_parts.append(author)

        dest_dir = os.path.join(*dest_parts)
        os.makedirs(dest_dir, exist_ok=True)

        filename = os.path.basename(file_path)
        dest_path = os.path.join(dest_dir, filename)

        # Handle collision
        counter = 1
        base, ext = os.path.splitext(filename)
        while os.path.exists(dest_path):
            dest_path = os.path.join(dest_dir, f"{base}_{counter}{ext}")
            counter += 1

        # Move file
        shutil.move(file_path, dest_path)

        # Update DB paths
        ebook.cloud_file_path = dest_path
        ebook.cloud_file_id = dest_path
        db.commit()

        logger.info(f"Organized: {filename} → {dest_path}")

    def get_failed_files(self) -> list:
        """List files in the _failed directory."""
        failed_dir = os.path.join(settings.WATCH_DIR, "_failed")
        if not os.path.exists(failed_dir):
            return []

        files = []
        for f in os.listdir(failed_dir):
            if f.endswith('.error.txt'):
                continue
            full_path = os.path.join(failed_dir, f)
            error_log = full_path + ".error.txt"
            error_msg = None
            if os.path.exists(error_log):
                with open(error_log, 'r') as ef:
                    error_msg = ef.read()

            files.append({
                "filename": f,
                "path": full_path,
                "size": os.path.getsize(full_path),
                "error": error_msg,
            })

        return files

    async def retry_failed(self, filename: str) -> bool:
        """Retry processing a failed file by moving it back to inbox."""
        failed_dir = os.path.join(settings.WATCH_DIR, "_failed")
        failed_path = os.path.join(failed_dir, filename)

        if not os.path.exists(failed_path):
            return False

        # Move back to watch dir (the watcher will pick it up)
        dest = os.path.join(settings.WATCH_DIR, filename)
        shutil.move(failed_path, dest)

        # Remove error log
        error_log = failed_path + ".error.txt"
        if os.path.exists(error_log):
            os.remove(error_log)

        logger.info(f"Retrying failed file: {filename}")
        return True


# Singleton instance
watcher_service = WatcherService()
