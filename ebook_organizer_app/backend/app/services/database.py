"""Database service for SQLAlchemy session management"""

import logging
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, Session
from app.models.database import Base
from app.config import settings

logger = logging.getLogger(__name__)

# Create database engine
engine = create_engine(
    settings.DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in settings.DATABASE_URL else {}
)


@event.listens_for(engine, "connect")
def set_sqlite_pragmas(dbapi_connection, connection_record):
    """
    Set SQLite performance pragmas on every new connection.
    Tuned for Raspberry Pi 5 (8GB) with 100k+ ebook library.
    """
    if "sqlite" not in settings.DATABASE_URL:
        return

    cursor = dbapi_connection.cursor()
    # WAL mode: allows concurrent reads during writes
    # Critical for watchdog writing new books while web UI reads
    cursor.execute("PRAGMA journal_mode=WAL")
    # NORMAL sync: safe with WAL, ~2x faster than FULL
    cursor.execute("PRAGMA synchronous=NORMAL")
    # 64MB page cache (negative = KB, so -65536 = 64MB)
    # 100k book index ≈ 20MB, so this keeps hot pages in memory
    cursor.execute("PRAGMA cache_size=-65536")
    # 256MB memory-mapped I/O for fast reads
    # Pi 5 8GB has plenty of RAM; bypasses read() syscalls
    cursor.execute("PRAGMA mmap_size=268435456")
    # Enable foreign keys (not enabled by default in SQLite)
    cursor.execute("PRAGMA foreign_keys=ON")
    # Temp tables in memory (faster than disk on Pi with NVMe)
    cursor.execute("PRAGMA temp_store=MEMORY")
    cursor.close()


# Create session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def init_db():
    """Initialize database tables and FTS index"""
    Base.metadata.create_all(bind=engine)
    
    # Initialize FTS5 for full-text search
    try:
        from app.services.search_service import init_fts
        db = SessionLocal()
        init_fts(db)
        db.close()
    except Exception as e:
        # FTS init failure is non-fatal, fallback search will work
        logger.info(f"FTS initialization note: {e}")

def get_db():
    """Dependency for FastAPI to get database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
