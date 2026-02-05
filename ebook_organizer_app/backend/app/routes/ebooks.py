"""Ebooks API endpoints"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
from app.services.database import get_db
from app.services.search_service import search_ebooks, get_search_suggestions
from app.models import Ebook, Tag, EbookResponse, EbookUpdate, LibraryStats
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

@router.get("/", response_model=List[EbookResponse])
async def get_ebooks(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    category: Optional[str] = None,
    sub_genre: Optional[str] = None,
    author: Optional[str] = None,
    search: Optional[str] = None,
    format: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """
    Get list of ebooks with filtering and pagination
    """
    query = db.query(Ebook)
    
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
    
    # Get total count before pagination
    total = query.count()
    
    # Apply pagination
    ebooks = query.offset(skip).limit(limit).all()
    
    # Convert to response format with tags
    result = []
    for ebook in ebooks:
        ebook_dict = EbookResponse.model_validate(ebook)
        ebook_dict.tags = [tag.name for tag in ebook.tags]
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
    return ebook_dict

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

@router.get("/stats/library", response_model=LibraryStats)
async def get_library_stats(db: Session = Depends(get_db)):
    """Get library statistics"""
    total_books = db.query(func.count(Ebook.id)).scalar()
    
    # Group by category
    by_category = {}
    categories = db.query(Ebook.category, func.count(Ebook.id)).group_by(Ebook.category).all()
    for category, count in categories:
        by_category[category or "Unknown"] = count
    
    # Group by format
    by_format = {}
    formats = db.query(Ebook.file_format, func.count(Ebook.id)).group_by(Ebook.file_format).all()
    for format, count in formats:
        by_format[format or "Unknown"] = count
    
    # Group by cloud provider
    by_cloud_provider = {}
    providers = db.query(Ebook.cloud_provider, func.count(Ebook.id)).group_by(Ebook.cloud_provider).all()
    for provider, count in providers:
        by_cloud_provider[provider] = count
    
    # Calculate total size
    total_size_bytes = db.query(func.sum(Ebook.file_size)).scalar() or 0
    total_size_mb = round(total_size_bytes / (1024 * 1024), 2)
    
    # Get last sync time
    last_sync = db.query(func.max(Ebook.last_synced)).scalar()
    
    return LibraryStats(
        total_books=total_books,
        by_category=by_category,
        by_format=by_format,
        by_cloud_provider=by_cloud_provider,
        total_size_mb=total_size_mb,
        last_sync=last_sync
    )
