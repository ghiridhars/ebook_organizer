"""
Cloud provider abstraction layer.

Defines the interface every cloud storage back-end must implement,
plus concrete scaffolds for Google Drive and OneDrive using OAuth 2.0.
"""

from __future__ import annotations

import json
import logging
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Dict, List, Optional

from app.config import settings

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Data-transfer objects
# ---------------------------------------------------------------------------

class CloudFile:
    """Lightweight representation of a file in a cloud provider."""

    def __init__(
        self,
        file_id: str,
        name: str,
        path: str,
        mime_type: str,
        size: int,
        modified_at: Optional[datetime] = None,
    ):
        self.file_id = file_id
        self.name = name
        self.path = path
        self.mime_type = mime_type
        self.size = size
        self.modified_at = modified_at

    def __repr__(self) -> str:
        return f"<CloudFile({self.name!r}, {self.size} bytes)>"


# ---------------------------------------------------------------------------
# Abstract base class
# ---------------------------------------------------------------------------

class CloudProviderBase(ABC):
    """Interface that every cloud provider adapter must implement."""

    provider_name: str = ""

    @abstractmethod
    def get_auth_url(self) -> str:
        """Return the OAuth 2.0 authorization URL the user should visit."""
        ...

    @abstractmethod
    async def handle_callback(self, code: str) -> Dict:
        """Exchange the authorization code for tokens.  Return token dict."""
        ...

    @abstractmethod
    async def refresh_token(self, refresh_token: str) -> Dict:
        """Use a refresh token to obtain new access credentials."""
        ...

    @abstractmethod
    async def list_files(
        self,
        folder_path: Optional[str] = None,
        file_types: Optional[List[str]] = None,
    ) -> List[CloudFile]:
        """List ebook files in the user's cloud storage."""
        ...

    @abstractmethod
    async def download_file(self, file_id: str, dest_path: str) -> str:
        """Download a file to *dest_path* and return the local path."""
        ...

    @abstractmethod
    async def upload_file(self, local_path: str, cloud_folder: str) -> CloudFile:
        """Upload a local file to the cloud folder."""
        ...


# ---------------------------------------------------------------------------
# Google Drive scaffold
# ---------------------------------------------------------------------------

_GOOGLE_SCOPES = "https://www.googleapis.com/auth/drive.readonly"
_GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
_GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"


class GoogleDriveProvider(CloudProviderBase):
    """Google Drive adapter (OAuth 2.0, Desktop / OOB flow)."""

    provider_name = "google_drive"

    def __init__(self) -> None:
        self._credentials: Optional[Dict] = None
        self._load_client_credentials()

    # -- internal helpers ------------------------------------------------

    def _load_client_credentials(self) -> None:
        """Load the Google OAuth client-id / secret from the credentials file."""
        import os

        path = settings.GOOGLE_DRIVE_CREDENTIALS_FILE
        if os.path.exists(path):
            try:
                with open(path) as f:
                    raw = json.load(f)
                # Handles both *web* and *installed* credential shapes
                key = "web" if "web" in raw else "installed"
                self._credentials = raw.get(key, {})
            except Exception as exc:
                logger.warning(f"Could not parse Google credentials file: {exc}")

    @property
    def _client_id(self) -> str:
        return (self._credentials or {}).get("client_id", "")

    @property
    def _client_secret(self) -> str:
        return (self._credentials or {}).get("client_secret", "")

    @property
    def _redirect_uri(self) -> str:
        uris = (self._credentials or {}).get("redirect_uris", [])
        return uris[0] if uris else "http://localhost:8000/api/cloud/google/callback"

    # -- public API ------------------------------------------------------

    def get_auth_url(self) -> str:
        if not self._client_id:
            raise RuntimeError(
                "Google OAuth credentials not configured. "
                "Place a credentials JSON file at "
                f"'{settings.GOOGLE_DRIVE_CREDENTIALS_FILE}'."
            )
        from urllib.parse import urlencode

        params = {
            "client_id": self._client_id,
            "redirect_uri": self._redirect_uri,
            "response_type": "code",
            "scope": _GOOGLE_SCOPES,
            "access_type": "offline",
            "prompt": "consent",
        }
        return f"{_GOOGLE_AUTH_URL}?{urlencode(params)}"

    async def handle_callback(self, code: str) -> Dict:
        import httpx

        async with httpx.AsyncClient() as client:
            resp = await client.post(
                _GOOGLE_TOKEN_URL,
                data={
                    "code": code,
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                    "redirect_uri": self._redirect_uri,
                    "grant_type": "authorization_code",
                },
            )
            resp.raise_for_status()
            return resp.json()

    async def refresh_token(self, refresh_token: str) -> Dict:
        import httpx

        async with httpx.AsyncClient() as client:
            resp = await client.post(
                _GOOGLE_TOKEN_URL,
                data={
                    "refresh_token": refresh_token,
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                    "grant_type": "refresh_token",
                },
            )
            resp.raise_for_status()
            return resp.json()

    async def list_files(
        self,
        folder_path: Optional[str] = None,
        file_types: Optional[List[str]] = None,
    ) -> List[CloudFile]:
        # TODO: implement paging through Drive API v3 /files endpoint
        logger.info("GoogleDriveProvider.list_files is not yet fully implemented")
        return []

    async def download_file(self, file_id: str, dest_path: str) -> str:
        logger.info("GoogleDriveProvider.download_file is not yet fully implemented")
        return dest_path

    async def upload_file(self, local_path: str, cloud_folder: str) -> CloudFile:
        raise NotImplementedError("Upload to Google Drive is not yet implemented")


