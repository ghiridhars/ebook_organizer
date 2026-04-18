"""Cloud storage API endpoints"""

import json
import logging
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List
from app.services.database import get_db
from app.models import CloudConfig, CloudProviderStatus
from app.services.cloud_provider_service import get_provider, list_providers

logger = logging.getLogger(__name__)

router = APIRouter()


def _get_authenticated_adapter(provider: str, db: Session):
    """Load stored credentials and return a ready-to-use provider adapter.

    Raises HTTPException if the provider is unknown or not authenticated.
    """
    if provider not in list_providers():
        raise HTTPException(status_code=400, detail=f"Unknown provider: {provider}")

    config = db.query(CloudConfig).filter(CloudConfig.provider == provider).first()
    if not config or not config.is_authenticated:
        raise HTTPException(
            status_code=401,
            detail=f"{provider} is not authenticated. Connect it first.",
        )

    adapter = get_provider(provider)
    adapter.set_credentials(json.loads(config.credentials_encrypted))
    return adapter

@router.get("/providers", response_model=List[CloudProviderStatus])
async def get_cloud_providers(db: Session = Depends(get_db)):
    """Get status of all cloud providers"""
    providers = db.query(CloudConfig).all()
    
    # If no providers configured, return defaults
    if not providers:
        return [
            CloudProviderStatus(
                provider="google_drive",
                is_enabled=False,
                is_authenticated=False
            ),
            CloudProviderStatus(
                provider="onedrive",
                is_enabled=False,
                is_authenticated=False
            )
        ]
    
    return [
        CloudProviderStatus(
            provider=p.provider,
            is_enabled=p.is_enabled,
            is_authenticated=p.is_authenticated,
            last_sync=p.last_sync,
            folder_path=p.folder_path
        )
        for p in providers
    ]


@router.post("/providers/{provider}/authenticate")
async def authenticate_provider(provider: str, db: Session = Depends(get_db)):
    """
    Initiate OAuth authentication for a cloud provider.

    Returns the authorization URL the user should visit to grant access.
    """
    if provider not in list_providers():
        raise HTTPException(status_code=400, detail=f"Unknown provider: {provider}")

    try:
        adapter = get_provider(provider)
        auth_url = adapter.get_auth_url()
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    return {
        "status": "redirect",
        "auth_url": auth_url,
        "provider": provider,
    }


@router.get("/providers/{provider}/callback")
async def oauth_callback(
    provider: str,
    code: str = Query(..., description="Authorization code from OAuth flow"),
    db: Session = Depends(get_db),
):
    """
    OAuth callback endpoint.

    The provider redirects the user here after consent.  We exchange the
    authorization *code* for access / refresh tokens and persist them.
    """
    if provider not in list_providers():
        raise HTTPException(status_code=400, detail=f"Unknown provider: {provider}")

    try:
        adapter = get_provider(provider)
        tokens = await adapter.handle_callback(code)
    except Exception as exc:
        logger.error(f"OAuth callback failed for {provider}: {exc}")
        raise HTTPException(status_code=400, detail=f"Authentication failed: {exc}")

    # Persist credentials
    config = db.query(CloudConfig).filter(CloudConfig.provider == provider).first()
    if not config:
        config = CloudConfig(provider=provider)
        db.add(config)

    import json
    config.is_enabled = True
    config.is_authenticated = True
    config.credentials_encrypted = json.dumps(tokens)  # TODO: encrypt at rest
    db.commit()

    return {
        "status": "authenticated",
        "provider": provider,
        "message": f"Successfully connected to {provider}",
    }


@router.post("/providers/{provider}/disconnect")
async def disconnect_provider(provider: str, db: Session = Depends(get_db)):
    """Disconnect cloud provider"""
    config = db.query(CloudConfig).filter(CloudConfig.provider == provider).first()
    if not config:
        raise HTTPException(status_code=404, detail="Provider not found")
    
    config.is_enabled = False
    config.is_authenticated = False
    config.credentials_encrypted = None
    db.commit()
    
    return {"message": f"{provider} disconnected successfully"}


@router.get("/providers/{provider}/files")
async def list_cloud_files(
    provider: str,
    folder: str = Query(None, description="Folder ID to list files from"),
    db: Session = Depends(get_db),
):
    """
    List ebook files in the user's cloud storage.

    Requires the provider to be authenticated first.
    """
    try:
        adapter = _get_authenticated_adapter(provider, db)
        files = await adapter.list_files(folder_path=folder)
    except HTTPException:
        raise
    except Exception as exc:
        logger.error(f"Failed to list files from {provider}: {exc}")
        raise HTTPException(status_code=500, detail=str(exc))

    return {
        "provider": provider,
        "total": len(files),
        "files": [
            {
                "file_id": f.file_id,
                "name": f.name,
                "path": f.path,
                "size": f.size,
                "mime_type": f.mime_type,
                "modified_at": f.modified_at.isoformat() if f.modified_at else None,
            }
            for f in files
        ],
    }


@router.get("/providers/{provider}/folders")
async def list_cloud_folders(
    provider: str,
    parent_id: str = Query("root", description="Parent folder ID"),
    db: Session = Depends(get_db),
):
    """
    List subfolders in the user's cloud storage (for folder picker UI).

    Requires the provider to be authenticated first.
    """
    try:
        adapter = _get_authenticated_adapter(provider, db)
        folders = await adapter.list_folders(parent_id=parent_id)
    except HTTPException:
        raise
    except Exception as exc:
        logger.error(f"Failed to list folders from {provider}: {exc}")
        raise HTTPException(status_code=500, detail=str(exc))

    # Build a human-readable path for the current location
    current_path = "My Drive" if parent_id == "root" else parent_id

    return {
        "provider": provider,
        "parent_id": parent_id,
        "current_path": current_path,
        "folders": [
            {
                "id": f.folder_id,
                "name": f.name,
                "parent_id": f.parent_id,
            }
            for f in folders
        ],
    }
