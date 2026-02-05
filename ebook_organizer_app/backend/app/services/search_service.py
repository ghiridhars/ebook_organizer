"""
Full-Text Search Service using SQLite FTS5

Provides high-performance full-text search capabilities for ebooks.
"""

from typing import List, Optional, Tuple
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models.database import Ebook
from app.logging_config import logger


# SQL to create FTS5 virtual table
FTS_TABLE_CREATE = """
CREATE VIRTUAL TABLE IF NOT EXISTS ebooks_fts USING fts5(
    title,
    author,
    description,
    category,
    sub_genre,
    content='ebooks',
    content_rowid='id',
    tokenize='porter unicode61'
);
"""

# Triggers to keep FTS in sync with ebooks table
FTS_TRIGGERS = [
    """
    CREATE TRIGGER IF NOT EXISTS ebooks_ai AFTER INSERT ON ebooks BEGIN
        INSERT INTO ebooks_fts(rowid, title, author, description, category, sub_genre)
        VALUES (new.id, new.title, new.author, new.description, new.category, new.sub_genre);
    END;
    """,
    """
    CREATE TRIGGER IF NOT EXISTS ebooks_ad AFTER DELETE ON ebooks BEGIN
        INSERT INTO ebooks_fts(ebooks_fts, rowid, title, author, description, category, sub_genre)
        VALUES ('delete', old.id, old.title, old.author, old.description, old.category, old.sub_genre);
    END;
    """,
    """
    CREATE TRIGGER IF NOT EXISTS ebooks_au AFTER UPDATE ON ebooks BEGIN
        INSERT INTO ebooks_fts(ebooks_fts, rowid, title, author, description, category, sub_genre)
        VALUES ('delete', old.id, old.title, old.author, old.description, old.category, old.sub_genre);
        INSERT INTO ebooks_fts(rowid, title, author, description, category, sub_genre)
        VALUES (new.id, new.title, new.author, new.description, new.category, new.sub_genre);
    END;
    """
]


def init_fts(db: Session) -> None:
    """Initialize FTS5 virtual table and triggers"""
    try:
        # Create FTS table
        db.execute(text(FTS_TABLE_CREATE))
        
        # Create sync triggers
        for trigger_sql in FTS_TRIGGERS:
            db.execute(text(trigger_sql))
        
        db.commit()
        logger.info("FTS5 search initialized successfully")
    except Exception as e:
        logger.warning(f"FTS5 initialization warning: {e}")
        # FTS might already exist, which is fine
        db.rollback()


def rebuild_fts_index(db: Session) -> int:
    """Rebuild FTS index from all ebooks (useful after data import)"""
    try:
        # Clear existing FTS data
        db.execute(text("DELETE FROM ebooks_fts;"))
        
        # Rebuild from ebooks table
        db.execute(text("""
            INSERT INTO ebooks_fts(rowid, title, author, description, category, sub_genre)
            SELECT id, title, author, description, category, sub_genre FROM ebooks;
        """))
        
        # Get count
        result = db.execute(text("SELECT COUNT(*) FROM ebooks_fts;"))
        count = result.scalar()
        
        db.commit()
        logger.info(f"FTS index rebuilt with {count} documents")
        return count
    except Exception as e:
        logger.error(f"FTS rebuild failed: {e}")
        db.rollback()
        raise


class SearchResult:
    """Search result with relevance score"""
    def __init__(self, ebook: Ebook, score: float, snippet: Optional[str] = None):
        self.ebook = ebook
        self.score = score
        self.snippet = snippet


