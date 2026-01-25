"""Database models for Ebook Organizer"""

from sqlalchemy import Column, Integer, String, DateTime, Boolean, ForeignKey, Text, Float
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime

Base = declarative_base()

class Ebook(Base):
    """Ebook model representing individual books"""
    __tablename__ = "ebooks"
    
    id = Column(Integer, primary_key=True, index=True)
    
    # Cloud Storage Info
    cloud_provider = Column(String(50), nullable=False)  # google_drive, onedrive
    cloud_file_id = Column(String(255), unique=True, nullable=False, index=True)
    cloud_file_path = Column(String(500))
    
    # Metadata
    title = Column(String(500), nullable=False, index=True)
    author = Column(String(500), index=True)
    isbn = Column(String(20), index=True)
    publisher = Column(String(255))
    published_date = Column(String(50))
    description = Column(Text)
    language = Column(String(10))
    page_count = Column(Integer)
    
    # Organization
    category = Column(String(100), index=True)  # Fiction, Non-Fiction, etc.
    sub_genre = Column(String(100), index=True)  # Science Fiction, Biography, etc.
    
    # File Info
    file_format = Column(String(10), index=True)  # epub, pdf, mobi
    file_size = Column(Integer)  # bytes
    file_hash = Column(String(64))  # SHA-256 for deduplication
    
    # Sync State
    last_synced = Column(DateTime, default=datetime.utcnow)
    is_synced = Column(Boolean, default=True)
    sync_status = Column(String(50), default="synced")  # synced, pending, error
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # User Tags
    tags = relationship("Tag", back_populates="ebook", cascade="all, delete-orphan")
    
    def __repr__(self):
        return f"<Ebook(title='{self.title}', author='{self.author}')>"


class Tag(Base):
    """Custom tags for ebooks"""
    __tablename__ = "tags"
    
    id = Column(Integer, primary_key=True, index=True)
    ebook_id = Column(Integer, ForeignKey("ebooks.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(100), nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    ebook = relationship("Ebook", back_populates="tags")
    
    def __repr__(self):
        return f"<Tag(name='{self.name}')>"


class SyncLog(Base):
    """Log of synchronization operations"""
    __tablename__ = "sync_logs"
    
    id = Column(Integer, primary_key=True, index=True)
    cloud_provider = Column(String(50), nullable=False)
    operation = Column(String(50))  # full_sync, incremental, metadata_update
    status = Column(String(50))  # success, partial, failed
    books_processed = Column(Integer, default=0)
    books_added = Column(Integer, default=0)
    books_updated = Column(Integer, default=0)
    books_failed = Column(Integer, default=0)
    error_message = Column(Text)
    started_at = Column(DateTime, default=datetime.utcnow)
    completed_at = Column(DateTime)
    duration_seconds = Column(Float)
    
    def __repr__(self):
        return f"<SyncLog(provider='{self.cloud_provider}', status='{self.status}')>"


class CloudConfig(Base):
    """Cloud storage configuration and credentials"""
    __tablename__ = "cloud_configs"
    
    id = Column(Integer, primary_key=True, index=True)
    provider = Column(String(50), unique=True, nullable=False)  # google_drive, onedrive
    is_enabled = Column(Boolean, default=False)
    is_authenticated = Column(Boolean, default=False)
    credentials_encrypted = Column(Text)  # Encrypted JSON credentials
    folder_path = Column(String(500))  # Cloud folder to monitor
    last_sync = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    def __repr__(self):
        return f"<CloudConfig(provider='{self.provider}', enabled={self.is_enabled})>"
