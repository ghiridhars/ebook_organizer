"""Cloud storage API endpoints"""

import logging
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List
from app.services.database import get_db
from app.models import CloudConfig, CloudProviderStatus
from app.services.cloud_provider_service import get_provider, list_providers

logger = logging.getLogger(__name__)

router = APIRouter()

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
    folder: str = Query(None, description="Folder path to list"),
    db: Session = Depends(get_db),
):
    """
    List ebook files in the user's cloud storage.

    Requires the provider to be authenticated first.
    """
    config = db.query(CloudConfig).filter(CloudConfig.provider == provider).first()
    if not config or not config.is_authenticated:
        raise HTTPException(
            status_code=401,
            detail=f"{provider} is not authenticated. Connect it first.",
        )

    try:
        adapter = get_provider(provider)
        files = await adapter.list_files(folder_path=folder)
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
