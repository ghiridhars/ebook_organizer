"""Organization API endpoints"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional, Dict, Any
from pydantic import BaseModel
from dataclasses import asdict

from app.services.database import get_db
from app.services.organization_service import (
    get_taxonomy_tree,
    get_organization_stats,
    classify_single_ebook,
    batch_classify_ebooks,
    update_ebook_classification,
    get_books_by_category,
    preview_classification
)
from app.services.file_organizer_service import (
    generate_reorganize_plan,
    execute_reorganization,
)
from app.models import EbookResponse

router = APIRouter()


# =============================================================================
# REQUEST/RESPONSE MODELS
# =============================================================================

class ClassifyRequest(BaseModel):
    """Request to classify an ebook"""
    force_reclassify: bool = False
    
    
class BatchClassifyRequest(BaseModel):
    """Request to classify multiple ebooks"""
    ebook_ids: Optional[List[int]] = None
    source_path: Optional[str] = None
    force_reclassify: bool = False
    limit: int = 100
    # Manual overrides: {ebook_id: {category, sub_genre}}
    overrides: Optional[Dict[str, Dict[str, str]]] = None


class UpdateClassificationRequest(BaseModel):
    """Request to manually update classification"""
    category: Optional[str] = None
    sub_genre: Optional[str] = None


class ClassificationResultResponse(BaseModel):
    """Classification result for a single book"""
    category: Optional[str]
    sub_genre: Optional[str]
    author: Optional[str]
    metadata_source: str
    was_updated: bool = False


class BatchClassificationResponse(BaseModel):
    """Response for batch classification"""
    total_processed: int
    newly_classified: int
    already_classified: int
    failed: int
    # Map of file_path -> {category, sub_genre} for syncing to local storage
    classifications: Dict[str, Dict[str, Optional[str]]] = {}


class OrganizationStatsResponse(BaseModel):
    """Organization coverage statistics"""
    total_books: int
    classified_books: int
    unclassified_books: int
    by_category: Dict[str, int]
    by_sub_genre: Dict[str, int]
    coverage_percent: float


class ReorganizePreviewRequest(BaseModel):
    """Request for reorganization preview"""
    destination: str
    source_path: Optional[str] = None
    include_unclassified: bool = False
    operation: str = "move"


class PlannedMoveResponse(BaseModel):
    """A single planned file move"""
    ebook_id: int
    source_path: str
    target_path: str
    title: str
    author: str
    category: str
    sub_genre: str


class ReorganizePreviewResponse(BaseModel):
    """Response for reorganization preview"""
    destination: str
    operation: str
    total_files: int
    classified_files: int
    unclassified_files: int
    collisions: int
    planned_moves: List[PlannedMoveResponse]


class ReorganizeRequest(BaseModel):
    """Request to execute reorganization"""
    destination: str
    source_path: Optional[str] = None
    include_unclassified: bool = False
    operation: str = "move"


class ReorganizeResponse(BaseModel):
    """Response after reorganization"""
    total_processed: int
    succeeded: int
    skipped: int
    failed: int
    errors: List[str] = []
    path_mappings: Dict[str, str] = {}


# =============================================================================
# API ENDPOINTS
# =============================================================================

@router.get("/taxonomy")
async def get_taxonomy():
    """
    Get the full taxonomy tree structure.
    
    Returns all categories and their sub-genres for UI display.
    """
    return get_taxonomy_tree()


@router.get("/stats", response_model=OrganizationStatsResponse)
async def get_stats(
    source_path: Optional[str] = Query(None, description="Filter by source path prefix"),
    db: Session = Depends(get_db)
):
    """
    Get organization coverage statistics.
    
    Shows how many books are classified vs unclassified,
    and breakdown by category and sub-genre.
    """
    stats = get_organization_stats(db, source_path)
    return OrganizationStatsResponse(
        total_books=stats.total_books,
        classified_books=stats.classified_books,
        unclassified_books=stats.unclassified_books,
        by_category=stats.by_category,
        by_sub_genre=stats.by_sub_genre,
        coverage_percent=stats.coverage_percent
    )


@router.get("/preview")
async def preview(
    source_path: Optional[str] = Query(None, description="Filter by source path prefix"),
    limit: int = Query(100, ge=1, le=500, description="Number of books to preview"),
    db: Session = Depends(get_db)
):
    """
    Preview classification without applying changes.
    
    Returns a tree structure showing the proposed organization:
    Category -> SubGenre -> [books]
    
    Files are NOT modified - this is a dry run.
    """
    return preview_classification(db, source_path, limit)


@router.post("/classify/{ebook_id}", response_model=ClassificationResultResponse)
async def classify_ebook(
    ebook_id: int,
    request: ClassifyRequest = ClassifyRequest(),
    db: Session = Depends(get_db)
):
    """
    Classify a single ebook using the taxonomy system.
    
    Uses multiple strategies: embedded metadata, folder structure,
    Open Library API, and title keywords.
    """
    try:
        result, was_updated = classify_single_ebook(
            db, ebook_id, request.force_reclassify
        )
        return ClassificationResultResponse(
            category=result.category,
            sub_genre=result.sub_genre,
            author=result.author,
            metadata_source=result.metadata_source,
            was_updated=was_updated
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/batch-classify", response_model=BatchClassificationResponse)
async def batch_classify(
    request: BatchClassifyRequest,
    db: Session = Depends(get_db)
):
    """
    Classify multiple ebooks in batch.
    
    If ebook_ids is provided, classifies those specific books.
    Otherwise, classifies unclassified books (optionally filtered by source_path).
    """
    result = batch_classify_ebooks(
        db,
        ebook_ids=request.ebook_ids,
        source_path=request.source_path,
        force_reclassify=request.force_reclassify,
        limit=request.limit,
        overrides=request.overrides
    )
    return BatchClassificationResponse(
        total_processed=result.total_processed,
        newly_classified=result.newly_classified,
        already_classified=result.already_classified,
        failed=result.failed,
        classifications=result.file_classifications
    )


@router.put("/classify/{ebook_id}", response_model=EbookResponse)
async def update_classification(
    ebook_id: int,
    request: UpdateClassificationRequest,
    db: Session = Depends(get_db)
):
    """
    Manually update an ebook's classification.
    
    Validates that category and sub_genre exist in the taxonomy.
    """
    try:
        ebook = update_ebook_classification(
            db, ebook_id, request.category, request.sub_genre
        )
        return EbookResponse.model_validate(ebook)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/browse", response_model=List[EbookResponse])
async def browse_by_category(
    category: Optional[str] = Query(None, description="Filter by category"),
    sub_genre: Optional[str] = Query(None, description="Filter by sub-genre"),
    source_path: Optional[str] = Query(None, description="Filter by source path prefix"),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db)
):
    """
    Browse books by category and/or sub-genre.
    
    Useful for the organized view in the UI.
    """
    ebooks = get_books_by_category(
        db, category, sub_genre, source_path, skip, limit
    )
    return [EbookResponse.model_validate(ebook) for ebook in ebooks]


@router.get("/unclassified", response_model=List[EbookResponse])
async def get_unclassified(
    source_path: Optional[str] = Query(None, description="Filter by source path prefix"),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db)
):
    """
    Get books that haven't been classified yet.
    
    Useful for showing what needs organization.
    """
    from app.models.database import Ebook
    
    query = db.query(Ebook).filter(
        (Ebook.category.is_(None)) | (Ebook.category == '') |
        (Ebook.sub_genre.is_(None)) | (Ebook.sub_genre == '')
    )
    
    if source_path:
        query = query.filter(Ebook.cloud_file_path.like(f"{source_path}%"))
    
    ebooks = query.offset(skip).limit(limit).all()
    return [EbookResponse.model_validate(ebook) for ebook in ebooks]


@router.post("/reorganize-preview", response_model=ReorganizePreviewResponse)
async def reorganize_preview(
    request: ReorganizePreviewRequest,
    db: Session = Depends(get_db)
):
    """
    Preview file reorganization without executing.

    Returns a list of planned source -> target path mappings
    based on the Category/SubGenre/Author folder structure.
    """
    try:
        plan = generate_reorganize_plan(
            db,
            destination=request.destination,
            source_path=request.source_path,
            include_unclassified=request.include_unclassified,
            operation=request.operation,
        )
        return ReorganizePreviewResponse(
            destination=plan.destination,
            operation=plan.operation,
            total_files=plan.total_files,
            classified_files=plan.classified_files,
            unclassified_files=plan.unclassified_files,
            collisions=plan.collisions,
            planned_moves=[
                PlannedMoveResponse(
                    ebook_id=m.ebook_id,
                    source_path=m.source_path,
                    target_path=m.target_path,
                    title=m.title,
                    author=m.author,
                    category=m.category,
                    sub_genre=m.sub_genre,
                )
                for m in plan.planned_moves
            ],
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/reorganize", response_model=ReorganizeResponse)
async def reorganize(
    request: ReorganizeRequest,
    db: Session = Depends(get_db)
):
    """
    Execute file reorganization (move or copy).

    Moves/copies files into Category/SubGenre/Author folder structure
    and updates database paths for moved files.
    """
    try:
        result = execute_reorganization(
            db,
            destination=request.destination,
            source_path=request.source_path,
            include_unclassified=request.include_unclassified,
            operation=request.operation,
        )
        return ReorganizeResponse(
            total_processed=result.total_processed,
            succeeded=result.succeeded,
            skipped=result.skipped,
            failed=result.failed,
            errors=result.errors,
            path_mappings=result.path_mappings,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
