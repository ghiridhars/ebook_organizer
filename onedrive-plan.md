# OneDrive Integration — Implementation Plan

## Overview

Add OneDrive as a third source option (alongside Local and Google Drive) in the import screen. The existing `OneDriveProvider` class already has OAuth scaffolding — we need to complete the MS Graph API methods, wire up sync/reorganization, and refactor the Flutter UI into generic cloud-provider widgets.

## Prerequisites

### Azure AD App Registration

Before coding begins, register an Azure AD application:

1. Go to [Microsoft Entra → App Registrations](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade) (sign in with your Microsoft account)
2. **+ New Registration**:
   - Name: `Ebook Organizer`
   - Supported account types: **Personal Microsoft accounts only** (or "Personal + org" if you want both)
   - Redirect URI: Platform = `Web`, URI = `http://localhost:8000/api/cloud/onedrive/callback`
3. Copy the **Application (client) ID** from the Overview page
4. **Certificates & Secrets** → **+ New client secret** → copy the **Value** (not the Secret ID)
5. **API Permissions** → **+ Add a permission** → **Microsoft Graph** → **Delegated permissions** → Add:
   - `Files.Read` — Read user files
   - `Files.ReadWrite.All` — Move/create folders for reorganization
   - `offline_access` — Refresh tokens
6. Add to backend `.env`:
   ```
   ONEDRIVE_CLIENT_ID=<client_id>
   ONEDRIVE_CLIENT_SECRET=<client_secret>
   ```

## Design Decisions

- **Full parity** with Google Drive: browse, sync, classify, reorganize on OneDrive
- **Same manual code-paste OAuth flow** as Google Drive
- **Refactor Flutter to generic cloud widgets** — `CloudConnectScreen`, `CloudToolbar`, `CloudFolderBrowser` parameterized by provider name
- **MS Graph API** for all OneDrive operations (not legacy OneDrive API)
- **Same retry/error handling** as Google Drive (tenacity, exponential backoff)

## Architecture

```
Flutter UI                              Backend (FastAPI)
─────────                              ─────────────────
Source Toggle (3 segments)
  ├─ Local → FilePicker                POST /api/sync/trigger (provider=local)
  ├─ GDrive → CloudFolderBrowser  ──►  GET  /api/cloud/providers/google_drive/folders
  └─ OneDrive → CloudFolderBrowser ──► GET  /api/cloud/providers/onedrive/folders
                                       POST /api/sync/trigger (provider=onedrive)

OneDrive API Calls ────────────────────► MS Graph v1.0:
                                          GET /me/drive/items/{id}/children
                                          GET /me/drive/items/{id}/content
                                          POST /me/drive/items/{parent}/children
                                          PATCH /me/drive/items/{id} (move)
```

## Implementation Phases

### Phase 1: Backend — Complete OneDriveProvider MS Graph API Methods

**File:** `backend/app/services/cloud_provider_service.py`

The `OneDriveProvider` class (lines ~620-716) already has:
- ✅ `get_auth_url()` — generates MS OAuth URL
- ✅ `handle_callback(code)` — exchanges code for tokens
- ✅ `refresh_token(refresh_token)` — refreshes access token

Need to implement (following GoogleDriveProvider patterns):

| Method | MS Graph API Endpoint | Notes |
|--------|----------------------|-------|
| `list_files(folder_id)` | `GET /me/drive/items/{folder_id}/children` | Filter by `.epub`, `.pdf`, `.mobi` extensions |
| `list_folders(parent_id)` | `GET /me/drive/items/{parent_id}/children` | Filter `folder` facet |
| `download_file(file_id, dest)` | `GET /me/drive/items/{file_id}/content` | Follow 302 redirect to download URL |
| `create_folder(name, parent_id)` | `POST /me/drive/items/{parent_id}/children` | `{"name": name, "folder": {}}` |
| `move_file(file_id, new_parent)` | `PATCH /me/drive/items/{file_id}` | `{"parentReference": {"id": new_parent}}` |
| `get_file_metadata(file_id)` | `GET /me/drive/items/{file_id}` | Map to `CloudFile` DTO |
| `upload_file(path, folder)` | `PUT /me/drive/items/{parent}:/{name}:/content` | Simple upload for small files |

Implementation details:
- Base URL: `https://graph.microsoft.com/v1.0`
- Auth header: `Authorization: Bearer {access_token}`
- Use `httpx` for async HTTP calls (same as Google Drive token exchange)
- Pagination: MS Graph uses `@odata.nextLink` — follow until exhausted
- Error mapping: 401 → `DriveAuthError`, 429 → `DriveRateLimitError`, 404 → `DriveNotFoundError`
- Same retry decorator as Google Drive (`@retry` with tenacity)

**File:** `backend/app/config.py`

Add OneDrive settings:
```python
ONEDRIVE_CLIENT_ID: str = os.getenv("ONEDRIVE_CLIENT_ID", "")
ONEDRIVE_CLIENT_SECRET: str = os.getenv("ONEDRIVE_CLIENT_SECRET", "")
```

