"""
Metadata API endpoints
Handles reading and writing ebook metadata for local files.
"""

import logging
from fastapi import APIRouter, UploadFile, File, HTTPException, Query
from pydantic import BaseModel
from typing import Dict, Optional, List
import tempfile
import os

logger = logging.getLogger(__name__)
import urllib.parse

from app.services.metadata_service import metadata_service, EbookMetadata

router = APIRouter()


# ==================== Response/Request Models ====================

class MetadataResponse(BaseModel):
    """Response model for metadata read operations"""
    success: bool
    file_path: str
    format: str
    writable: bool
    metadata: Optional[dict] = None
    error: Optional[str] = None


class MetadataUpdateRequest(BaseModel):
    """Request model for metadata update operations"""
    title: Optional[str] = None
    author: Optional[str] = None
    description: Optional[str] = None
    publisher: Optional[str] = None
    language: Optional[str] = None
    subjects: Optional[List[str]] = None


class MetadataUpdateResponse(BaseModel):
    """Response model for metadata update operations"""
    success: bool
    file_path: str
    message: str
    error: Optional[str] = None


# ==================== Local File Metadata Endpoints ====================

@router.get("/read")
async def read_metadata(file_path: str = Query(..., description="URL-encoded file path")):
    """
    Read metadata from a local ebook file.
    
    Supported formats: EPUB, PDF, MOBI
    
    Note: file_path should be URL-encoded to handle special characters and spaces.
    """
    # Decode the file path
    decoded_path = urllib.parse.unquote(file_path)
    
    # Validate file exists
    if not os.path.exists(decoded_path):
        raise HTTPException(status_code=404, detail=f"File not found: {decoded_path}")
    
    # Check format is supported
    if not metadata_service.is_supported(decoded_path):
        fmt = metadata_service.get_format(decoded_path)
        raise HTTPException(
            status_code=400, 
            detail=f"Unsupported format: {fmt}. Supported: {list(metadata_service.SUPPORTED_FORMATS)}"
        )
    
    # Read metadata
    try:
        metadata = await metadata_service.read_metadata(decoded_path)
        
        return MetadataResponse(
            success=True,
            file_path=decoded_path,
            format=metadata_service.get_format(decoded_path),
            writable=metadata_service.is_writable(decoded_path),
            metadata=metadata.to_dict() if metadata else None
        )
    except Exception as e:
        return MetadataResponse(
            success=False,
            file_path=decoded_path,
            format=metadata_service.get_format(decoded_path),
            writable=metadata_service.is_writable(decoded_path),
            error=str(e)
        )


@router.put("/write")
async def write_metadata(
    file_path: str = Query(..., description="URL-encoded file path"),
    request: MetadataUpdateRequest = None
):
    """
    Write metadata to a local ebook file.
    
    Writable formats: EPUB, PDF
    Note: MOBI format is read-only (proprietary format).
    
    Only provided fields will be updated.
    """
    # Decode the file path
    decoded_path = urllib.parse.unquote(file_path)
    logger.info(f"[METADATA API] PUT /write called for: {decoded_path}")
    logger.info(f"[METADATA API] Request body: title={request.title if request else None!r}, "
                 f"author={request.author if request else None!r}, "
                 f"description={request.description if request else None!r}, "
                 f"publisher={request.publisher if request else None!r}, "
                 f"language={request.language if request else None!r}, "
                 f"subjects={request.subjects if request else None!r}")
    
    # Validate file exists
    if not os.path.exists(decoded_path):
        logger.error(f"[METADATA API] File not found: {decoded_path}")
        raise HTTPException(status_code=404, detail=f"File not found: {decoded_path}")
    
    # Check format is writable
    if not metadata_service.is_writable(decoded_path):
        fmt = metadata_service.get_format(decoded_path)
        logger.warning(f"[METADATA API] Format not writable: {fmt}")
        if fmt == '.mobi':
            raise HTTPException(
                status_code=400,
                detail="MOBI format is read-only. Amazon's MOBI format is proprietary and cannot be reliably modified."
            )
        raise HTTPException(
            status_code=400,
            detail=f"Format {fmt} is not writable. Writable formats: {list(metadata_service.WRITABLE_FORMATS)}"
        )
    
    # Build metadata object from request
    metadata = EbookMetadata(
        title=request.title if request else None,
        author=request.author if request else None,
        description=request.description if request else None,
        publisher=request.publisher if request else None,
        language=request.language if request else None,
        subjects=request.subjects if request and request.subjects else [],
    )
    logger.info(f"[METADATA API] Built EbookMetadata object: {metadata.to_dict()}")
    
    # Write metadata
    try:
        success = await metadata_service.write_metadata(decoded_path, metadata)
        logger.info(f"[METADATA API] write_metadata returned: {success}")
        
        return MetadataUpdateResponse(
            success=True,
            file_path=decoded_path,
            message=f"Metadata successfully updated for {os.path.basename(decoded_path)}"
        )
    except PermissionError as e:
        logger.error(f"[METADATA API] Permission error: {e}", exc_info=True)
        return MetadataUpdateResponse(
            success=False,
            file_path=decoded_path,
            message="Failed to update metadata",
            error=f"Permission denied: {e}. The file may be encrypted, read-only, or locked by OneDrive/another process."
        )
    except OSError as e:
        logger.error(f"[METADATA API] OS error during metadata write: {e}", exc_info=True)
        error_detail = str(e)
        if 'Errno 22' in error_detail or 'Invalid argument' in error_detail:
            error_detail = (f"{e}. This often happens with files in OneDrive/cloud-synced folders. "
                           f"Try: (1) ensure the file is fully downloaded (not cloud-only), "
                           f"(2) pause OneDrive sync, or (3) copy the file to a local folder first.")
        return MetadataUpdateResponse(
            success=False,
            file_path=decoded_path,
            message="Failed to update metadata",
            error=error_detail
        )
    except Exception as e:
        logger.error(f"[METADATA API] Exception during metadata write: {e}", exc_info=True)
        return MetadataUpdateResponse(
            success=False,
            file_path=decoded_path,
            message="Failed to update metadata",
            error=str(e)
        )


