"""
Ebook Metadata Service
Handles reading and writing metadata for various ebook formats.
"""

import os
from typing import Optional, Dict, List, Any
from dataclasses import dataclass, asdict
from pathlib import Path


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
        """Write metadata to supported ebook format"""
        if not os.path.exists(file_path):
            return False
        
        fmt = self.get_format(file_path)
        
        if fmt not in self.WRITABLE_FORMATS:
            return False
        
        try:
            if fmt == '.epub':
                return await self._write_epub_metadata(file_path, metadata)
            elif fmt == '.pdf':
                return await self._write_pdf_metadata(file_path, metadata)
            else:
                return False
        except Exception as e:
            print(f"Error writing metadata to {file_path}: {e}")
            return False
    
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
        
        reader = PdfReader(file_path)
        info = reader.metadata
        
        if not info:
            return EbookMetadata()
        
        # PDF standard metadata fields
        return EbookMetadata(
            title=info.get('/Title'),
            author=info.get('/Author'),
            description=info.get('/Subject'),  # PDF uses Subject for description
            publisher=info.get('/Creator'),    # Often the creating software
            # PDF doesn't have standard fields for:
            # language, date (has /CreationDate but format varies), subjects
        )
    
    async def _write_pdf_metadata(self, file_path: str, metadata: EbookMetadata) -> bool:
        """Write metadata to PDF file using pypdf"""
        from pypdf import PdfReader, PdfWriter
        import shutil
        
        # Create backup
        backup_path = file_path + '.backup'
        shutil.copy2(file_path, backup_path)
        
        try:
            reader = PdfReader(file_path)
            writer = PdfWriter()
            
            # Copy all pages
            for page in reader.pages:
                writer.add_page(page)
            
            # Copy existing metadata
            if reader.metadata:
                writer.add_metadata(reader.metadata)
            
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
            
            if new_metadata:
                writer.add_metadata(new_metadata)
            
            # Write to temporary file first
            temp_path = file_path + '.tmp'
            with open(temp_path, 'wb') as output_file:
                writer.write(output_file)
            
            # Replace original with temp
            os.replace(temp_path, file_path)
            
            # Remove backup on success
            os.remove(backup_path)
            return True
            
        except Exception as e:
            # Restore from backup on failure
            if os.path.exists(backup_path):
                shutil.move(backup_path, file_path)
            # Clean up temp file if exists
            temp_path = file_path + '.tmp'
            if os.path.exists(temp_path):
                os.remove(temp_path)
            raise e
    
    # ==================== MOBI ====================
    
    async def _read_mobi_metadata(self, file_path: str) -> EbookMetadata:
        """
        Read metadata from MOBI file.
        
        Note: MOBI format is proprietary (Amazon). Writing is very limited.
        The 'mobi' library can read but not write metadata effectively.
        """
        try:
            from mobi import Mobi
            
            book = Mobi(file_path)
            book.parse()
            
            # Extract available metadata
            return EbookMetadata(
                title=book.title() if hasattr(book, 'title') else None,
                author=book.author() if hasattr(book, 'author') else None,
                # MOBI has limited metadata fields exposed by the library
            )
        except ImportError:
            print("mobi library not installed. Install with: pip install mobi")
            return EbookMetadata()
        except Exception as e:
            print(f"Error reading MOBI metadata: {e}")
            # Try alternative approach using raw MOBI header parsing
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
