# Google Drive Sync — Implementation Plan

## Overview

Add Google Drive as a primary ebook source alongside local filesystem. Users can toggle between Local and Google Drive from the same screen, browse Drive folders, and use the full classify/reorganize pipeline — with reorganization happening directly on Google Drive.

## Design Decisions

- **Drive is primary storage** — files live on Drive, downloaded temporarily only for metadata extraction
- **No cover extraction** for Drive books (skipped to avoid full downloads)
- **User-specified folder** — user browses and selects a Drive folder via a folder picker
- **Reorganize on Drive** — creates folder tree (`Category/SubGenre/Author/`) on Drive and moves files via API
- **Unified UI** — Local tab gets a source toggle; same grid/list, classify, and reorganize screens work for both sources

## Architecture

```
Flutter UI                          Backend (FastAPI)
─────────                          ─────────────────
Source Toggle                      
  ├─ Local → FilePicker            POST /api/sync/trigger (provider=local)
  └─ GDrive → Folder Browser  ──► GET  /api/cloud/providers/google_drive/folders
                                   POST /api/sync/trigger (provider=google_drive)

Classify Screen ──────────────────► POST /api/organization/classify
Reorganize Screen ────────────────► POST /api/organization/reorganize
                                      ├─ local  → shutil.move()
                                      └─ gdrive → Drive API move_file()
```

## Implementation Phases

### Phase 1: Backend — Drive API Operations ✅

**File:** `backend/app/services/cloud_provider_service.py`

| Method | Purpose |
|--------|---------|
| `list_files(folder_id)` | Enumerate ebooks (.epub/.pdf/.mobi) in a Drive folder, paginated |
| `list_folders(parent_id)` | List subfolders for the folder browser UI |
| `download_file(file_id)` → temp path | Download to `/tmp/` for metadata extraction, return path |
| `create_folder(name, parent_id)` | Create folder on Drive (for reorganization) |
| `move_file(file_id, new_parent_id)` | Move a file to a different Drive folder |
| `get_file_metadata(file_id)` | Get name, size, mimeType, modifiedTime |

All methods build a Drive v3 service from stored OAuth credentials, auto-refreshing tokens as needed.

### Phase 2: Backend — Drive Sync Flow ✅

**File:** `backend/app/services/sync_service.py`

Add `sync_google_drive(folder_id, full_sync, db)`:

1. Call `list_files(folder_id)` to enumerate ebooks
2. For each file:
   - Check `cloud_file_id` in DB for dedup
   - `download_file(file_id)` → temp path
   - `metadata_service.read_metadata(temp_path)` → extract title/author/subjects
   - `metadata_classifier.classify_book(...)` → category/sub_genre
   - Create/update `Ebook` record with `cloud_provider="google_drive"`, `cloud_file_id`, `cloud_file_path`
   - Delete temp file
3. Update `SyncLog` with results

**File:** `backend/app/routes/sync.py`

Extend `POST /api/sync/trigger` to accept `provider="google_drive"` + `folder_id`.

### Phase 3: Backend — Drive Folder Browser & Reorganize ✅

**File:** `backend/app/routes/cloud.py`

| Endpoint | Purpose |
|----------|---------|
| `GET /api/cloud/providers/google_drive/folders?parent_id=` | List subfolders (for folder picker) |
| `GET /api/cloud/providers/google_drive/files?folder_id=` | List ebook files in folder |

**File:** `backend/app/services/file_organizer_service.py`

Extend `execute_reorganization()`:
- If `cloud_provider == "google_drive"`:
  - `create_folder("Category/SubGenre/Author")` on Drive (creating each level)
  - `move_file(file_id, target_folder_id)` instead of `shutil.move()`
  - Update DB `cloud_file_path` with new Drive path

### Phase 4: Flutter — Source Toggle & Folder Browser ✅

**File:** `ebook_organizer_gui/lib/screens/local_library_screen.dart`

- Add `SegmentedButton` at top: `[📁 Local]` | `[☁️ Google Drive]`
- When GDrive selected:
  - Not authenticated → "Connect Google Drive" button → OAuth flow
  - Authenticated, no folder → Drive Folder Browser widget
  - Folder selected → same book grid/list view

**New widget:** `ebook_organizer_gui/lib/widgets/drive_folder_browser.dart`

- Breadcrumb path bar (`My Drive > Ebooks > Fiction`)
- List of subfolders (tap to navigate deeper)
- "Select This Folder" button
- Calls `GET /api/cloud/providers/google_drive/folders?parent_id=`

**File:** `ebook_organizer_gui/lib/providers/local_library_provider.dart`

- Add `sourceType` enum (`local`, `googleDrive`)
- Add `driveFolderId` / `driveFolderPath` state
- Extend `scanLibrary()` to call Drive sync when source is GDrive
- `triggerSync()` passes provider type to backend

### Phase 5: Incremental Sync & Polish ✅

- ✅ Compare `modifiedTime` from Drive API vs `cloud_modified_time` on DB record — skip unchanged files
- ✅ Token auto-refresh before each Drive API call (with callback to persist new tokens)
- ✅ Rate limiting with exponential backoff via tenacity (3 attempts, 1-30s backoff, retries on 429/5xx)
- ✅ Typed error handling: `DriveApiError` → `DriveAuthError`, `DriveRateLimitError`, `DriveNotFoundError`

## File Change Summary

| File | Change Type |
|------|-------------|
| `backend/app/services/cloud_provider_service.py` | Major — implement 6 Drive API methods |
| `backend/app/services/sync_service.py` | Medium — add `sync_google_drive()` |
| `backend/app/routes/sync.py` | Small — extend trigger to accept provider |
| `backend/app/routes/cloud.py` | Medium — add folders/files endpoints |
| `backend/app/services/file_organizer_service.py` | Medium — Drive reorganization branch |
| `backend/app/routes/organization.py` | Small — pass provider context through |
| `gui/lib/screens/local_library_screen.dart` | Medium — source toggle + conditional UI |
| `gui/lib/providers/local_library_provider.dart` | Medium — GDrive state + source type |
| `gui/lib/widgets/drive_folder_browser.dart` | New — folder picker widget |
| `gui/lib/services/api_service.dart` | Small — add folder/file listing API calls |

## Dependencies (in requirements.txt)

- `google-api-python-client==2.116.0`
- `google-auth==2.27.0`
- `google-auth-oauthlib==1.2.0`
- `tenacity>=8.2.0`

## API Contracts

### List Folders
```
GET /api/cloud/providers/google_drive/folders?parent_id=root
Response: {
  "folders": [
    {"id": "abc123", "name": "Ebooks", "parent_id": "root"},
    {"id": "def456", "name": "Documents", "parent_id": "root"}
  ],
  "current_path": "My Drive"
}
```

### Trigger Drive Sync
```
POST /api/sync/trigger
Body: {
  "provider": "google_drive",
  "folder_id": "abc123",
  "full_sync": false
}
```

### Reorganize (Drive)
```
POST /api/organization/reorganize
Body: {
  "source_path": "google_drive:abc123",
  "destination_path": "google_drive:abc123",
  "operation": "move",
  "include_unclassified": false
}
```
