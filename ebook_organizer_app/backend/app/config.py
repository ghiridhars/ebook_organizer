"""Configuration management for Ebook Organizer Backend"""

from pydantic_settings import BaseSettings, SettingsConfigDict
from pathlib import Path

class Settings(BaseSettings):
    """Application settings"""
    
    # API Configuration
    API_HOST: str = "127.0.0.1"
    API_PORT: int = 8000
    DEBUG: bool = True
    
    # Database
    DATABASE_URL: str = "sqlite:///./ebook_organizer.db"
    
    # Cloud Storage
    GOOGLE_DRIVE_CREDENTIALS_FILE: str = "credentials_google.json"
    GOOGLE_DRIVE_TOKEN_FILE: str = "token_google.json"
    ONEDRIVE_CLIENT_ID: str = ""
    ONEDRIVE_CLIENT_SECRET: str = ""
    ONEDRIVE_TOKEN_FILE: str = "token_onedrive.json"
    
    # Security
    SECRET_KEY: str = "your-secret-key-change-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    
    # File Processing
    MAX_FILE_SIZE_MB: int = 100
    SUPPORTED_FORMATS: list = ["epub", "pdf", "mobi", "azw", "azw3", "fb2"]
    
    # Paths
    BASE_DIR: Path = Path(__file__).resolve().parent.parent
    CACHE_DIR: Path = BASE_DIR / "cache"
    TEMP_DIR: Path = BASE_DIR / "temp"
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True
    )

settings = Settings()
