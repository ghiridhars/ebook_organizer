"""Pydantic models for API request/response validation"""

from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime

class EbookBase(BaseModel):
    """Base Ebook schema"""
    title: str = Field(..., min_length=1, max_length=500)
    author: Optional[str] = Field(None, max_length=500)
    isbn: Optional[str] = Field(None, max_length=20)
    publisher: Optional[str] = Field(None, max_length=255)
    published_date: Optional[str] = None
    description: Optional[str] = None
    language: Optional[str] = Field(None, max_length=10)
    page_count: Optional[int] = None
    category: Optional[str] = Field(None, max_length=100)
    sub_genre: Optional[str] = Field(None, max_length=100)
    file_format: str = Field(..., max_length=10)
    file_size: Optional[int] = None

class EbookCreate(EbookBase):
    """Schema for creating a new ebook"""
    cloud_provider: str = Field(..., max_length=50)
    cloud_file_id: str = Field(..., max_length=255)
    cloud_file_path: Optional[str] = Field(None, max_length=500)

class EbookUpdate(BaseModel):
    """Schema for updating ebook metadata"""
    title: Optional[str] = Field(None, max_length=500)
    author: Optional[str] = Field(None, max_length=500)
    category: Optional[str] = Field(None, max_length=100)
    sub_genre: Optional[str] = Field(None, max_length=100)
    description: Optional[str] = None
    tags: Optional[List[str]] = None

class EbookResponse(EbookBase):
    """Schema for ebook response"""
    id: int
    cloud_provider: str
    cloud_file_id: str
    cloud_file_path: Optional[str] = None
    file_hash: Optional[str] = None
    last_synced: datetime
    is_synced: bool
    sync_status: str
    created_at: datetime
    updated_at: datetime
    tags: List[str] = []
    
    class Config:
        from_attributes = True

class TagCreate(BaseModel):
    """Schema for creating a tag"""
    name: str = Field(..., min_length=1, max_length=100)

class TagResponse(BaseModel):
    """Schema for tag response"""
    id: int
    name: str
    created_at: datetime
    
    class Config:
        from_attributes = True

class CloudProviderStatus(BaseModel):
    """Cloud provider connection status"""
    provider: str
    is_enabled: bool
    is_authenticated: bool
    last_sync: Optional[datetime] = None
    folder_path: Optional[str] = None

class SyncRequest(BaseModel):
    """Schema for sync request"""
    provider: Optional[str] = None  # If None, sync all enabled providers
    full_sync: bool = False  # If True, perform full sync instead of incremental

class SyncResponse(BaseModel):
    """Schema for sync response"""
    status: str
    provider: str
    books_processed: int
    books_added: int
    books_updated: int
    books_failed: int
    duration_seconds: float
    error_message: Optional[str] = None

class LibraryStats(BaseModel):
    """Library statistics"""
    total_books: int
    by_category: dict
    by_format: dict
    by_cloud_provider: dict
    total_size_mb: float
    last_sync: Optional[datetime] = None
