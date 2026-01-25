"""
Metadata API endpoints
Handles reading and writing ebook metadata for local files.
"""

from fastapi import APIRouter, UploadFile, File, HTTPException, Query
from pydantic import BaseModel
from typing import Dict, Optional, List
import tempfile
import os
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
    
    # Validate file exists
    if not os.path.exists(decoded_path):
        raise HTTPException(status_code=404, detail=f"File not found: {decoded_path}")
    
    # Check format is writable
    if not metadata_service.is_writable(decoded_path):
        fmt = metadata_service.get_format(decoded_path)
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
    
    # Write metadata
    try:
        success = await metadata_service.write_metadata(decoded_path, metadata)
        
        if success:
            return MetadataUpdateResponse(
                success=True,
                file_path=decoded_path,
                message=f"Metadata successfully updated for {os.path.basename(decoded_path)}"
            )
        else:
            return MetadataUpdateResponse(
                success=False,
                file_path=decoded_path,
                message="Failed to update metadata",
                error="Unknown error during write operation"
            )
    except Exception as e:
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
