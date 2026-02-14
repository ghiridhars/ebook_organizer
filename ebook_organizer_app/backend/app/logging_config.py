"""
Logging Configuration for Ebook Organizer Backend

Provides structured JSON logging with separate console and file handlers.
"""

import logging
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict
from logging.handlers import RotatingFileHandler

from app.config import settings


class JSONFormatter(logging.Formatter):
    """Custom formatter that outputs JSON structured logs"""
    
    def format(self, record: logging.LogRecord) -> str:
        log_data: Dict[str, Any] = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        
        # Add extra fields if present
        if hasattr(record, "request_id"):
            log_data["request_id"] = record.request_id
        if hasattr(record, "method"):
            log_data["method"] = record.method
        if hasattr(record, "path"):
            log_data["path"] = record.path
        if hasattr(record, "status_code"):
            log_data["status_code"] = record.status_code
        if hasattr(record, "duration_ms"):
            log_data["duration_ms"] = record.duration_ms
        if hasattr(record, "client_ip"):
            log_data["client_ip"] = record.client_ip
        
        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)
        
        return json.dumps(log_data)


class ConsoleFormatter(logging.Formatter):
    """Human-readable console formatter with colors"""
    
    COLORS = {
        "DEBUG": "\033[36m",    # Cyan
        "INFO": "\033[32m",     # Green
        "WARNING": "\033[33m",  # Yellow
        "ERROR": "\033[31m",    # Red
        "CRITICAL": "\033[35m", # Magenta
    }
    RESET = "\033[0m"
    
    def format(self, record: logging.LogRecord) -> str:
        color = self.COLORS.get(record.levelname, self.RESET)
        timestamp = datetime.now().strftime("%H:%M:%S")
        
        # Build base message
        msg = f"{color}[{timestamp}] {record.levelname:8}{self.RESET} {record.getMessage()}"
        
        # Add request details if present
        if hasattr(record, "method") and hasattr(record, "path"):
            msg = f"{color}[{timestamp}] {record.levelname:8}{self.RESET} {record.method} {record.path}"
            if hasattr(record, "status_code"):
                msg += f" -> {record.status_code}"
            if hasattr(record, "duration_ms"):
                msg += f" ({record.duration_ms:.1f}ms)"
        
        return msg


def setup_logging() -> logging.Logger:
    """Configure application logging with console and file handlers"""
    
    # Create logs directory if needed
    log_dir = settings.BASE_DIR / "logs"
    log_dir.mkdir(exist_ok=True)
    
    # Get root logger for app
    logger = logging.getLogger("app")
    logger.setLevel(logging.DEBUG if settings.DEBUG else logging.INFO)
    
    # Clear existing handlers
    logger.handlers.clear()
    
    # Console handler - human readable
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.DEBUG if settings.DEBUG else logging.INFO)
    console_handler.setFormatter(ConsoleFormatter())
    logger.addHandler(console_handler)
    
    # File handler - JSON structured (for production parsing)
    file_handler = RotatingFileHandler(
        log_dir / "app.log",
        maxBytes=10 * 1024 * 1024,  # 10 MB
        backupCount=5,
        encoding="utf-8"
    )
    file_handler.setLevel(logging.INFO)
    file_handler.setFormatter(JSONFormatter())
    logger.addHandler(file_handler)
    
    # Error file handler - separate file for errors only
    error_handler = RotatingFileHandler(
        log_dir / "error.log",
        maxBytes=10 * 1024 * 1024,  # 10 MB
        backupCount=5,
        encoding="utf-8"
    )
    error_handler.setLevel(logging.ERROR)
    error_handler.setFormatter(JSONFormatter())
    logger.addHandler(error_handler)
    
    return logger


# Create configured logger instance
logger = setup_logging()
