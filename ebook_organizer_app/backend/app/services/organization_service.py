"""
Organization Service

Provides ebook organization capabilities:
- Auto-classification of ebooks using taxonomy
- Batch classification for multiple ebooks
- Statistics on organization coverage
"""

from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass, asdict
from pathlib import Path
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models.database import Ebook
from app.services.metadata_classifier import (
    ClassificationResult,
    classify_book,
    is_valid_author,
    clean_author_name
)
from app.services.taxonomy import TAXONOMY


@dataclass
class OrganizationStats:
    """Statistics about library organization coverage"""
    total_books: int = 0
    classified_books: int = 0
    unclassified_books: int = 0
    by_category: Dict[str, int] = None
    by_sub_genre: Dict[str, int] = None
    coverage_percent: float = 0.0
    
    def __post_init__(self):
        if self.by_category is None:
            self.by_category = {}
        if self.by_sub_genre is None:
            self.by_sub_genre = {}


@dataclass
class BatchClassificationResult:
    """Result of batch classification operation"""
    total_processed: int = 0
    newly_classified: int = 0
    already_classified: int = 0
    failed: int = 0
    results: Dict[int, ClassificationResult] = None
    # Map of file_path -> {category, sub_genre} for syncing to local storage
    file_classifications: Dict[str, Dict[str, Optional[str]]] = None
    
    def __post_init__(self):
        if self.results is None:
            self.results = {}
        if self.file_classifications is None:
            self.file_classifications = {}


def get_taxonomy_tree() -> Dict:
    """
    Get the full taxonomy tree structure for UI display.
    
    Returns:
        Dict with categories and their sub-genres
    """
    tree = {}
    for category, subgenres in TAXONOMY.items():
        tree[category] = [sg for sg in subgenres.keys()]
    return tree


def get_organization_stats(db: Session, source_path: Optional[str] = None) -> OrganizationStats:
    """
    Get statistics about library organization coverage.
    
    Args:
        db: Database session
        source_path: Optional path prefix to filter books
        
    Returns:
        OrganizationStats with classification coverage info
    """
    query = db.query(Ebook)
    
    if source_path:
        query = query.filter(Ebook.cloud_file_path.like(f"{source_path}%"))
    
    # Total books
    total = query.count()
    
    # Classified books (have both category and sub_genre)
    classified = query.filter(
        Ebook.category.isnot(None),
        Ebook.category != '',
        Ebook.sub_genre.isnot(None),
        Ebook.sub_genre != ''
    ).count()
    
    # Category breakdown
    category_counts = dict(
        db.query(Ebook.category, func.count(Ebook.id))
        .filter(Ebook.category.isnot(None), Ebook.category != '')
        .group_by(Ebook.category)
        .all()
    )
    
    # Sub-genre breakdown
    subgenre_counts = dict(
        db.query(Ebook.sub_genre, func.count(Ebook.id))
        .filter(Ebook.sub_genre.isnot(None), Ebook.sub_genre != '')
        .group_by(Ebook.sub_genre)
        .all()
    )
    
    return OrganizationStats(
        total_books=total,
        classified_books=classified,
        unclassified_books=total - classified,
        by_category=category_counts,
        by_sub_genre=subgenre_counts,
        coverage_percent=round((classified / total * 100) if total > 0 else 0, 1)
    )


def classify_single_ebook(
    db: Session,
    ebook_id: int,
    force_reclassify: bool = False
) -> Tuple[ClassificationResult, bool]:
    """
    Classify a single ebook using the taxonomy system.
    
    Args:
        db: Database session
        ebook_id: ID of ebook to classify
        force_reclassify: If True, reclassify even if already classified
        
    Returns:
        Tuple of (ClassificationResult, was_updated)
    """
    ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
    if not ebook:
        raise ValueError(f"Ebook with id {ebook_id} not found")
    
    # Check if already classified
    already_classified = (
        ebook.category and ebook.sub_genre and 
        ebook.category != '' and ebook.sub_genre != ''
    )
    
    if already_classified and not force_reclassify:
        return ClassificationResult(
            category=ebook.category,
            sub_genre=ebook.sub_genre,
            author=ebook.author,
            metadata_source="existing"
        ), False
    
    # Get file path for classification
    filepath = Path(ebook.cloud_file_path) if ebook.cloud_file_path else Path(ebook.title)
    
    # Extract embedded genre from existing metadata if available
    embedded_genre = ebook.sub_genre if ebook.sub_genre else None
    embedded_author = ebook.author
    
    # Run classification
    result = classify_book(
        filepath=filepath,
        embedded_genre=embedded_genre,
        embedded_author=embedded_author
    )
    
    # Update ebook with classification results
    was_updated = False
    
    if result.category:
        ebook.category = result.category
        was_updated = True
        
    if result.sub_genre:
        ebook.sub_genre = result.sub_genre
        was_updated = True
        
    # Update author if we found a better one
    if result.author and (not ebook.author or not is_valid_author(ebook.author)):
        ebook.author = result.author
        was_updated = True
    
    if was_updated:
        db.commit()
    
    return result, was_updated


