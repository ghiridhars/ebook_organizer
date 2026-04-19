"""
Cloud provider abstraction layer.

Defines the interface every cloud storage back-end must implement,
plus concrete scaffolds for Google Drive and OneDrive using OAuth 2.0.
"""

from __future__ import annotations

import asyncio
import json
import logging
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Dict, List, Optional

from app.config import settings

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class DriveApiError(Exception):
    """Wrapper for Google Drive API errors with categorised status codes."""

    def __init__(self, message: str, status_code: int = 0, retryable: bool = False):
        super().__init__(message)
        self.status_code = status_code
        self.retryable = retryable


class DriveAuthError(DriveApiError):
    """Token expired or permissions revoked (401 / 403)."""


class DriveRateLimitError(DriveApiError):
    """Too many requests (429)."""

    def __init__(self, message: str = "Rate limited by Google Drive"):
        super().__init__(message, status_code=429, retryable=True)


class DriveNotFoundError(DriveApiError):
    """Resource not found (404)."""

    def __init__(self, message: str = "Drive resource not found"):
        super().__init__(message, status_code=404, retryable=False)


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


class CloudFolder:
    """Lightweight representation of a folder in a cloud provider."""

    def __init__(
        self,
        folder_id: str,
        name: str,
        parent_id: str = "root",
    ):
        self.folder_id = folder_id
        self.name = name
        self.parent_id = parent_id

    def __repr__(self) -> str:
        return f"<CloudFolder({self.name!r}, id={self.folder_id!r})>"


# ---------------------------------------------------------------------------
# Abstract base class
# ---------------------------------------------------------------------------

class CloudProviderBase(ABC):
    """Interface that every cloud provider adapter must implement."""

    provider_name: str = ""

    def __init__(self) -> None:
        self._token_data: Optional[Dict] = None
        self._token_refresh_callback = None  # Set by route layer to persist refreshed tokens

    def set_credentials(self, token_data: Dict) -> None:
        """Store OAuth token data for subsequent API calls."""
        self._token_data = token_data

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
    async def list_folders(self, parent_id: str = "root") -> List[CloudFolder]:
        """List subfolders of the given parent folder."""
        ...

    @abstractmethod
    async def download_file(self, file_id: str, dest_path: str) -> str:
        """Download a file to *dest_path* and return the local path."""
        ...

    @abstractmethod
    async def upload_file(self, local_path: str, cloud_folder: str) -> CloudFile:
        """Upload a local file to the cloud folder."""
        ...

    @abstractmethod
    async def create_folder(self, name: str, parent_id: str = "root") -> str:
        """Create a folder on the cloud provider. Return the new folder ID."""
        ...

    @abstractmethod
    async def move_file(self, file_id: str, new_parent_id: str) -> Dict:
        """Move a file to a different folder. Return updated file metadata."""
        ...

    @abstractmethod
    async def get_file_metadata(self, file_id: str) -> CloudFile:
        """Get metadata (name, size, mimeType, modifiedTime) for a file."""
        ...


# ---------------------------------------------------------------------------
# Google Drive scaffold
# ---------------------------------------------------------------------------

_GOOGLE_SCOPES = ["https://www.googleapis.com/auth/drive"]
_GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
_GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"

# Ebook file extensions to search for on Drive
_EBOOK_EXTENSIONS = [".epub", ".pdf", ".mobi"]