@router.get("/supported-formats")
async def get_supported_formats():
    """
    Get list of supported formats and their capabilities.
    """
    return {
        "formats": [
            {
                "extension": ".epub",
                "name": "EPUB",
                "readable": True,
                "writable": True,
                "notes": "Full metadata support using Dublin Core standard"
            },
            {
                "extension": ".pdf",
                "name": "PDF",
                "readable": True,
                "writable": True,
                "notes": "Standard PDF metadata (Title, Author, Subject, Keywords)"
            },
            {
                "extension": ".mobi",
                "name": "MOBI/AZW",
                "readable": True,
                "writable": False,
                "notes": "Read-only. Amazon's proprietary format cannot be reliably modified."
            }
        ]
    }


# ==================== Upload-based Endpoints (Legacy) ====================

@router.post("/extract")
async def extract_metadata(file: UploadFile = File(...)) -> Dict:
    """
    Extract metadata from uploaded ebook file.
    """
    # Validate file format
    file_ext = os.path.splitext(file.filename)[1].lower()
    
    if not metadata_service.is_supported(f"test{file_ext}"):
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported format: {file_ext}. Supported: {list(metadata_service.SUPPORTED_FORMATS)}"
        )
    
    # Save to temp file and extract
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=file_ext) as tmp:
            content = await file.read()
            tmp.write(content)
            tmp_path = tmp.name
        
        metadata = await metadata_service.read_metadata(tmp_path)
        
        # Clean up temp file
        os.unlink(tmp_path)
        
        return {
            "success": True,
            "filename": file.filename,
            "format": file_ext,
            "metadata": metadata.to_dict() if metadata else None
        }
    except Exception as e:
        # Clean up temp file on error
        if 'tmp_path' in locals():
            os.unlink(tmp_path)
        raise HTTPException(status_code=500, detail=str(e))


# ==================== Classification Endpoints ====================