# ---------------------------------------------------------------------------
# OneDrive scaffold
# ---------------------------------------------------------------------------

_MS_AUTH_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
_MS_TOKEN_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
_MS_SCOPES = "Files.Read Files.Read.All offline_access"


class OneDriveProvider(CloudProviderBase):
    """Microsoft OneDrive adapter (OAuth 2.0)."""

    provider_name = "onedrive"

    @property
    def _client_id(self) -> str:
        return settings.ONEDRIVE_CLIENT_ID

    @property
    def _client_secret(self) -> str:
        return settings.ONEDRIVE_CLIENT_SECRET

    @property
    def _redirect_uri(self) -> str:
        return "http://localhost:8000/api/cloud/onedrive/callback"

    def get_auth_url(self) -> str:
        if not self._client_id:
            raise RuntimeError(
                "OneDrive OAuth credentials not configured. "
                "Set ONEDRIVE_CLIENT_ID and ONEDRIVE_CLIENT_SECRET."
            )
        from urllib.parse import urlencode

        params = {
            "client_id": self._client_id,
            "redirect_uri": self._redirect_uri,
            "response_type": "code",
            "scope": _MS_SCOPES,
        }
        return f"{_MS_AUTH_URL}?{urlencode(params)}"

    async def handle_callback(self, code: str) -> Dict:
        import httpx

        async with httpx.AsyncClient() as client:
            resp = await client.post(
                _MS_TOKEN_URL,
                data={
                    "code": code,
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                    "redirect_uri": self._redirect_uri,
                    "grant_type": "authorization_code",
                },
            )
            resp.raise_for_status()
            return resp.json()

    async def refresh_token(self, refresh_token: str) -> Dict:
        import httpx

        async with httpx.AsyncClient() as client:
            resp = await client.post(
                _MS_TOKEN_URL,
                data={
                    "refresh_token": refresh_token,
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                    "grant_type": "refresh_token",
                },
            )
            resp.raise_for_status()
            return resp.json()

    async def list_files(
        self,
        folder_path: Optional[str] = None,
        file_types: Optional[List[str]] = None,
    ) -> List[CloudFile]:
        logger.info("OneDriveProvider.list_files is not yet fully implemented")
        return []

    async def download_file(self, file_id: str, dest_path: str) -> str:
        logger.info("OneDriveProvider.download_file is not yet fully implemented")
        return dest_path

    async def upload_file(self, local_path: str, cloud_folder: str) -> CloudFile:
        raise NotImplementedError("Upload to OneDrive is not yet implemented")


# ---------------------------------------------------------------------------
# Provider registry
# ---------------------------------------------------------------------------

_PROVIDERS: Dict[str, CloudProviderBase] = {
    "google_drive": GoogleDriveProvider(),
    "onedrive": OneDriveProvider(),
}


def get_provider(name: str) -> CloudProviderBase:
    """Return a cloud provider adapter by name.

    Raises ``KeyError`` if the provider is unknown.
    """
    return _PROVIDERS[name]


def list_providers() -> List[str]:
    """Return the names of all registered providers."""
    return list(_PROVIDERS.keys())
