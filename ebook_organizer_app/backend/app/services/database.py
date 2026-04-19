"""Database service for SQLAlchemy session management"""

import logging
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from app.models.database import Base
from app.config import settings

logger = logging.getLogger(__name__)

# Create database engine
engine = create_engine(
    settings.DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in settings.DATABASE_URL else {}
)

# Create session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def init_db():
    """Initialize database tables and FTS index"""
    Base.metadata.create_all(bind=engine)

    # Auto-migrate: add missing columns to existing tables
    _run_schema_migrations()
    
    # Initialize FTS5 for full-text search
    try:
        from app.services.search_service import init_fts
        db = SessionLocal()
        init_fts(db)
        db.close()
    except Exception as e:
        # FTS init failure is non-fatal, fallback search will work
        logger.info(f"FTS initialization note: {e}")


def _run_schema_migrations():
    """Add any columns that exist in models but not yet in the DB."""
    import sqlite3
    conn = engine.raw_connection()
    cursor = conn.cursor()
    try:
        # Get existing columns for 'ebooks' table
        cursor.execute("PRAGMA table_info(ebooks)")
        existing = {row[1] for row in cursor.fetchall()}

        migrations = [
            ("cloud_modified_time", "DATETIME"),
        ]
        for col, col_type in migrations:
            if col not in existing:
                cursor.execute(f"ALTER TABLE ebooks ADD COLUMN {col} {col_type}")
                logger.info(f"Migration: added column ebooks.{col}")
        conn.commit()
    except Exception as e:
        logger.warning(f"Schema migration note: {e}")
    finally:
        cursor.close()
        conn.close()

def get_db():
    """Dependency for FastAPI to get database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

