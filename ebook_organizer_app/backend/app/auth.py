"""
Authentication & authorization for Ebook Organizer API.

Provides optional API-key authentication suitable for a local desktop app.
When API_KEY is set in the environment / .env file, every request must include
the header ``X-API-Key: <key>``.  When API_KEY is empty (default), auth is
bypassed so development / testing stays frictionless.
"""

from fastapi import Depends, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from typing import Optional

from app.config import settings
from app.logging_config import logger

# Header-based API key scheme.  auto_error=False so we can provide a
# friendlier message when the key is missing.
_api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


async def verify_api_key(
    api_key: Optional[str] = Security(_api_key_header),
) -> Optional[str]:
    """FastAPI dependency that validates the API key.

    * If ``settings.API_KEY`` is empty the check is skipped (open access).
    * If set, the request must carry a matching ``X-API-Key`` header.

    Returns the validated key (or *None* when auth is disabled).
    """
    expected = settings.API_KEY

    # Auth disabled – allow everything
    if not expected:
        return None

    if not api_key:
        logger.warning("Request missing API key")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing API key. Provide it via the X-API-Key header.",
        )

    if api_key != expected:
        logger.warning("Invalid API key presented")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid API key.",
        )

    return api_key
