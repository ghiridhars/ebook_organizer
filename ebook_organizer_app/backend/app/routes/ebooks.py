"""Ebooks API endpoints"""

import os
from fastapi import APIRouter, Depends, HTTPException, Query, Request, BackgroundTasks, UploadFile, File
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
from app.services.database import get_db
from app.services.search_service import search_ebooks, get_search_suggestions
from app.models import Ebook, Tag, EbookResponse, EbookUpdate, LibraryStats
from app.config import settings
from sqlalchemy import func

router = APIRouter()


# Search response models
class SearchHit(BaseModel):
    """Individual search result"""
    id: int
    title: str
    author: Optional[str]
    category: Optional[str]
    sub_genre: Optional[str]
    format: Optional[str]
    score: float
    snippet: Optional[str] = None

    class Config:
        from_attributes = True


class SearchResponse(BaseModel):
    """Search results response"""
    query: str
    total: int
    page: int
    page_size: int
    results: List[SearchHit]


@router.get("/search", response_model=SearchResponse)
async def search_library(
    q: str = Query(..., min_length=1, description="Search query"),
    category: Optional[str] = Query(None, description="Filter by category"),
    format: Optional[str] = Query(None, description="Filter by format"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Results per page"),
    db: Session = Depends(get_db)
):
    """
    Full-text search across ebooks using FTS5.
    
    Searches title, author, and description fields with relevance ranking.
    """
    offset = (page - 1) * page_size
    
    results, total = search_ebooks(
        db=db,
        query=q,
        category=category,
        format=format,
        limit=page_size,
        offset=offset
    )
    
    hits = []
    for result in results:
        hits.append(SearchHit(
            id=result.ebook.id,
            title=result.ebook.title,
            author=result.ebook.author,
            category=result.ebook.category,
            sub_genre=result.ebook.sub_genre,
            format=result.ebook.file_format,
            score=result.score,
            snippet=result.snippet
        ))
    
    return SearchResponse(
        query=q,
        total=total,
        page=page,
        page_size=page_size,
        results=hits
    )


@router.get("/search/suggestions")
async def get_suggestions(
    prefix: str = Query(..., min_length=2, description="Search prefix"),
    limit: int = Query(5, ge=1, le=10, description="Max suggestions"),
    db: Session = Depends(get_db)
):
    """Get search suggestions based on existing titles and authors"""
    suggestions = get_search_suggestions(db, prefix, limit)
    return {"suggestions": suggestions}


@router.get("/stats/library", response_model=LibraryStats)
async def get_library_stats(
    source_path: Optional[str] = Query(None, description="Filter by source path prefix"),
    db: Session = Depends(get_db)
):
    """Get library statistics, optionally scoped to a source path"""
    # Build base filter
    base_filter = []
    if source_path:
        base_filter.append(Ebook.cloud_file_path.startswith(source_path))
    
    total_books = db.query(func.count(Ebook.id)).filter(*base_filter).scalar() or 0
    
    # Group by category
    by_category = {}
    categories = db.query(Ebook.category, func.count(Ebook.id)).filter(*base_filter).group_by(Ebook.category).all()
    for category, count in categories:
        by_category[category or "Unknown"] = count
    
    # Group by format
    by_format = {}
    formats = db.query(Ebook.file_format, func.count(Ebook.id)).filter(*base_filter).group_by(Ebook.file_format).all()
    for fmt, count in formats:
        by_format[fmt or "Unknown"] = count
    
    # Group by cloud provider
    by_cloud_provider = {}
    providers = db.query(Ebook.cloud_provider, func.count(Ebook.id)).filter(*base_filter).group_by(Ebook.cloud_provider).all()
    for provider, count in providers:
        by_cloud_provider[provider] = count
    
    # Calculate total size
    total_size_bytes = db.query(func.sum(Ebook.file_size)).filter(*base_filter).scalar() or 0
    total_size_mb = round(total_size_bytes / (1024 * 1024), 2)
    
    # Get last sync time
    last_sync = db.query(func.max(Ebook.last_synced)).filter(*base_filter).scalar()
    
    return LibraryStats(
        total_books=total_books,
        by_category=by_category,
        by_format=by_format,
        by_cloud_provider=by_cloud_provider,
        total_size_mb=total_size_mb,
        last_sync=last_sync
    )


@router.post("/upload")
async def upload_ebook(file: UploadFile = File(...)):
    """
    Upload an ebook to the watcher inbox directory.
    The background watcher service will eventually pick it up, extract metadata,
    and add it to the library.
    """
    if not settings.WATCH_DIR.exists():
        settings.WATCH_DIR.mkdir(parents=True, exist_ok=True)
        
    file_path = settings.WATCH_DIR / file.filename
    try:
        content = await file.read()
        with open(file_path, "wb") as f:
            f.write(content)
        return {"filename": file.filename, "status": "uploaded", "message": "File is queued for processing."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save file: {e}")


@router.get("/authors", response_model=List[str])
async def get_authors(
    source_path: Optional[str] = Query(None, description="Filter by source path prefix"),
    db: Session = Depends(get_db)
):
    """Get a list of all unique authors in the library"""
    query = db.query(Ebook.author).filter(Ebook.author.isnot(None), Ebook.author != '')
    if source_path:
        query = query.filter(Ebook.cloud_file_path.startswith(source_path))
    
    # Use distinct to get unique authors, ordered alphabetically
    authors = query.distinct().order_by(Ebook.author).all()
    # Flatten list of tuples
    return [author[0] for author in authors]


@router.get("/", response_model=List[EbookResponse])
async def get_ebooks(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    category: Optional[str] = None,
    sub_genre: Optional[str] = None,
    author: Optional[str] = None,
    search: Optional[str] = None,
    format: Optional[str] = None,
    sort: Optional[str] = Query(None, description="Sort field (created_at, title, author)"),
    order: Optional[str] = Query("desc", description="Sort order (asc, desc)"),
    source_path: Optional[str] = Query(None, description="Filter by source path prefix"),
    db: Session = Depends(get_db)
):
    """
    Get list of ebooks with filtering and pagination.
    Use source_path to scope results to a specific folder.
    """
    query = db.query(Ebook)
    
    # Filter by source path (scoped library)
    if source_path:
        query = query.filter(Ebook.cloud_file_path.startswith(source_path))
    
    # Apply filters
    if category:
        query = query.filter(Ebook.category == category)
    if sub_genre:
        query = query.filter(Ebook.sub_genre == sub_genre)
    if author:
        query = query.filter(Ebook.author.ilike(f"%{author}%"))
    if search:
        query = query.filter(
            (Ebook.title.ilike(f"%{search}%")) |
            (Ebook.author.ilike(f"%{search}%")) |
            (Ebook.description.ilike(f"%{search}%"))
        )
    if format:
        query = query.filter(Ebook.file_format == format)
    
    # Apply sorting
    if sort:
        sort_column = getattr(Ebook, sort, None)
        if sort_column is not None:
            if order == "asc":
                query = query.order_by(sort_column.asc())
            else:
                query = query.order_by(sort_column.desc())
    
    # Get total count before pagination
    total = query.count()
    
    # Apply pagination
    ebooks = query.offset(skip).limit(limit).all()
    
    # Convert to response format with tags and cover URLs
    result = []
    for ebook in ebooks:
        ebook_dict = EbookResponse.model_validate(ebook)
        ebook_dict.tags = [tag.name for tag in ebook.tags]
        # Generate cover URL if cover exists
        if ebook.cover_path and os.path.exists(ebook.cover_path):
            ebook_dict.cover_url = f"/api/ebooks/{ebook.id}/cover"
        result.append(ebook_dict)
    
    return result

@router.get("/{ebook_id}", response_model=EbookResponse)
async def get_ebook(ebook_id: int, db: Session = Depends(get_db)):
    """Get a specific ebook by ID"""
    ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
    if not ebook:
        raise HTTPException(status_code=404, detail="Ebook not found")
    
    ebook_dict = EbookResponse.model_validate(ebook)
    ebook_dict.tags = [tag.name for tag in ebook.tags]
    if ebook.cover_path and os.path.exists(ebook.cover_path):
        ebook_dict.cover_url = f"/api/ebooks/{ebook.id}/cover"
    return ebook_dict


@router.get("/{ebook_id}/cover")
async def get_ebook_cover(ebook_id: int, db: Session = Depends(get_db)):
    """
    Get cover art for an ebook.
    Returns the WebP thumbnail if available, or generates it on-the-fly.
    """
    ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
    if not ebook:
        raise HTTPException(status_code=404, detail="Ebook not found")

    # Serve existing cover
    if ebook.cover_path and os.path.exists(ebook.cover_path):
        return FileResponse(
            ebook.cover_path,
            media_type="image/webp",
            headers={"Cache-Control": "public, max-age=604800"}  # Cache 7 days
        )

    # Try to generate on-the-fly
    if ebook.cloud_file_path and os.path.exists(ebook.cloud_file_path):
        try:
            from app.services.cover_service import cover_service
            cover_path = await cover_service.extract_cover(ebook.cloud_file_path, ebook_id, db)
            if cover_path and os.path.exists(cover_path):
                return FileResponse(
                    cover_path,
                    media_type="image/webp",
                    headers={"Cache-Control": "public, max-age=604800"}
                )
        except Exception:
            pass

    raise HTTPException(status_code=404, detail="No cover available")


@router.get("/{ebook_id}/download")
async def download_ebook(ebook_id: int, db: Session = Depends(get_db)):
    """Download an ebook file."""
    ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
    if not ebook:
        raise HTTPException(status_code=404, detail="Ebook not found")

    file_path = ebook.cloud_file_path
    if not file_path or not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found on disk")

    # Security: prevent path traversal
    _validate_file_path(file_path)

    filename = f"{ebook.title}.{ebook.file_format}" if ebook.title else os.path.basename(file_path)
    # Sanitize filename for Content-Disposition
    filename = filename.replace('"', "'")

    media_type = _get_media_type(ebook.file_format)

    return FileResponse(
        path=file_path,
        filename=filename,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'}
    )


@router.get("/{ebook_id}/stream")
async def stream_ebook(ebook_id: int, db: Session = Depends(get_db)):
    """
    Stream an ebook file with HTTP Range support.
    Required for epub.js progressive chapter loading.
    Starlette's FileResponse supports Range requests natively.
    """
    ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
    if not ebook:
        raise HTTPException(status_code=404, detail="Ebook not found")

    file_path = ebook.cloud_file_path
    if not file_path or not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found on disk")

    # Security: prevent path traversal
    _validate_file_path(file_path)

    media_type = _get_media_type(ebook.file_format)

    return FileResponse(
        path=file_path,
        media_type=media_type,
        headers={
            "Accept-Ranges": "bytes",
            "Cache-Control": "public, max-age=86400",  # Cache 24h
        }
    )


@router.post("/extract-covers")
async def batch_extract_covers(
    background_tasks: BackgroundTasks,
    ebook_ids: Optional[List[int]] = None,
    db: Session = Depends(get_db)
):
    """
    Batch extract covers for ebooks.
    If ebook_ids is empty/None, extracts for all ebooks missing covers.
    Runs as a background task.
    """
    from app.services.cover_service import cover_service

    async def _batch_extract():
        from app.services.database import SessionLocal
        batch_db = SessionLocal()
        try:
            result = await cover_service.batch_extract(ebook_ids or [], batch_db)
            return result
        finally:
            batch_db.close()

    background_tasks.add_task(_batch_extract)

    return {"message": "Cover extraction started in background", "ebook_ids": ebook_ids or "all_missing"}


@router.patch("/{ebook_id}", response_model=EbookResponse)
async def update_ebook(
    ebook_id: int,
    ebook_update: EbookUpdate,
    db: Session = Depends(get_db)
):
    """Update ebook metadata"""
    ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
    if not ebook:
        raise HTTPException(status_code=404, detail="Ebook not found")
    
    # Update fields
    update_data = ebook_update.model_dump(exclude_unset=True)
    
    # Handle tags separately
    if "tags" in update_data:
        tags_list = update_data.pop("tags")
        # Remove existing tags
        db.query(Tag).filter(Tag.ebook_id == ebook_id).delete()
        # Add new tags
        for tag_name in tags_list:
            new_tag = Tag(ebook_id=ebook_id, name=tag_name)
            db.add(new_tag)
    
    # Update other fields
    for key, value in update_data.items():
        setattr(ebook, key, value)
    
    ebook.is_synced = False
    ebook.sync_status = "pending"
    
    db.commit()
    db.refresh(ebook)
    
    ebook_dict = EbookResponse.model_validate(ebook)
    ebook_dict.tags = [tag.name for tag in ebook.tags]
    if ebook.cover_path and os.path.exists(ebook.cover_path):
        ebook_dict.cover_url = f"/api/ebooks/{ebook.id}/cover"
    return ebook_dict

@router.delete("/{ebook_id}")
async def delete_ebook(ebook_id: int, db: Session = Depends(get_db)):
    """Delete an ebook from local database (does not delete from cloud)"""
    ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
    if not ebook:
        raise HTTPException(status_code=404, detail="Ebook not found")
    
    db.delete(ebook)
    db.commit()
    return {"message": "Ebook deleted successfully"}


# ─── Helpers ───────────────────────────────────────────────────────────────

def _get_media_type(file_format: str) -> str:
    """Map ebook format to MIME type."""
    media_types = {
        "epub": "application/epub+zip",
        "pdf": "application/pdf",
        "mobi": "application/x-mobipocket-ebook",
        "azw": "application/x-mobipocket-ebook",
        "azw3": "application/x-mobipocket-ebook",
    }
    return media_types.get(file_format, "application/octet-stream")


def _validate_file_path(file_path: str):
    """
    Validate that a file path is within the LIBRARY_DIR.
    Prevents path traversal attacks.
    """
    real_path = os.path.realpath(file_path)
    library_real = os.path.realpath(settings.LIBRARY_DIR)

    # Also allow paths relative to the app directory (for dev / non-Pi environments)
    app_dir = os.path.realpath(".")

    if not (real_path.startswith(library_real) or real_path.startswith(app_dir)):
        raise HTTPException(status_code=403, detail="Access denied")