def search_ebooks(
    db: Session,
    query: str,
    category: Optional[str] = None,
    format: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
) -> Tuple[List[SearchResult], int]:
    """
    Search ebooks using FTS5 with optional filters.
    
    Args:
        db: Database session
        query: Search query (supports FTS5 syntax)
        category: Optional category filter
        format: Optional format filter
        limit: Maximum results to return
        offset: Results offset for pagination
    
    Returns:
        Tuple of (search results, total count)
    """
    if not query or not query.strip():
        logger.warning("Empty search query provided")
        return [], 0
    
    # Sanitize query for FTS5 (escape special characters)
    safe_query = query.replace('"', '""').strip()
    
    try:
        # Build the search query
        # Using MATCH for FTS5 with BM25 ranking
        base_sql = """
            SELECT e.*, bm25(ebooks_fts) AS score,
                   snippet(ebooks_fts, 2, '<mark>', '</mark>', '...', 32) AS snippet
            FROM ebooks_fts
            JOIN ebooks e ON ebooks_fts.rowid = e.id
            WHERE ebooks_fts MATCH :query
        """
        
        count_sql = """
            SELECT COUNT(*)
            FROM ebooks_fts
            JOIN ebooks e ON ebooks_fts.rowid = e.id
            WHERE ebooks_fts MATCH :query
        """
        
        params = {"query": safe_query}
        
        # Add filters
        filters = []
        if category:
            filters.append("e.category = :category")
            params["category"] = category
        if format:
            filters.append("e.file_format = :format")
            params["format"] = format
        
        if filters:
            filter_clause = " AND " + " AND ".join(filters)
            base_sql += filter_clause
            count_sql += filter_clause
        
        # Add ordering and pagination
        base_sql += " ORDER BY score LIMIT :limit OFFSET :offset"
        params["limit"] = limit
        params["offset"] = offset
        
        # Execute search
        results = db.execute(text(base_sql), params).fetchall()
        
        # Get total count
        total = db.execute(text(count_sql), {k: v for k, v in params.items() if k not in ['limit', 'offset']}).scalar()
        
        # Convert to SearchResult objects
        search_results = []
        for row in results:
            ebook = db.query(Ebook).filter(Ebook.id == row.id).first()
            if ebook:
                search_results.append(SearchResult(
                    ebook=ebook,
                    score=abs(row.score),  # BM25 returns negative scores
                    snippet=row.snippet
                ))
        
        logger.info(f"Search for '{query}' returned {len(search_results)} results (total: {total})")
        return search_results, total or 0
        
    except Exception as e:
        logger.error(f"Search failed: {e}")
        # Fall back to LIKE search if FTS fails
        return _fallback_search(db, query, category, format, limit, offset)


def _fallback_search(
    db: Session,
    query: str,
    category: Optional[str] = None,
    format: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
) -> Tuple[List[SearchResult], int]:
    """Fallback search using LIKE when FTS is unavailable"""
    logger.warning("Using fallback LIKE search")
    
    search_pattern = f"%{query}%"
    
    db_query = db.query(Ebook).filter(
        (Ebook.title.ilike(search_pattern)) |
        (Ebook.author.ilike(search_pattern)) |
        (Ebook.description.ilike(search_pattern))
    )
    
    if category:
        db_query = db_query.filter(Ebook.category == category)
    if format:
        db_query = db_query.filter(Ebook.file_format == format)
    
    total = db_query.count()
    results = db_query.offset(offset).limit(limit).all()
    
    return [SearchResult(ebook=e, score=1.0) for e in results], total


def get_search_suggestions(db: Session, prefix: str, limit: int = 5) -> List[str]:
    """Get search suggestions based on existing titles and authors"""
    if not prefix or len(prefix) < 2:
        return []
    
    pattern = f"{prefix}%"
    
    # Get title suggestions
    titles = db.query(Ebook.title).filter(
        Ebook.title.ilike(pattern)
    ).distinct().limit(limit).all()
    
    # Get author suggestions
    authors = db.query(Ebook.author).filter(
        Ebook.author.ilike(pattern)
    ).distinct().limit(limit).all()
    
    suggestions = list(set([t[0] for t in titles] + [a[0] for a in authors if a[0]]))
    return sorted(suggestions)[:limit]