class GoogleDriveProvider(CloudProviderBase):
    """Google Drive adapter (OAuth 2.0, Desktop / OOB flow)."""

    provider_name = "google_drive"

    def __init__(self) -> None:
        super().__init__()
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

    def _build_drive_service(self):
        """Build an authenticated Google Drive v3 service from stored tokens."""
        if not self._token_data:
            raise RuntimeError(
                "No OAuth tokens configured. "
                "Call set_credentials() with stored token data first."
            )

        from google.oauth2.credentials import Credentials
        from googleapiclient.discovery import build

        creds = Credentials(
            token=self._token_data.get("access_token"),
            refresh_token=self._token_data.get("refresh_token"),
            token_uri=_GOOGLE_TOKEN_URL,
            client_id=self._client_id,
            client_secret=self._client_secret,
            scopes=_GOOGLE_SCOPES,
        )

        return build("drive", "v3", credentials=creds)

    @staticmethod
    def _translate_http_error(exc) -> DriveApiError:
        """Translate a googleapiclient HttpError into a typed DriveApiError."""
        from googleapiclient.errors import HttpError

        if not isinstance(exc, HttpError):
            return DriveApiError(str(exc))

        status = exc.resp.status if exc.resp else 0
        msg = str(exc)

        if status in (401, 403):
            return DriveAuthError(msg, status_code=status)
        if status == 429:
            return DriveRateLimitError(msg)
        if status == 404:
            return DriveNotFoundError(msg)
        if status in (500, 502, 503):
            return DriveApiError(msg, status_code=status, retryable=True)

        return DriveApiError(msg, status_code=status)

    async def _attempt_token_refresh(self) -> bool:
        """Try to refresh the access token. Returns True on success."""
        rt = (self._token_data or {}).get("refresh_token")
        if not rt:
            logger.warning("No refresh token available for Google Drive")
            return False

        try:
            new_tokens = await self.refresh_token(rt)
            # Merge new tokens into existing token data
            merged = {**(self._token_data or {}), **new_tokens}
            self._token_data = merged

            # Persist via callback if available
            if self._token_refresh_callback:
                self._token_refresh_callback(new_tokens)

            logger.info("Successfully refreshed Google Drive access token")
            return True
        except Exception as exc:
            logger.error(f"Token refresh failed: {exc}")
            return False

    async def _drive_api_call(self, fn):
        """Execute a Drive API call with retry, backoff, and auth refresh.

        *fn* is a callable (sync) that performs the actual API request.
        Retries on 429 / 500 / 503 with exponential backoff (max 3 attempts).
        On 401 / 403, attempts a single token refresh before re-raising.
        """
        from googleapiclient.errors import HttpError
        from tenacity import (
            AsyncRetrying,
            stop_after_attempt,
            wait_exponential,
            retry_if_exception,
        )

        def _is_retryable(exc):
            return isinstance(exc, DriveApiError) and exc.retryable

        try:
            async for attempt in AsyncRetrying(
                stop=stop_after_attempt(3),
                wait=wait_exponential(multiplier=1, min=1, max=30),
                retry=retry_if_exception(_is_retryable),
                reraise=True,
            ):
                with attempt:
                    try:
                        return await asyncio.to_thread(fn)
                    except HttpError as exc:
                        translated = self._translate_http_error(exc)

                        # On auth errors, try one token refresh
                        if isinstance(translated, DriveAuthError):
                            refreshed = await self._attempt_token_refresh()
                            if refreshed:
                                raise DriveApiError(
                                    str(exc), status_code=translated.status_code,
                                    retryable=True,
                                ) from exc
                            raise translated from exc

                        raise translated from exc
        except DriveApiError:
            raise
        except Exception as exc:
            raise DriveApiError(f"Unexpected error: {exc}") from exc

    # -- public API (auth) -----------------------------------------------

    def get_auth_url(self) -> str:
        if not self._client_id:
            # Re-try loading in case the file was placed after startup
            self._load_client_credentials()
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
            "scope": " ".join(_GOOGLE_SCOPES),
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

    # -- public API (Drive operations) -----------------------------------

    async def list_files(
        self,
        folder_path: Optional[str] = None,
        file_types: Optional[List[str]] = None,
    ) -> List[CloudFile]:
        """List ebook files in a Drive folder, with pagination."""
        service = self._build_drive_service()
        folder_id = folder_path or "root"

        extensions = file_types or _EBOOK_EXTENSIONS
        ext_filter = " or ".join(f"name contains '{ext}'" for ext in extensions)
        query = (
            f"'{folder_id}' in parents "
            f"and trashed = false "
            f"and ({ext_filter})"
        )

        files: List[CloudFile] = []
        page_token: Optional[str] = None

        while True:
            def _list(pt=page_token):
                return service.files().list(
                    q=query,
                    fields="nextPageToken, files(id, name, mimeType, size, modifiedTime, parents)",
                    pageSize=100,
                    pageToken=pt,
                    orderBy="name",
                ).execute()

            results = await self._drive_api_call(_list)

            for f in results.get("files", []):
                modified = None
                if f.get("modifiedTime"):
                    modified = datetime.fromisoformat(
                        f["modifiedTime"].replace("Z", "+00:00")
                    )
                parent = f.get("parents", [folder_id])[0]
                files.append(CloudFile(
                    file_id=f["id"],
                    name=f["name"],
                    path=f"{parent}/{f['name']}",
                    mime_type=f.get("mimeType", ""),
                    size=int(f.get("size", 0)),
                    modified_at=modified,
                ))

            page_token = results.get("nextPageToken")
            if not page_token:
                break

        logger.info(f"Listed {len(files)} ebook(s) in Drive folder {folder_id}")
        return files

    async def list_folders(self, parent_id: str = "root") -> List[CloudFolder]:
        """List subfolders of the given parent folder on Drive."""
        service = self._build_drive_service()

        query = (
            f"'{parent_id}' in parents "
            "and mimeType = 'application/vnd.google-apps.folder' "
            "and trashed = false"
        )

        folders: List[CloudFolder] = []
        page_token: Optional[str] = None

        while True:
            def _list(pt=page_token):
                return service.files().list(
                    q=query,
                    fields="nextPageToken, files(id, name, parents)",
                    pageSize=100,
                    pageToken=pt,
                    orderBy="name",
                ).execute()

            results = await self._drive_api_call(_list)

            for f in results.get("files", []):
                p_id = f.get("parents", [parent_id])[0] if f.get("parents") else parent_id
                folders.append(CloudFolder(
                    folder_id=f["id"],
                    name=f["name"],
                    parent_id=p_id,
                ))

            page_token = results.get("nextPageToken")
            if not page_token:
                break

        logger.info(f"Listed {len(folders)} subfolder(s) under {parent_id}")
        return folders

    async def download_file(self, file_id: str, dest_path: str) -> str:
        """Download a Drive file to *dest_path* for temporary metadata extraction."""
        service = self._build_drive_service()

        def _download():
            from googleapiclient.http import MediaIoBaseDownload

            request = service.files().get_media(fileId=file_id)
            with open(dest_path, "wb") as fh:
                downloader = MediaIoBaseDownload(fh, request)
                done = False
                while not done:
                    _status, done = downloader.next_chunk()
            return dest_path

        result = await self._drive_api_call(_download)
        logger.info(f"Downloaded Drive file {file_id} → {dest_path}")
        return result

    async def upload_file(self, local_path: str, cloud_folder: str) -> CloudFile:
        """Upload a local file to a Drive folder."""
        service = self._build_drive_service()

        import os
        filename = os.path.basename(local_path)

        file_metadata = {"name": filename, "parents": [cloud_folder]}

        def _upload():
            from googleapiclient.http import MediaFileUpload

            media = MediaFileUpload(local_path, resumable=True)
            return service.files().create(
                body=file_metadata,
                media_body=media,
                fields="id, name, mimeType, size, modifiedTime, parents",
            ).execute()

        result = await self._drive_api_call(_upload)

        modified = None
        if result.get("modifiedTime"):
            modified = datetime.fromisoformat(
                result["modifiedTime"].replace("Z", "+00:00")
            )
        return CloudFile(
            file_id=result["id"],
            name=result["name"],
            path=f"{cloud_folder}/{result['name']}",
            mime_type=result.get("mimeType", ""),
            size=int(result.get("size", 0)),
            modified_at=modified,
        )

    async def create_folder(self, name: str, parent_id: str = "root") -> str:
        """Create a folder on Drive. Returns the new folder's ID."""
        service = self._build_drive_service()

        body = {
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "parents": [parent_id],
        }

        def _create():
            return service.files().create(
                body=body, fields="id, name"
            ).execute()

        result = await self._drive_api_call(_create)
        logger.info(f"Created Drive folder '{name}' (id={result['id']}) under {parent_id}")
        return result["id"]

    async def move_file(self, file_id: str, new_parent_id: str) -> Dict:
        """Move a Drive file to a new parent folder."""
        service = self._build_drive_service()

        def _move():
            file_info = service.files().get(
                fileId=file_id, fields="parents"
            ).execute()
            previous_parents = ",".join(file_info.get("parents", []))

            return service.files().update(
                fileId=file_id,
                addParents=new_parent_id,
                removeParents=previous_parents,
                fields="id, name, parents",
            ).execute()

        result = await self._drive_api_call(_move)
        logger.info(f"Moved Drive file {file_id} → folder {new_parent_id}")
        return result

    async def get_file_metadata(self, file_id: str) -> CloudFile:
        """Get metadata for a single Drive file."""
        service = self._build_drive_service()

        def _get():
            return service.files().get(
                fileId=file_id,
                fields="id, name, mimeType, size, modifiedTime, parents",
            ).execute()

        result = await self._drive_api_call(_get)

        modified = None
        if result.get("modifiedTime"):
            modified = datetime.fromisoformat(
                result["modifiedTime"].replace("Z", "+00:00")
            )
        parent = result.get("parents", ["root"])[0] if result.get("parents") else "root"
        return CloudFile(
            file_id=result["id"],
            name=result["name"],
            path=f"{parent}/{result['name']}",
            mime_type=result.get("mimeType", ""),
            size=int(result.get("size", 0)),
            modified_at=modified,
        )


