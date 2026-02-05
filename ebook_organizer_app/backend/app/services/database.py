"""Database service for SQLAlchemy session management"""

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from app.models.database import Base
from app.config import settings

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
    
    # Initialize FTS5 for full-text search
    try:
        from app.services.search_service import init_fts
        db = SessionLocal()
        init_fts(db)
        db.close()
    except Exception as e:
        # FTS init failure is non-fatal, fallback search will work
        print(f"FTS initialization note: {e}")

def get_db():
    """Dependency for FastAPI to get database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