**File:** `backend/.env.example`

Add OneDrive environment variables.

### Phase 2: Backend — OneDrive Sync Flow

**File:** `backend/app/services/sync_service.py`

Add `sync_onedrive(folder_id, full_sync, db)` following the exact `sync_google_drive()` pattern:

1. Load `CloudConfig` for provider `"onedrive"`
2. Initialize `OneDriveProvider` adapter with stored credentials
3. Set token refresh callback (same pattern as Google Drive)
4. Call `adapter.list_files(folder_id)` — get OneDrive ebooks
5. For each file:
   - Check `cloud_file_id` for dedup
   - Incremental: skip if `cloud_modified_time >= file.modified_at`
   - `adapter.download_file(file_id)` → temp path
   - Extract metadata + classify
   - Create/update `Ebook` record with `cloud_provider="onedrive"`
   - Delete temp file
6. Update `SyncLog` and `CloudConfig.last_sync`

**File:** `backend/app/routes/sync.py`

Extend `perform_sync()` background task to handle `provider == "onedrive"`:
```python
elif provider in ("onedrive", "all"):
    result = await sync_service.sync_onedrive(folder_id, full_sync, db)
```

### Phase 3: Backend — OneDrive Reorganization

**File:** `backend/app/services/file_organizer_service.py`

Add OneDrive-specific reorganization methods following the Google Drive pattern:

- `generate_onedrive_reorganize_plan()` — filter ebooks where `cloud_provider == "onedrive"`
- `execute_onedrive_reorganization()`:
  1. Load OneDriveProvider adapter + credentials
  2. For each OneDrive ebook:
     - `_ensure_drive_folder_path()` → create `Category/SubGenre/Author/` hierarchy (reuse existing helper with OneDrive adapter)
     - `adapter.move_file(file_id, target_folder_id)`
     - Update `Ebook.cloud_file_path`
  3. Use folder cache to avoid duplicate creation

The existing `_get_or_create_folder()` and `_ensure_drive_folder_path()` helpers should already work if they accept the adapter as a parameter (they do — they take an adapter argument).

**File:** `backend/app/routes/organization.py`

Extend reorganize endpoints to detect `request.destination.startswith("onedrive:")` and route to OneDrive reorganization.

### Phase 4: Flutter — Refactor to Generic Cloud Widgets

This phase refactors Drive-specific code into provider-agnostic widgets.

**File:** `lib/providers/local_library_provider.dart`

1. Extend enum:
   ```dart
   enum LibrarySource { local, googleDrive, oneDrive }
   ```

2. Genericize cloud state fields:
   ```dart
   // Replace Drive-specific fields with a map or add OneDrive equivalents
   Map<String, String?> _cloudFolderIds = {};  // {'google_drive': 'abc', 'onedrive': 'xyz'}
   Map<String, String?> _cloudFolderPaths = {};
   Map<String, bool> _cloudAuthenticated = {'google_drive': false, 'onedrive': false};
   Map<String, bool> _cloudSyncing = {'google_drive': false, 'onedrive': false};
   ```
   OR simpler: add parallel OneDrive fields:
   ```dart
   String? _onedriveFolderId;
   String? _onedriveFolderPath;
   bool _isOnedriveAuthenticated = false;
   bool _isOnedriveSyncing = false;
   ```

3. Add helper getters:
   ```dart
   bool get isOnedriveSource => _source == LibrarySource.oneDrive;
   bool get isCloudSource => isDriveSource || isOnedriveSource;
   String get activeCloudProvider => isDriveSource ? 'google_drive' : 'onedrive';
   ```

4. Add methods:
   - `checkOnedriveAuth()` — same pattern as `checkDriveAuth()`
   - `selectOnedriveFolder(id, path)` — same pattern as Drive
   - `triggerOnedriveSync()` — same pattern, `provider: 'onedrive'`

5. Update `setSource()` to handle `oneDrive` case.

6. Add SharedPreferences keys:
   ```dart
   static const String _onedriveFolderIdKey = 'onedrive_folder_id';
   static const String _onedriveFolderPathKey = 'onedrive_folder_path';
   ```

**File:** `lib/services/api_service.dart`

Add generic cloud methods or OneDrive-specific equivalents:
```dart
Future<List<Map<String, dynamic>>> listCloudFolders(String provider, {String parentId = 'root'})
Future<List<Map<String, dynamic>>> listCloudFiles(String provider, {String? folderId})
```
These call `/api/cloud/providers/{provider}/folders` and `/api/cloud/providers/{provider}/files` — the backend routes are already parameterized.

### Phase 5: Flutter — UI Updates

**File:** `lib/screens/local_library_screen.dart`

1. **SegmentedButton**: Add third segment:
   ```dart
   ButtonSegment(
     value: LibrarySource.oneDrive,
     label: Text('OneDrive'),
     icon: Icon(Icons.cloud_outlined),  // Different icon to distinguish
   ),
   ```