# ---------------------------------------------------------------------------
# OneDrive scaffold
# ---------------------------------------------------------------------------

_MS_AUTH_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
_MS_TOKEN_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
_MS_GRAPH_BASE = "https://graph.microsoft.com/v1.0"
_MS_SCOPES = "Files.Read Files.Read.All Files.ReadWrite.All offline_access"


class OneDriveProvider(CloudProviderBase):
    """Microsoft OneDrive adapter (OAuth 2.0 + MS Graph API)."""

    provider_name = "onedrive"

    def __init__(self) -> None:
        super().__init__()

    @property
    def _client_id(self) -> str:
        return settings.ONEDRIVE_CLIENT_ID

    @property
    def _client_secret(self) -> str:
        return settings.ONEDRIVE_CLIENT_SECRET

    @property
    def _redirect_uri(self) -> str:
        return "http://localhost:8000/api/cloud/onedrive/callback"

    @property
    def _access_token(self) -> str:
        if not self._token_data:
            raise RuntimeError(
                "No OAuth tokens configured. "
                "Call set_credentials() with stored token data first."
            )
        return self._token_data.get("access_token", "")

    def _auth_headers(self) -> Dict[str, str]:
        return {"Authorization": f"Bearer {self._access_token}"}

    @staticmethod
    def _translate_graph_error(status: int, body: str) -> DriveApiError:
        """Map MS Graph HTTP status to a typed DriveApiError."""
        if status in (401, 403):
            return DriveAuthError(body, status_code=status)
        if status == 429:
            return DriveRateLimitError(f"Rate limited by OneDrive: {body}")
        if status == 404:
            return DriveNotFoundError(f"OneDrive resource not found: {body}")
        if status in (500, 502, 503):
            return DriveApiError(body, status_code=status, retryable=True)
        return DriveApiError(body, status_code=status)

    async def _attempt_token_refresh(self) -> bool:
        """Try to refresh the access token. Returns True on success."""
        rt = (self._token_data or {}).get("refresh_token")
        if not rt:
            logger.warning("No refresh token available for OneDrive")
            return False

        try:
            new_tokens = await self.refresh_token(rt)
            merged = {**(self._token_data or {}), **new_tokens}
            self._token_data = merged

            if self._token_refresh_callback:
                self._token_refresh_callback(new_tokens)

            logger.info("Successfully refreshed OneDrive access token")
            return True
        except Exception as exc:
            logger.error(f"OneDrive token refresh failed: {exc}")
            return False

    async def _graph_request(
        self,
        method: str,
        url: str,
        *,
        json_body: Optional[Dict] = None,
        raw_content: Optional[bytes] = None,
        extra_headers: Optional[Dict[str, str]] = None,
        stream: bool = False,
        timeout: int = 60,
    ):
        """Execute an MS Graph API request with retry and auth refresh.

        Returns the parsed JSON response, or raw bytes when *stream=True*.
        Pass *raw_content* + *extra_headers* for binary uploads.
        """
        import httpx
        from tenacity import (
            AsyncRetrying,
            stop_after_attempt,
            wait_exponential,
            retry_if_exception,
        )

        def _is_retryable(exc):
            return isinstance(exc, DriveApiError) and exc.retryable

        try:
            async for attempt in AsyncRetrying(
                stop=stop_after_attempt(3),
                wait=wait_exponential(multiplier=1, min=1, max=30),
                retry=retry_if_exception(_is_retryable),
                reraise=True,
            ):
                with attempt:
                    headers = {**self._auth_headers(), **(extra_headers or {})}
                    kwargs: Dict = {"headers": headers}
                    if raw_content is not None:
                        kwargs["content"] = raw_content
                    elif json_body is not None:
                        kwargs["json"] = json_body

                    async with httpx.AsyncClient(follow_redirects=True, timeout=timeout) as client:
                        resp = await client.request(method, url, **kwargs)

                    if resp.status_code >= 400:
                        translated = self._translate_graph_error(
                            resp.status_code, resp.text
                        )
                        if isinstance(translated, DriveAuthError):
                            refreshed = await self._attempt_token_refresh()
                            if refreshed:
                                raise DriveApiError(
                                    resp.text,
                                    status_code=resp.status_code,
                                    retryable=True,
                                )
                            raise translated
                        raise translated

                    if stream:
                        return resp.content
                    if resp.status_code == 204 or not resp.text:
                        return {}
                    return resp.json()
        except DriveApiError:
            raise
        except Exception as exc:
            raise DriveApiError(f"Unexpected OneDrive error: {exc}") from exc

    def _item_url(self, item_id: str) -> str:
        """Build MS Graph URL for a drive item."""
        if item_id == "root":
            return f"{_MS_GRAPH_BASE}/me/drive/root"
        return f"{_MS_GRAPH_BASE}/me/drive/items/{item_id}"

    @staticmethod
    def _parse_datetime(value: Optional[str]) -> Optional[datetime]:
        if not value:
            return None
        return datetime.fromisoformat(value.replace("Z", "+00:00"))

    # -- public API (auth) -----------------------------------------------

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
                    "scope": _MS_SCOPES,
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
                    "scope": _MS_SCOPES,
                },
            )
            resp.raise_for_status()
            return resp.json()

    # -- public API (OneDrive operations) --------------------------------

    async def list_files(
        self,
        folder_path: Optional[str] = None,
        file_types: Optional[List[str]] = None,
    ) -> List[CloudFile]:
        """List ebook files in a OneDrive folder, following pagination."""
        folder_id = folder_path or "root"
        extensions = set(file_types or _EBOOK_EXTENSIONS)

        url = f"{self._item_url(folder_id)}/children"
        files: List[CloudFile] = []

        while url:
            data = await self._graph_request("GET", url)

            for item in data.get("value", []):
                # Skip folders
                if "folder" in item:
                    continue
                name = item.get("name", "")
                ext = "." + name.rsplit(".", 1)[-1].lower() if "." in name else ""
                if ext not in extensions:
                    continue

                files.append(CloudFile(
                    file_id=item["id"],
                    name=name,
                    path=f"{folder_id}/{name}",
                    mime_type=item.get("file", {}).get("mimeType", ""),
                    size=item.get("size", 0),
                    modified_at=self._parse_datetime(
                        item.get("lastModifiedDateTime")
                    ),
                ))

            url = data.get("@odata.nextLink")

        logger.info(f"Listed {len(files)} ebook(s) in OneDrive folder {folder_id}")
        return files

    async def list_folders(self, parent_id: str = "root") -> List[CloudFolder]:
        """List subfolders of the given parent folder on OneDrive."""
        url = f"{self._item_url(parent_id)}/children?$filter=folder ne null&$orderby=name"
        folders: List[CloudFolder] = []

        while url:
            data = await self._graph_request("GET", url)

            for item in data.get("value", []):
                if "folder" not in item:
                    continue
                folders.append(CloudFolder(
                    folder_id=item["id"],
                    name=item.get("name", ""),
                    parent_id=parent_id,
                ))

            url = data.get("@odata.nextLink")

        logger.info(f"Listed {len(folders)} subfolder(s) under OneDrive {parent_id}")
        return folders

    async def download_file(self, file_id: str, dest_path: str) -> str:
        """Download a OneDrive file to *dest_path*."""
        url = f"{self._item_url(file_id)}/content"
        content = await self._graph_request("GET", url, stream=True)

        with open(dest_path, "wb") as fh:
            fh.write(content)

        logger.info(f"Downloaded OneDrive file {file_id} → {dest_path}")
        return dest_path

    async def upload_file(self, local_path: str, cloud_folder: str) -> CloudFile:
        """Upload a local file to a OneDrive folder (simple upload ≤ 4 MB)."""
        import os

        filename = os.path.basename(local_path)
        url = f"{self._item_url(cloud_folder)}:/{filename}:/content"

        with open(local_path, "rb") as fh:
            file_bytes = fh.read()

        item = await self._graph_request(
            "PUT",
            url,
            raw_content=file_bytes,
            extra_headers={"Content-Type": "application/octet-stream"},
            timeout=120,
        )

        return CloudFile(
            file_id=item["id"],
            name=item.get("name", filename),
            path=f"{cloud_folder}/{item.get('name', filename)}",
            mime_type=item.get("file", {}).get("mimeType", ""),
            size=item.get("size", 0),
            modified_at=self._parse_datetime(item.get("lastModifiedDateTime")),
        )

    async def create_folder(self, name: str, parent_id: str = "root") -> str:
        """Create a folder on OneDrive. Returns the new folder's ID."""
        url = f"{self._item_url(parent_id)}/children"
        body = {
            "name": name,
            "folder": {},
            "@microsoft.graph.conflictBehavior": "fail",
        }

        try:
            result = await self._graph_request("POST", url, json_body=body)
        except DriveApiError as e:
            # 409 Conflict means folder already exists — look it up
            if e.status_code == 409:
                existing = await self.list_folders(parent_id)
                for f in existing:
                    if f.name == name:
                        return f.folder_id
            raise

        folder_id = result["id"]
        logger.info(
            f"Created OneDrive folder '{name}' (id={folder_id}) under {parent_id}"
        )
        return folder_id

    async def move_file(self, file_id: str, new_parent_id: str) -> Dict:
        """Move a OneDrive file to a new parent folder."""
        url = self._item_url(file_id)
        body = {"parentReference": {"id": new_parent_id}}

        result = await self._graph_request("PATCH", url, json_body=body)
        logger.info(f"Moved OneDrive file {file_id} → folder {new_parent_id}")
        return result

    async def get_file_metadata(self, file_id: str) -> CloudFile:
        """Get metadata for a single OneDrive file."""
        url = self._item_url(file_id)
        result = await self._graph_request("GET", url)

        parent_id = result.get("parentReference", {}).get("id", "root")
        return CloudFile(
            file_id=result["id"],
            name=result.get("name", ""),
            path=f"{parent_id}/{result.get('name', '')}",
            mime_type=result.get("file", {}).get("mimeType", ""),
            size=result.get("size", 0),
            modified_at=self._parse_datetime(
                result.get("lastModifiedDateTime")
            ),
        )


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
