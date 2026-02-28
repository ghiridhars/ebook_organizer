"""
Simple in-memory rate limiter middleware.

Uses a sliding-window counter per client IP.  When the rate is exceeded the
client receives a 429 response with a ``Retry-After`` header.
"""

import time
from collections import defaultdict
from typing import Callable, Dict, List

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from app.config import settings
from app.logging_config import logger


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Sliding-window rate limiter keyed by client IP."""

    def __init__(self, app, max_requests: int | None = None, window_seconds: int = 60):
        super().__init__(app)
        self.max_requests = max_requests or settings.RATE_LIMIT_PER_MINUTE
        self.window = window_seconds
        # ip -> list of request timestamps
        self._hits: Dict[str, List[float]] = defaultdict(list)

    def _prune(self, ip: str, now: float) -> None:
        """Remove timestamps outside the current window."""
        cutoff = now - self.window
        self._hits[ip] = [t for t in self._hits[ip] if t > cutoff]

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Skip rate limiting for health / docs endpoints
        if request.url.path in ("/", "/health", "/docs", "/redoc", "/openapi.json"):
            return await call_next(request)

        client_ip = request.client.host if request.client else "unknown"
        now = time.time()
        self._prune(client_ip, now)

        if len(self._hits[client_ip]) >= self.max_requests:
            retry_after = int(self.window - (now - self._hits[client_ip][0])) + 1
            logger.warning(
                f"Rate limit exceeded for {client_ip} "
                f"({len(self._hits[client_ip])}/{self.max_requests} in {self.window}s)"
            )
            return JSONResponse(
                status_code=429,
                content={
                    "success": False,
                    "error": {
                        "code": 429,
                        "message": "Too many requests. Please slow down.",
                    },
                },
                headers={"Retry-After": str(retry_after)},
            )

        self._hits[client_ip].append(now)
        return await call_next(request)