2. **Refactor `_DriveConnectScreen` → `_CloudConnectScreen`**:
   - Accept `provider` parameter (`'google_drive'` or `'onedrive'`)
   - Dynamic labels: "Connect Google Drive" vs "Connect OneDrive"
   - Dynamic icons: Google Drive icon vs OneDrive icon
   - Same OAuth code-paste dialog flow, parameterized by provider

3. **Refactor `_DriveToolbar` → `_CloudToolbar`**:
   - Accept `provider`, `folderPath`, `isSyncing`, callbacks
   - Same layout, different labels

4. **Conditional rendering**: Add `isOnedriveSource` branch:
   ```dart
   if (provider.isOnedriveSource) {
     if (!provider.isOnedriveAuthenticated) return _CloudConnectScreen(provider: 'onedrive');
     if (!provider.hasOnedriveFolder) return CloudFolderBrowser(provider: 'onedrive', ...);
     return Column(children: [_CloudToolbar(provider: 'onedrive', ...), ...]);
   }
   ```

**File:** `lib/widgets/drive_folder_browser.dart` → refactor or rename

- Rename to `cloud_folder_browser.dart` / `CloudFolderBrowser`
- Accept `provider` parameter
- Change API calls from `listDriveFolders()` to `listCloudFolders(provider)`
- Update root breadcrumb: "My Drive" for Google, "OneDrive" for Microsoft
- Same navigation logic works for both

### Phase 6: Backend Config & Environment

**File:** `backend/.env`
```
ONEDRIVE_CLIENT_ID=<from_azure_portal>
ONEDRIVE_CLIENT_SECRET=<from_azure_portal>
```

**File:** `backend/.env.example`
```
ONEDRIVE_CLIENT_ID=
ONEDRIVE_CLIENT_SECRET=
```

**File:** `backend/app/config.py`

Ensure `ONEDRIVE_CLIENT_ID` and `ONEDRIVE_CLIENT_SECRET` are read from environment.

### Phase 7: Testing & Polish

- Verify OAuth flow end-to-end (Azure app → auth URL → code → tokens)
- Test folder browsing with OneDrive root and nested folders
- Test sync with a folder containing EPUBs/PDFs/MOBIs
- Test incremental sync (modified files only)
- Test reorganization (create folders + move files on OneDrive)
- Test token refresh (wait for token expiry or force refresh)
- Test error handling (revoke access, rate limits)
- Verify Google Drive still works after refactoring

## File Change Summary

| File | Change | Effort |
|------|--------|--------|
| `backend/app/services/cloud_provider_service.py` | Complete OneDriveProvider API methods (~7 methods) | Major |
| `backend/app/services/sync_service.py` | Add `sync_onedrive()` | Medium |
| `backend/app/services/file_organizer_service.py` | Add OneDrive reorganization | Medium |
| `backend/app/routes/sync.py` | Handle `provider="onedrive"` | Small |
| `backend/app/routes/organization.py` | Handle `"onedrive:"` prefix | Small |
| `backend/app/config.py` | Add OneDrive env settings | Small |
| `backend/.env.example` | Add OneDrive env vars | Small |
| `gui/lib/providers/local_library_provider.dart` | Add OneDrive enum + state + methods | Medium |
| `gui/lib/services/api_service.dart` | Add generic cloud API methods | Medium |
| `gui/lib/screens/local_library_screen.dart` | 3-segment toggle + refactor to generic cloud widgets | Major |
| `gui/lib/widgets/drive_folder_browser.dart` | Rename + parameterize by provider | Medium |

## MS Graph API Reference

### Authentication
- Auth URL: `https://login.microsoftonline.com/common/oauth2/v2.0/authorize`
- Token URL: `https://login.microsoftonline.com/common/oauth2/v2.0/token`
- Scopes: `Files.Read Files.Read.All Files.ReadWrite.All offline_access`

### Key Endpoints
- List children: `GET https://graph.microsoft.com/v1.0/me/drive/items/{item-id}/children`
- Download: `GET https://graph.microsoft.com/v1.0/me/drive/items/{item-id}/content` (302 → download URL)
- Create folder: `POST https://graph.microsoft.com/v1.0/me/drive/items/{parent-id}/children`
- Move file: `PATCH https://graph.microsoft.com/v1.0/me/drive/items/{item-id}`
- Root folder: Use `root` as item-id for top-level

### Pagination
MS Graph uses `@odata.nextLink` for pagination. Loop requests until no `nextLink` returned.

### File Filtering
Unlike Google Drive's query syntax, OneDrive children endpoint returns all items. Filter client-side by file extension (`.epub`, `.pdf`, `.mobi`) and by `folder` facet for folders.

## Dependencies

No new Python packages needed — `msal` and `httpx` already in requirements.txt.
No new Flutter packages needed — `url_launcher`, `http`, `shared_preferences` already in pubspec.yaml.