def batch_classify_ebooks(
    db: Session,
    ebook_ids: Optional[List[int]] = None,
    source_path: Optional[str] = None,
    force_reclassify: bool = False,
    limit: int = 100,
    overrides: Optional[Dict[str, Dict[str, str]]] = None
) -> BatchClassificationResult:
    """
    Classify multiple ebooks in batch.
    
    Args:
        db: Database session
        ebook_ids: Specific ebook IDs to classify (if None, classifies unclassified books)
        source_path: Filter to specific source path
        force_reclassify: If True, reclassify even if already classified
        limit: Maximum number of books to process in one batch
        overrides: Manual overrides dictionary {ebook_id: {category, sub_genre}}
        
    Returns:
        BatchClassificationResult with counts and per-book results
    """
    result = BatchClassificationResult()
    overridden_ids = set()
    
    # 1. Apply overrides first
    if overrides:
        for str_id, data in overrides.items():
            try:
                ebook_id = int(str_id)
                ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
                if ebook:
                    old_cat = ebook.category
                    old_sub = ebook.sub_genre
                    
                    new_cat = data.get('category')
                    new_sub = data.get('sub_genre')
                    
                    # Update if changed
                    if ebook.category != new_cat or ebook.sub_genre != new_sub:
                        ebook.category = new_cat
                        ebook.sub_genre = new_sub
                        result.newly_classified += 1
                        was_updated = True
                    else:
                        result.already_classified += 1
                        was_updated = False
                        
                    result.total_processed += 1
                    overridden_ids.add(ebook_id)
                    
                    # Store file path -> classification mapping for local sync
                    if ebook.cloud_file_path:
                        result.file_classifications[ebook.cloud_file_path] = {
                            'category': ebook.category,
                            'sub_genre': ebook.sub_genre
                        }
                        
                    # Add result entry
                    result.results[ebook_id] = ClassificationResult(
                        category=ebook.category,
                        sub_genre=ebook.sub_genre,
                        author=ebook.author,
                        metadata_source="manual_override",
                        was_updated=was_updated
                    )
            except Exception:
                result.failed += 1
        
        # Commit manual changes
        db.commit()
    
    # 2. Proceed with AI classification for others
    if ebook_ids:
        # Classify specific ebooks
        query = db.query(Ebook).filter(Ebook.id.in_(ebook_ids))
        if overridden_ids:
             query = query.filter(Ebook.id.notin_(overridden_ids))
        ebooks = query.limit(limit).all()
    else:
        # Classify unclassified ebooks
        query = db.query(Ebook)
        
        if source_path:
            query = query.filter(Ebook.cloud_file_path.like(f"{source_path}%"))
        
        if not force_reclassify:
            # Only get unclassified books
            query = query.filter(
                (Ebook.category.is_(None)) | (Ebook.category == '') |
                (Ebook.sub_genre.is_(None)) | (Ebook.sub_genre == '')
            )
            
        # Exclude already overridden books (though unclassified filter might already catch them)
        if overridden_ids:
            query = query.filter(Ebook.id.notin_(overridden_ids))
        
        ebooks = query.limit(limit).all()
    
    for ebook in ebooks:
        try:
            classification, was_updated = classify_single_ebook(
                db, ebook.id, force_reclassify
            )
            result.results[ebook.id] = classification
            result.total_processed += 1
            
            # Store file path -> classification mapping for local sync
            if ebook.cloud_file_path:
                result.file_classifications[ebook.cloud_file_path] = {
                    'category': classification.category,
                    'sub_genre': classification.sub_genre
                }
            
            if was_updated:
                result.newly_classified += 1
            else:
                result.already_classified += 1
                
        except Exception as e:
            result.failed += 1
            result.results[ebook.id] = ClassificationResult(
                metadata_source=f"error: {str(e)}"
            )
    
    return result


