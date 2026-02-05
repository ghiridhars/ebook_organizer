"""
Pytest fixtures and configuration for Ebook Organizer Backend tests
"""

import pytest
from typing import Generator, AsyncGenerator
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.pool import StaticPool

from app.main import app
from app.models.database import Base, get_db


# Create in-memory SQLite database for testing
SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"

test_engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)

TestingSessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=test_engine
)


@pytest.fixture(scope="function")
def db_session() -> Generator[Session, None, None]:
    """
    Create a fresh database session for each test.
    Tables are created before and dropped after each test.
    """
    # Create all tables
    Base.metadata.create_all(bind=test_engine)
    
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        # Drop all tables after test
        Base.metadata.drop_all(bind=test_engine)


@pytest.fixture(scope="function")
def client(db_session: Session) -> Generator[TestClient, None, None]:
    """
    Create a test client with overridden database dependency.
    """
    def override_get_db():
        try:
            yield db_session
        finally:
            pass
    
    app.dependency_overrides[get_db] = override_get_db
    
    with TestClient(app) as test_client:
        yield test_client
    
    app.dependency_overrides.clear()


# =============================================================================
# Sample Data Fixtures
# =============================================================================

@pytest.fixture
def sample_ebook_data() -> dict:
    """Sample ebook data for testing"""
    return {
        "title": "Test Book",
        "author": "Test Author",
        "description": "A test book description",
        "category": "Fiction",
        "genre": "Science Fiction",
        "format": "epub",
        "file_path": "/path/to/test.epub",
        "file_size": 1024000,
        "cover_image": None,
    }


@pytest.fixture
def sample_ebooks(sample_ebook_data: dict) -> list:
    """Multiple sample ebooks for testing"""
    return [
        {**sample_ebook_data, "title": f"Book {i}", "author": f"Author {i}"}
        for i in range(1, 6)
    ]


@pytest.fixture
def sample_metadata() -> dict:
    """Sample metadata for testing"""
    return {
        "title": "Foundation",
        "author": "Isaac Asimov",
        "description": "The first novel in the Foundation series",
        "publisher": "Gnome Press",
        "language": "en",
        "subjects": ["Science Fiction", "Space Opera"],
    }
