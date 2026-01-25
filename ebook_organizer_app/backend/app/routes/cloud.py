"""Cloud storage API endpoints"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from app.services.database import get_db
from app.models import CloudConfig, CloudProviderStatus

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
    Initiate OAuth authentication for cloud provider
    TODO: Implement OAuth flow
    """
    if provider not in ["google_drive", "onedrive"]:
        raise HTTPException(status_code=400, detail="Invalid provider")
    
    return {
        "message": f"Authentication for {provider} not yet implemented",
        "status": "pending",
        "auth_url": None
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