def update_ebook_classification(
    db: Session,
    ebook_id: int,
    category: Optional[str] = None,
    sub_genre: Optional[str] = None
) -> Ebook:
    """
    Manually update an ebook's classification.
    
    Args:
        db: Database session
        ebook_id: ID of ebook to update
        category: Category to assign
        sub_genre: Sub-genre to assign
        
    Returns:
        Updated Ebook object
    """
    ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
    if not ebook:
        raise ValueError(f"Ebook with id {ebook_id} not found")
    
    # Validate category and sub_genre exist in taxonomy
    if category:
        if category not in TAXONOMY:
            raise ValueError(f"Invalid category: {category}. Valid options: {list(TAXONOMY.keys())}")
        ebook.category = category
        
    if sub_genre:
        # Find the category this sub_genre belongs to
        valid = False
        for cat, subgenres in TAXONOMY.items():
            if sub_genre in subgenres:
                valid = True
                # If category not specified, infer from sub_genre
                if not category:
                    ebook.category = cat
                break
        
        if not valid:
            raise ValueError(f"Invalid sub_genre: {sub_genre}")
        
        ebook.sub_genre = sub_genre
    
    db.commit()
    db.refresh(ebook)
    
    return ebook


def get_books_by_category(
    db: Session,
    category: Optional[str] = None,
    sub_genre: Optional[str] = None,
    source_path: Optional[str] = None,
    skip: int = 0,
    limit: int = 100
) -> List[Ebook]:
    """
    Get books filtered by category/sub_genre.
    
    Args:
        db: Database session
        category: Filter by category
        sub_genre: Filter by sub-genre
        source_path: Filter by source path prefix
        skip: Pagination offset
        limit: Max results
        
    Returns:
        List of matching Ebook objects
    """
    query = db.query(Ebook)
    
    if source_path:
        query = query.filter(Ebook.cloud_file_path.like(f"{source_path}%"))
    
    if category:
        query = query.filter(Ebook.category == category)
        
    if sub_genre:
        query = query.filter(Ebook.sub_genre == sub_genre)
    
    return query.offset(skip).limit(limit).all()


def preview_classification(
    db: Session,
    source_path: Optional[str] = None,
    limit: int = 100
) -> Dict:
    """
    Preview classification without applying changes.
    Returns a tree structure showing proposed organization.
    
    Args:
        db: Database session
        source_path: Filter to specific source path
        limit: Maximum number of books to preview
        
    Returns:
        Dict with tree structure showing Category -> SubGenre -> [books]
    """
    # Get unclassified ebooks
    query = db.query(Ebook)
    
    if source_path:
        query = query.filter(Ebook.cloud_file_path.like(f"{source_path}%"))
    
    # Only get unclassified books
    query = query.filter(
        (Ebook.category.is_(None)) | (Ebook.category == '') |
        (Ebook.sub_genre.is_(None)) | (Ebook.sub_genre == '')
    )
    
    ebooks = query.limit(limit).all()
    
    # Build proposed tree
    tree = {}
    books_preview = []
    
    for ebook in ebooks:
        filepath = Path(ebook.cloud_file_path) if ebook.cloud_file_path else Path(ebook.title)
        
        # Run classification (dry run - don't save)
        result = classify_book(
            filepath=filepath,
            embedded_genre=ebook.sub_genre if ebook.sub_genre else None,
            embedded_author=ebook.author
        )
        
        category = result.category or "_Uncategorized"
        sub_genre = result.sub_genre or "Other"
        
        # Build tree structure
        if category not in tree:
            tree[category] = {}
        if sub_genre not in tree[category]:
            tree[category][sub_genre] = []
        
        book_info = {
            "id": ebook.id,
            "title": ebook.title,
            "author": result.author or ebook.author or "Unknown",
            "source": result.metadata_source,
            "current_category": ebook.category,
            "current_subgenre": ebook.sub_genre,
            "proposed_category": category,
            "proposed_subgenre": sub_genre
        }
        
        tree[category][sub_genre].append(book_info)
        books_preview.append(book_info)
    
    # Calculate summary counts
    category_counts = {cat: sum(len(sgs) for sgs in subgenres.values()) 
                       for cat, subgenres in tree.items()}
    
    return {
        "total_to_classify": len(ebooks),
        "tree": tree,
        "category_counts": category_counts,
        "books": books_preview
    }

