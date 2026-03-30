"""
Cover Art Extraction & Thumbnail Service

Extracts cover images from EPUB, PDF, and MOBI ebooks,
generates WebP thumbnails (400×600), and stores them in the covers directory.
"""

import os
import io
import logging
from typing import Optional
from pathlib import Path

from app.config import settings

logger = logging.getLogger(__name__)


class CoverService:
    """Extracts cover art from ebooks and generates WebP thumbnails."""

    THUMBNAIL_SIZE = (400, 600)
    WEBP_QUALITY = 80

    def __init__(self):
        os.makedirs(settings.COVERS_DIR, exist_ok=True)

    async def extract_cover(self, file_path: str, ebook_id: int, db=None) -> Optional[str]:
        """
        Extract cover from an ebook file and save as WebP thumbnail.

        Args:
            file_path: Path to the ebook file
            ebook_id: Database ID of the ebook (used as filename)
            db: Optional database session to update cover_path

        Returns:
            Path to the generated thumbnail, or None if extraction failed
        """
        ext = os.path.splitext(file_path)[1].lower()

        cover_bytes = None
        try:
            if ext == '.epub':
                cover_bytes = self._extract_epub_cover(file_path)
            elif ext == '.pdf':
                cover_bytes = self._extract_pdf_cover(file_path)
            elif ext in ('.mobi', '.azw', '.azw3'):
                cover_bytes = self._extract_mobi_cover(file_path)
        except Exception as e:
            logger.warning(f"Cover extraction failed for {file_path}: {e}")
            return None

        if not cover_bytes:
            logger.debug(f"No cover found in: {file_path}")
            return None

        # Generate thumbnail
        output_path = os.path.join(settings.COVERS_DIR, f"{ebook_id}.webp")
        try:
            thumbnail_path = self._generate_thumbnail(cover_bytes, output_path)
        except Exception as e:
            logger.warning(f"Thumbnail generation failed: {e}")
            return None

        # Update database if session provided
        if db and thumbnail_path:
            try:
                from app.models.database import Ebook
                ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
                if ebook:
                    ebook.cover_path = thumbnail_path
                    db.commit()
            except Exception as e:
                logger.warning(f"Failed to update cover_path in DB: {e}")

        return thumbnail_path

    def _extract_epub_cover(self, file_path: str) -> Optional[bytes]:
        """Extract cover image from EPUB file."""
        try:
            import ebooklib
            from ebooklib import epub

            book = epub.read_epub(file_path, options={'ignore_ncx': True})

            # Method 1: Check OPF metadata for cover reference
            cover_id = None
            for meta in book.get_metadata('OPF', 'meta'):
                attrs = meta[1] if len(meta) > 1 else {}
                if isinstance(attrs, dict) and attrs.get('name') == 'cover':
                    cover_id = attrs.get('content')
                    break

            if cover_id:
                for item in book.get_items():
                    if item.get_id() == cover_id:
                        return item.get_content()

            # Method 2: Look for item with cover-image property
            for item in book.get_items():
                if hasattr(item, 'get_type') and item.get_type() == ebooklib.ITEM_COVER:
                    return item.get_content()

            # Method 3: Look for image items with "cover" in the name
            for item in book.get_items_of_type(ebooklib.ITEM_IMAGE):
                item_name = (item.get_name() or '').lower()
                item_id = (item.get_id() or '').lower()
                if 'cover' in item_name or 'cover' in item_id:
                    return item.get_content()

            # Method 4: Just use the first image
            for item in book.get_items_of_type(ebooklib.ITEM_IMAGE):
                content = item.get_content()
                if content and len(content) > 1024:  # Skip tiny images (likely icons)
                    return content

        except Exception as e:
            logger.debug(f"EPUB cover extraction error: {e}")

        return None

    def _extract_pdf_cover(self, file_path: str) -> Optional[bytes]:
        """Extract cover from PDF first page (embedded images)."""
        try:
            from pypdf import PdfReader

            reader = PdfReader(file_path)
            if not reader.pages:
                return None

            first_page = reader.pages[0]

            # Try to extract embedded images from the first page
            if '/XObject' in (first_page.get('/Resources') or {}):
                x_objects = first_page['/Resources']['/XObject'].get_object()
                for obj_name in x_objects:
                    obj = x_objects[obj_name].get_object()
                    if obj.get('/Subtype') == '/Image':
                        # Extract image data
                        data = obj.get_data()
                        if data and len(data) > 1024:
                            # Check if it's a JPEG (most common)
                            filter_type = obj.get('/Filter')
                            if filter_type == '/DCTDecode':
                                return data
                            elif filter_type == '/FlateDecode':
                                # Raw image data — need width/height/color info
                                width = obj.get('/Width', 0)
                                height = obj.get('/Height', 0)
                                if width > 100 and height > 100:
                                    try:
                                        from PIL import Image
                                        color_space = obj.get('/ColorSpace', '/DeviceRGB')
                                        if color_space == '/DeviceRGB':
                                            mode = 'RGB'
                                        elif color_space == '/DeviceGray':
                                            mode = 'L'
                                        else:
                                            mode = 'RGB'

                                        img = Image.frombytes(mode, (width, height), data)
                                        buf = io.BytesIO()
                                        img.save(buf, format='PNG')
                                        return buf.getvalue()
                                    except Exception:
                                        pass
                            elif isinstance(filter_type, list) and '/DCTDecode' in filter_type:
                                return data

        except Exception as e:
            logger.debug(f"PDF cover extraction error: {e}")

        return None

    def _extract_mobi_cover(self, file_path: str) -> Optional[bytes]:
        """Extract cover from MOBI/AZW file."""
        try:
            import mobi
            import tempfile

            # mobi library extracts to a temp directory
            with tempfile.TemporaryDirectory() as tmp_dir:
                try:
                    tempdir, filepath = mobi.extract(file_path)
                except Exception:
                    return None

                # Look for cover image in extracted content
                if tempdir and os.path.exists(tempdir):
                    for root, _, files in os.walk(tempdir):
                        for f in sorted(files):
                            lower_f = f.lower()
                            if ('cover' in lower_f and
                                any(lower_f.endswith(ext) for ext in ('.jpg', '.jpeg', '.png', '.gif'))):
                                img_path = os.path.join(root, f)
                                with open(img_path, 'rb') as img_file:
                                    return img_file.read()

                    # Fallback: first large image
                    for root, _, files in os.walk(tempdir):
                        for f in sorted(files):
                            if any(f.lower().endswith(ext) for ext in ('.jpg', '.jpeg', '.png', '.gif')):
                                img_path = os.path.join(root, f)
                                if os.path.getsize(img_path) > 1024:
                                    with open(img_path, 'rb') as img_file:
                                        return img_file.read()

        except Exception as e:
            logger.debug(f"MOBI cover extraction error: {e}")

        return None

    def _generate_thumbnail(self, image_bytes: bytes, output_path: str) -> Optional[str]:
        """Generate a WebP thumbnail from raw image bytes."""
        try:
            from PIL import Image

            img = Image.open(io.BytesIO(image_bytes))

            # Convert to RGB if necessary (handles RGBA, palette, etc.)
            if img.mode not in ('RGB', 'L'):
                img = img.convert('RGB')

            # Resize maintaining aspect ratio
            img.thumbnail(self.THUMBNAIL_SIZE, Image.LANCZOS)

            # Save as WebP
            img.save(output_path, "WEBP", quality=self.WEBP_QUALITY)

            logger.debug(f"Thumbnail saved: {output_path} ({os.path.getsize(output_path)} bytes)")
            return output_path

        except Exception as e:
            logger.warning(f"Thumbnail generation error: {e}")
            return None

    async def batch_extract(self, ebook_ids: list, db) -> dict:
        """
        Extract covers for multiple ebooks in batch.

        Args:
            ebook_ids: List of ebook IDs, or empty list for all missing covers
            db: Database session

        Returns:
            Summary dict with counts
        """
        from app.models.database import Ebook

        query = db.query(Ebook)
        if ebook_ids:
            query = query.filter(Ebook.id.in_(ebook_ids))
        else:
            # All ebooks without covers
            query = query.filter(
                (Ebook.cover_path == None) | (Ebook.cover_path == '')
            )

        ebooks = query.all()
        total = len(ebooks)
        success = 0
        failed = 0

        for ebook in ebooks:
            if not ebook.cloud_file_path or not os.path.exists(ebook.cloud_file_path):
                failed += 1
                continue

            result = await self.extract_cover(ebook.cloud_file_path, ebook.id, db)
            if result:
                success += 1
            else:
                failed += 1

        return {
            "total": total,
            "success": success,
            "failed": failed,
        }


# Singleton instance
cover_service = CoverService()
