"""
Middleware for request/response logging and error handling

Provides:
- Request ID tracking
- Request/response timing
- Structured logging
- Global exception handling
"""

import time
import uuid
from typing import Callable
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response, JSONResponse
from fastapi import HTTPException
from pydantic import ValidationError

from app.logging_config import logger


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Middleware that logs all requests with timing information"""
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Generate unique request ID
        request_id = str(uuid.uuid4())[:8]
        request.state.request_id = request_id
        
        # Record start time
        start_time = time.perf_counter()
        
        # Get client IP
        client_ip = request.client.host if request.client else "unknown"
        
        # Process request
        try:
            response = await call_next(request)
            
            # Calculate duration
            duration_ms = (time.perf_counter() - start_time) * 1000
            
            # Log request completion
            logger.info(
                f"{request.method} {request.url.path}",
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_ms": duration_ms,
                    "client_ip": client_ip,
                }
            )
            
            # Add request ID to response headers
            response.headers["X-Request-ID"] = request_id
            
            return response
            
        except Exception as e:
            # Calculate duration even on error
            duration_ms = (time.perf_counter() - start_time) * 1000
            
            # Log error
            logger.error(
                f"Request failed: {str(e)}",
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "duration_ms": duration_ms,
                    "client_ip": client_ip,
                },
                exc_info=True
            )
            
            # Re-raise to let exception handlers deal with it
            raise


async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
    """Handle HTTP exceptions with structured response"""
    request_id = getattr(request.state, "request_id", "unknown")
    
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "success": False,
            "error": {
                "code": exc.status_code,
                "message": exc.detail,
                "request_id": request_id,
            }
        },
        headers={"X-Request-ID": request_id}
    )


async def validation_exception_handler(request: Request, exc: ValidationError) -> JSONResponse:
    """Handle Pydantic validation errors with detailed response"""
    request_id = getattr(request.state, "request_id", "unknown")
    
    errors = []
    for error in exc.errors():
        errors.append({
            "field": ".".join(str(loc) for loc in error["loc"]),
            "message": error["msg"],
            "type": error["type"]
        })
    
    logger.warning(
        f"Validation error: {len(errors)} field(s) invalid",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
        }
    )
    
    return JSONResponse(
        status_code=422,
        content={
            "success": False,
            "error": {
                "code": 422,
                "message": "Validation failed",
                "details": errors,
                "request_id": request_id,
            }
        },
        headers={"X-Request-ID": request_id}
    )


async def generic_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Handle unexpected exceptions with safe error response"""
    request_id = getattr(request.state, "request_id", "unknown")
    
    # Log the full exception
    logger.error(
        f"Unhandled exception: {type(exc).__name__}: {str(exc)}",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
        },
        exc_info=True
    )
    
    # Return safe error response (don't expose internal details in production)
    from app.config import settings
    
    error_message = str(exc) if settings.DEBUG else "An internal error occurred"
    
    return JSONResponse(
        status_code=500,
        content={
            "success": False,
            "error": {
                "code": 500,
                "message": error_message,
                "request_id": request_id,
            }
        },
        headers={"X-Request-ID": request_id}
    )
