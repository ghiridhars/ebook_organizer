"""
Ebook Metadata Service
Handles reading and writing metadata for various ebook formats.
"""

import os
import logging
from typing import Optional, Dict, List, Any
from dataclasses import dataclass, asdict
from pathlib import Path

logger = logging.getLogger(__name__)


@dataclass
class EbookMetadata:
    """Universal ebook metadata model"""
    title: Optional[str] = None
    author: Optional[str] = None
    description: Optional[str] = None
    publisher: Optional[str] = None
    language: Optional[str] = None
    date: Optional[str] = None
    subjects: List[str] = None  # Tags/Categories
    identifier: Optional[str] = None  # ISBN, etc.
    
    def __post_init__(self):
        if self.subjects is None:
            self.subjects = []
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class MetadataService:
    """Service for reading/writing ebook metadata across formats"""
    
    SUPPORTED_FORMATS = {'.epub', '.pdf', '.mobi'}
    WRITABLE_FORMATS = {'.epub', '.pdf'}  # MOBI writing is very limited
    
    def get_format(self, file_path: str) -> str:
        """Get file extension in lowercase"""
        return Path(file_path).suffix.lower()
    
    def is_supported(self, file_path: str) -> bool:
        """Check if format is supported for reading"""
        return self.get_format(file_path) in self.SUPPORTED_FORMATS
    
    def is_writable(self, file_path: str) -> bool:
        """Check if format is supported for writing"""
        return self.get_format(file_path) in self.WRITABLE_FORMATS
    
    async def read_metadata(self, file_path: str) -> Optional[EbookMetadata]:
        """Read metadata from any supported ebook format"""
        if not os.path.exists(file_path):
            return None
        
        fmt = self.get_format(file_path)
        
        try:
            if fmt == '.epub':
                return await self._read_epub_metadata(file_path)
            elif fmt == '.pdf':
                return await self._read_pdf_metadata(file_path)
            elif fmt == '.mobi':
                return await self._read_mobi_metadata(file_path)
            else:
                return None
        except Exception as e:
            print(f"Error reading metadata from {file_path}: {e}")
            return None
    
    async def write_metadata(self, file_path: str, metadata: EbookMetadata) -> bool:
        """Write metadata to supported ebook format.
        
        Returns True on success.
        Raises an exception with a descriptive message on failure.
        """
        logger.info(f"[METADATA WRITE] Request to write metadata for: {file_path}")
        logger.info(f"[METADATA WRITE] Incoming metadata: title={metadata.title!r}, author={metadata.author!r}, "
                     f"description={metadata.description!r}, publisher={metadata.publisher!r}, "
                     f"language={metadata.language!r}, subjects={metadata.subjects!r}")
        
        if not os.path.exists(file_path):
            logger.error(f"[METADATA WRITE] File does not exist: {file_path}")
            raise FileNotFoundError(f"File does not exist: {file_path}")
        
        fmt = self.get_format(file_path)
        logger.info(f"[METADATA WRITE] Detected format: {fmt}")
        
        if fmt not in self.WRITABLE_FORMATS:
            logger.warning(f"[METADATA WRITE] Format {fmt} is not writable. Writable formats: {self.WRITABLE_FORMATS}")
            raise ValueError(f"Format {fmt} is not writable")
        
        if fmt == '.epub':
            result = await self._write_epub_metadata(file_path, metadata)
            logger.info(f"[METADATA WRITE] EPUB write result: {result}")
            return result
        elif fmt == '.pdf':
            result = await self._write_pdf_metadata(file_path, metadata)
            logger.info(f"[METADATA WRITE] PDF write result: {result}")
            return result
        else:
            logger.warning(f"[METADATA WRITE] No write handler for format: {fmt}")
            raise ValueError(f"No write handler for format: {fmt}")
    
    # ==================== EPUB ====================
    
    async def _read_epub_metadata(self, file_path: str) -> EbookMetadata:
        """Read metadata from EPUB file using ebooklib"""
        from ebooklib import epub
        
        book = epub.read_epub(file_path)
        
        def get_metadata(namespace: str, name: str) -> Optional[str]:
            values = book.get_metadata(namespace, name)
            if values:
                # Returns list of tuples: [(value, attributes), ...]
                return values[0][0] if values[0] else None
            return None
        
        def get_all_metadata(namespace: str, name: str) -> List[str]:
            values = book.get_metadata(namespace, name)
            return [v[0] for v in values if v and v[0]]
        
        return EbookMetadata(
            title=get_metadata('DC', 'title'),
            author=get_metadata('DC', 'creator'),
            description=get_metadata('DC', 'description'),
            publisher=get_metadata('DC', 'publisher'),
            language=get_metadata('DC', 'language'),
            date=get_metadata('DC', 'date'),
            subjects=get_all_metadata('DC', 'subject'),
            identifier=get_metadata('DC', 'identifier'),
        )
    
    async def _write_epub_metadata(self, file_path: str, metadata: EbookMetadata) -> bool:
        """Write metadata to EPUB file using ebooklib"""
        from ebooklib import epub
        import shutil
        
        # Create backup
        backup_path = file_path + '.backup'
        shutil.copy2(file_path, backup_path)
        
        try:
            book = epub.read_epub(file_path)
            
            # Clear existing metadata we're updating
            if metadata.title:
                book.set_title(metadata.title)
            
            if metadata.author:
                # Remove existing creators and add new one
                book.metadata['DC'] = {
                    k: v for k, v in book.metadata.get('DC', {}).items() 
                    if k != 'creator'
                }
                book.add_author(metadata.author)
            
            if metadata.description:
                book.add_metadata('DC', 'description', metadata.description)
            
            if metadata.publisher:
                book.add_metadata('DC', 'publisher', metadata.publisher)
            
            if metadata.language:
                book.set_language(metadata.language)
            
            if metadata.subjects:
                # Remove existing subjects
                if 'DC' in book.metadata:
                    book.metadata['DC'] = {
                        k: v for k, v in book.metadata['DC'].items()
                        if k != 'subject'
                    }
                for subject in metadata.subjects:
                    book.add_metadata('DC', 'subject', subject)
            
            # Write the modified EPUB
            epub.write_epub(file_path, book)
            
            # Remove backup on success
            os.remove(backup_path)
            return True
            
        except Exception as e:
            # Restore from backup on failure
            if os.path.exists(backup_path):
                shutil.move(backup_path, file_path)
            raise e
    
    # ==================== PDF ====================
    
    async def _read_pdf_metadata(self, file_path: str) -> EbookMetadata:
        """Read metadata from PDF file using pypdf"""
        from pypdf import PdfReader
        
        logger.info(f"[PDF READ] Reading PDF metadata from: {file_path}")
        try:
            reader = PdfReader(file_path)
            info = reader.metadata
            
            if not info:
                logger.info(f"[PDF READ] No metadata found in PDF: {file_path}")
                return EbookMetadata()
            
            # Log raw metadata values
            logger.info(f"[PDF READ] Raw PDF metadata:")
            for key in ['/Title', '/Author', '/Subject', '/Creator', '/Keywords', '/Producer']:
                val = info.get(key)
                logger.info(f"[PDF READ]   {key} = {val!r} (type={type(val).__name__})")
            
            result = EbookMetadata(
                title=self._clean_pdf_value(info.get('/Title')),
                author=self._clean_pdf_value(info.get('/Author')),
                description=self._clean_pdf_value(info.get('/Subject')),
                publisher=self._clean_pdf_value(info.get('/Creator')),
            )
            logger.info(f"[PDF READ] Parsed metadata: title={result.title!r}, author={result.author!r}, "
                         f"description={result.description!r}, publisher={result.publisher!r}")
            return result
        except Exception as e:
            logger.error(f"[PDF READ] Error reading PDF metadata {file_path}: {e}", exc_info=True)
            # Return empty metadata instead of failing
            return EbookMetadata()

    def _clean_pdf_value(self, value: Any) -> Optional[str]:
        """Clean and convert PDF metadata value to string"""
        if value is None:
            return None
            
        # Handle IndirectObject (pypdf)
        if hasattr(value, "get_object"):
            try:
                value = value.get_object()
            except:
                pass
        
        if isinstance(value, str):
            cleaned = value.strip().strip('/').strip()
            return cleaned if cleaned else None
            
        if isinstance(value, bytes):
            try:
                cleaned = value.decode('utf-8', errors='ignore').strip()
                return cleaned if cleaned else None
            except:
                return None
                
        # Fallback to string representation, but avoid IndirectObject repr
        s = str(value)
        if s.startswith("IndirectObject") or s.startswith("<"):
            return None
            
        return s
    
    def _replace_file_with_retry(self, src_path: str, dst_path: str, max_retries: int = 3, delay: float = 1.0) -> None:
        """Replace dst_path with src_path, retrying on failure (e.g., OneDrive file locks).
        
        Uses os.replace first, falls back to shutil.copy2 + os.remove if that fails.
        """
        import time
        import shutil as _shutil
        
        last_error = None
        for attempt in range(1, max_retries + 1):
            try:
                os.replace(src_path, dst_path)
                logger.info(f"[PDF WRITE] os.replace succeeded on attempt {attempt}")
                return
            except OSError as e:
                last_error = e
                logger.warning(f"[PDF WRITE] os.replace failed (attempt {attempt}/{max_retries}): {e}")
                if attempt < max_retries:
                    logger.info(f"[PDF WRITE] Waiting {delay}s before retry (file may be locked by OneDrive/antivirus)...")
                    time.sleep(delay)
        
        # Fallback: copy + remove (works when os.replace fails due to cross-device or locks)
        logger.info(f"[PDF WRITE] Attempting fallback: shutil.copy2 + os.remove")
        try:
            _shutil.copy2(src_path, dst_path)
            os.remove(src_path)
            logger.info(f"[PDF WRITE] Fallback copy+remove succeeded")
            return
        except OSError as fallback_error:
            logger.error(f"[PDF WRITE] Fallback also failed: {fallback_error}")
            raise OSError(
                f"Cannot replace file (likely locked by OneDrive or another process). "
                f"Original error: {last_error}. Fallback error: {fallback_error}"
            ) from fallback_error

    async def _write_pdf_metadata(self, file_path: str, metadata: EbookMetadata) -> bool:
        """Write metadata to PDF file using pypdf"""
        from pypdf import PdfReader, PdfWriter
        import shutil
        import tempfile
        
        logger.info(f"[PDF WRITE] Starting PDF metadata write for: {file_path}")
        
        # Log file size before
        original_size = os.path.getsize(file_path)
        logger.info(f"[PDF WRITE] Original file size: {original_size} bytes")
        
        # Create backup
        backup_path = file_path + '.backup'
        shutil.copy2(file_path, backup_path)
        logger.info(f"[PDF WRITE] Backup created at: {backup_path}")
        
        try:
            reader = PdfReader(file_path)
            logger.info(f"[PDF WRITE] PDF loaded successfully, pages: {len(reader.pages)}")
            
            # Check for encryption
            if reader.is_encrypted:
                try:
                    # Try empty password (some PDFs have owner-only password)
                    if not reader.decrypt(''):
                        raise PermissionError(
                            "PDF is encrypted/password-protected and cannot be modified. "
                            "Remove the password protection first."
                        )
                    logger.info(f"[PDF WRITE] PDF was encrypted but decrypted with empty password")
                except Exception as decrypt_err:
                    raise PermissionError(
                        f"PDF is encrypted/password-protected: {decrypt_err}"
                    ) from decrypt_err
            
            # Log existing metadata before update
            existing_meta = reader.metadata
            if existing_meta:
                logger.info(f"[PDF WRITE] Existing PDF metadata:")
                for key in ['/Title', '/Author', '/Subject', '/Creator', '/Keywords', '/Producer']:
                    val = existing_meta.get(key)
                    logger.info(f"[PDF WRITE]   {key} = {val!r}")
            else:
                logger.info(f"[PDF WRITE] No existing metadata found in PDF")
            
            writer = PdfWriter()
            
            # Copy all pages
            for page in reader.pages:
                writer.add_page(page)
            logger.info(f"[PDF WRITE] Copied {len(reader.pages)} pages to writer")
            
            # Copy existing metadata
            if reader.metadata:
                writer.add_metadata(reader.metadata)
                logger.info(f"[PDF WRITE] Copied existing metadata to writer")
            
            # Update with new metadata
            new_metadata = {}
            if metadata.title:
                new_metadata['/Title'] = metadata.title
            if metadata.author:
                new_metadata['/Author'] = metadata.author
            if metadata.description:
                new_metadata['/Subject'] = metadata.description
            if metadata.publisher:
                new_metadata['/Creator'] = metadata.publisher
            
            # Add subjects as keywords (comma-separated)
            if metadata.subjects:
                new_metadata['/Keywords'] = ', '.join(metadata.subjects)
            
            logger.info(f"[PDF WRITE] New metadata to write: {new_metadata}")
            
            if not new_metadata:
                logger.warning(f"[PDF WRITE] WARNING: new_metadata dict is EMPTY — no fields to update! "
                               f"All metadata fields evaluated to falsy. "
                               f"title={metadata.title!r}, author={metadata.author!r}, "
                               f"description={metadata.description!r}, publisher={metadata.publisher!r}, "
                               f"subjects={metadata.subjects!r}")
            
            if new_metadata:
                writer.add_metadata(new_metadata)
                logger.info(f"[PDF WRITE] add_metadata() called with {len(new_metadata)} fields")
            
            # Write to a temporary file in system temp dir (avoids OneDrive interference)
            file_dir = os.path.dirname(file_path)
            file_name = os.path.basename(file_path)
            temp_fd, temp_path = tempfile.mkstemp(suffix='.pdf', prefix=f'{file_name}_tmp_')
            logger.info(f"[PDF WRITE] Using system temp file: {temp_path}")
            
            try:
                with os.fdopen(temp_fd, 'wb') as output_file:
                    writer.write(output_file)
                
                temp_size = os.path.getsize(temp_path)
                logger.info(f"[PDF WRITE] Temp file written: {temp_path} ({temp_size} bytes)")
                
                # Replace original with temp (with retry for OneDrive locks)
                self._replace_file_with_retry(temp_path, file_path)
                logger.info(f"[PDF WRITE] Replaced original file successfully")
            except Exception:
                # Clean up temp file on failure
                if os.path.exists(temp_path):
                    os.remove(temp_path)
                    logger.info(f"[PDF WRITE] Cleaned up temp file after failure")
                raise
            
            final_size = os.path.getsize(file_path)
            logger.info(f"[PDF WRITE] Final file size: {final_size} bytes (was {original_size} bytes, delta: {final_size - original_size} bytes)")
            
            # Verify: re-read the written file to confirm metadata was persisted
            try:
                verify_reader = PdfReader(file_path)
                verify_meta = verify_reader.metadata
                if verify_meta:
                    logger.info(f"[PDF WRITE] VERIFICATION — metadata after write:")
                    for key in ['/Title', '/Author', '/Subject', '/Creator', '/Keywords']:
                        val = verify_meta.get(key)
                        logger.info(f"[PDF WRITE]   {key} = {val!r}")
                    
                    # Check if the values actually match what we wrote
                    for key, expected_val in new_metadata.items():
                        actual_val = verify_meta.get(key)
                        if actual_val != expected_val:
                            logger.warning(f"[PDF WRITE] MISMATCH for {key}: expected={expected_val!r}, actual={actual_val!r}")
                        else:
                            logger.info(f"[PDF WRITE] VERIFIED {key} matches expected value")
                else:
                    logger.warning(f"[PDF WRITE] VERIFICATION FAILED — no metadata found after write!")
            except Exception as ve:
                logger.warning(f"[PDF WRITE] Verification read failed: {ve}")
            
            # Remove backup on success
            os.remove(backup_path)
            logger.info(f"[PDF WRITE] Backup removed. PDF metadata write completed successfully.")
            return True
            
        except Exception as e:
            logger.error(f"[PDF WRITE] Exception during PDF write: {e}", exc_info=True)
            # Restore from backup on failure
            if os.path.exists(backup_path):
                shutil.move(backup_path, file_path)
                logger.info(f"[PDF WRITE] Restored from backup after failure")
            raise e
    
    # ==================== MOBI ====================
    
    async def _read_mobi_metadata(self, file_path: str) -> EbookMetadata:
        """
        Read metadata from MOBI file.
        
        Note: MOBI format is proprietary (Amazon). Writing is very limited.
        Using raw header parsing as 'mobi' library is primarily for extraction.
        """
        # unexpected-import-fix: 'mobi' library installed via pip doesn't expose Mobi class.
        # It only exposes 'extract'. So we use our raw parser instead.
        return await self._read_mobi_metadata_raw(file_path)
    
    async def _read_mobi_metadata_raw(self, file_path: str) -> EbookMetadata:
        """
        Raw MOBI metadata parsing fallback.
        MOBI files have a PalmDOC header followed by MOBI-specific headers.
        """
        try:
            with open(file_path, 'rb') as f:
                # Read PalmDOC header (first 78 bytes)
                palm_header = f.read(78)
                
                # Get title from PalmDOC header (offset 0, 32 bytes, null-terminated)
                title_bytes = palm_header[0:32]
                title = title_bytes.split(b'\x00')[0].decode('utf-8', errors='ignore').strip()
                
                return EbookMetadata(title=title if title else None)
        except Exception as e:
            print(f"Error in raw MOBI parsing: {e}")
            return EbookMetadata()


# Singleton instance
metadata_service = MetadataService()