@router.post("/classify")
async def classify_file(request: Dict):
    """
    Classify an ebook file to determine category, sub-genre, and author.
    
    Uses multiple classification strategies:
    1. Embedded metadata (genre/subject)
    2. Folder-based classification
    3. Open Library API lookup
    4. Title/filename keyword analysis
    """
    from app.services.metadata_classifier import classify_book, is_valid_author
    from app.services.metadata_service import metadata_service
    from pathlib import Path
    from app.models import ClassificationResponse
    
    file_path = request.get("file_path")
    if not file_path:
        raise HTTPException(status_code=400, detail="file_path is required")
    
    # Validate file exists
    if not os.path.exists(file_path):
        return ClassificationResponse(
            success=False,
            file_path=file_path,
            error=f"File not found: {file_path}"
        )
    
    # Check format is supported
    if not metadata_service.is_supported(file_path):
        fmt = metadata_service.get_format(file_path)
        return ClassificationResponse(
            success=False,
            file_path=file_path,
            error=f"Unsupported format: {fmt}"
        )
    
    try:
        # Read embedded metadata first
        embedded_metadata = await metadata_service.read_metadata(file_path)
        embedded_genre = None
        embedded_author = None
        
        if embedded_metadata:
            # Use first subject as genre if available
            if embedded_metadata.subjects:
                embedded_genre = embedded_metadata.subjects[0]
            embedded_author = embedded_metadata.author
        
        # Run classification
        classification_result = classify_book(
            filepath=Path(file_path),
            embedded_genre=embedded_genre,
            embedded_author=embedded_author
        )
        
        return ClassificationResponse(
            success=True,
            file_path=file_path,
            category=classification_result.category,
            sub_genre=classification_result.sub_genre,
            author=classification_result.author,
            metadata_source=classification_result.metadata_source
        )
        
    except Exception as e:
        return ClassificationResponse(
            success=False,
            file_path=file_path,
            error=str(e)
        )


@router.post("/extract-comprehensive")
async def extract_comprehensive_metadata(request: Dict):
    """
    Extract comprehensive metadata including embedded data and classification.
    
    Returns both:
    - Embedded metadata (title, author, description, etc.)
    - Classification results (category, sub_genre, author refinement)
    """
    from app.services.metadata_classifier import classify_book
    from app.services.metadata_service import metadata_service
    from pathlib import Path
    from app.models import (
        ComprehensiveMetadataResponse,
        ClassificationResponse,
        BasicMetadata
    )
    
    file_path = request.get("file_path")
    include_classification = request.get("include_classification", True)
    
    if not file_path:
        raise HTTPException(status_code=400, detail="file_path is required")
    
    # Validate file exists
    if not os.path.exists(file_path):
        return ComprehensiveMetadataResponse(
            success=False,
            file_path=file_path,
            file_format="unknown",
            error=f"File not found: {file_path}"
        )
    
    file_format = metadata_service.get_format(file_path)
    
    # Check format is supported
    if not metadata_service.is_supported(file_path):
        return ComprehensiveMetadataResponse(
            success=False,
            file_path=file_path,
            file_format=file_format,
            error=f"Unsupported format: {file_format}"
        )
    
    try:
        # Read embedded metadata
        embedded_metadata = await metadata_service.read_metadata(file_path)
        
        basic_metadata = None
        if embedded_metadata:
            basic_metadata = BasicMetadata(
                title=embedded_metadata.title,
                author=embedded_metadata.author,
                description=embedded_metadata.description,
                publisher=embedded_metadata.publisher,
                language=embedded_metadata.language,
                date=embedded_metadata.date,
                subjects=embedded_metadata.subjects or [],
                identifier=embedded_metadata.identifier
            )
        
        # Run classification if requested
        classification = None
        if include_classification:
            embedded_genre = None
            embedded_author = None
            
            if embedded_metadata:
                if embedded_metadata.subjects:
                    embedded_genre = embedded_metadata.subjects[0]
                embedded_author = embedded_metadata.author
            
            classification_result = classify_book(
                filepath=Path(file_path),
                embedded_genre=embedded_genre,
                embedded_author=embedded_author
            )
            
            classification = ClassificationResponse(
                success=True,
                file_path=file_path,
                category=classification_result.category,
                sub_genre=classification_result.sub_genre,
                author=classification_result.author,
                metadata_source=classification_result.metadata_source
            )
        
        return ComprehensiveMetadataResponse(
            success=True,
            file_path=file_path,
            file_format=file_format,
            embedded_metadata=basic_metadata,
            classification=classification
        )
        
    except Exception as e:
        return ComprehensiveMetadataResponse(
            success=False,
            file_path=file_path,
            file_format=file_format,
            error=str(e)
        )


@router.post("/analyze-cloud-file/{provider}/{file_id}")
async def analyze_cloud_file(provider: str, file_id: str):
    """
    Download and analyze metadata from cloud storage file
    TODO: Implement cloud file download and metadata extraction
    """
    return {
        "message": "Cloud file analysis not yet implemented",
        "provider": provider,
        "file_id": file_id
    }
