# Ebook Organizer - User Flow Documentation

This document maps the major user flows in the Ebook Organizer application, showing the corresponding Dart (Flutter frontend) and Python (FastAPI backend) methods involved in each flow.

---

## Flow Overview

| # | Flow Name | Description |
|---|-----------|-------------|
| 1 | Library Folder Selection & Scanning | User selects a folder and scans for ebooks |
| 2 | Browse Library | User views and filters ebook list |
| 3 | Search Ebooks | User performs full-text search |
| 4 | View Ebook Details | User views detailed ebook information |
| 5 | Edit Ebook Metadata | User updates ebook metadata |
| 6 | Cloud Sync | User triggers sync with cloud/local storage |

---

## 1. Library Folder Selection & Scanning

**User Action**: User clicks "Choose Folder" → selects a directory → triggers scan

### Method Flow

| Step | Dart (Flutter) | Python (Backend) |
|------|----------------|------------------|
| 1. User picks folder | `LocalLibraryProvider.chooseLibraryFolder()` | - |
| 2. Store folder path | `LocalLibraryServiceNative.setLibraryPath()` | - |
| 3. Scan directory | `LocalLibraryServiceNative.scanDirectory()` | - |
| 4. Extract file metadata | `EpubMetadataService.extractMetadata()` | - |
| 5. Backend metadata enhancement | `BackendMetadataService.extractComprehensiveMetadata()` | `POST /api/metadata/classify` → `classify_file()` |
| 6. Classification | - | `metadata_classifier.classify_ebook()` |
| 7. Open Library lookup | - | `openlibrary_service.search_by_title_author()` |
| 8. Store in local DB | `LocalLibraryServiceNative._createDB()` | - |
| 9. Refresh UI | `LocalLibraryProvider.loadEbooks()` | - |

> **Note**: Scanning can operate in two modes:
> - **Local-only**: Metadata extracted from EPUB/PDF files locally
> - **Backend-enhanced**: Uses Python backend for AI classification and Open Library enrichment

---

## 2. Browse Library (View & Filter Ebooks)

**User Action**: User browses ebook library, applies filters (category, author, format)

### Method Flow

| Step | Dart (Flutter) | Python (Backend) |
|------|----------------|------------------|
| 1. Load ebook list | `LocalLibraryProvider.loadEbooks()` | - |
| 2. Query local DB | `LocalLibraryServiceNative.getAllLocalEbooks()` | - |
| 3. Apply category filter | `LocalLibraryProvider.setCategory()` | - |
| 4. Apply author filter | `LocalLibraryProvider.setAuthor()` | - |
| 5. Apply format filter | `LocalLibraryProvider.setFormat()` | - |
| 6. Apply search query | `LocalLibraryProvider.setSearchQuery()` | - |
| 7. Sort results | `LocalLibraryProvider.setSortBy()` | - |
| 8. Get filter options (formats) | `LocalLibraryProvider.getFormats()` | - |
| 9. Get filter options (categories) | `LocalLibraryProvider.getCategories()` | - |
| 10. Get filter options (authors) | `LocalLibraryProvider.getAuthors()` | - |
| 11. Clear all filters | `LocalLibraryProvider.clearFilters()` | - |

### Backend-Connected Browse (Scoped Library)

| Step | Dart (Flutter) | Python (Backend) |
|------|----------------|------------------|
| 1. Set active source path | `LibraryProvider.setActiveSourcePath()` | - |
| 2. Load stats for path | `LibraryProvider.loadStats()` | `GET /api/ebooks/stats?source_path=...` → `get_library_stats()` |
| 3. Fetch filtered ebooks | `ApiService.getEbooks()` | `GET /api/ebooks/` → `get_ebooks()` |
| 4. Sync to local DB | `EbookProvider.syncWithBackend()` | - |
| 5. Display from local | `EbookProvider.loadEbooksFromLocal()` | - |

---

## 3. Search Ebooks (Full-Text Search)

**User Action**: User enters search query to find ebooks by title, author, or content

### Method Flow

| Step | Dart (Flutter) | Python (Backend) |
|------|----------------|------------------|
| 1. Enter search query | `LocalLibraryProvider.setSearchQuery()` | - |
| 2. Local search | `LocalLibraryServiceNative.getAllLocalEbooks(search: query)` | - |
| 3. Backend FTS search | `ApiService.getEbooks(search: query)` | `GET /api/ebooks/search?q=...` → `search_library()` |
| 4. Full-text search execution | - | `search_service.search_ebooks()` |
| 5. Get search suggestions | - | `GET /api/ebooks/suggestions?prefix=...` → `get_suggestions()` |
| 6. Suggestion lookup | - | `search_service.get_search_suggestions()` |

---

## 4. View Ebook Details

**User Action**: User clicks on an ebook to view its full details

### Method Flow

| Step | Dart (Flutter) | Python (Backend) |
|------|----------------|------------------|
| 1. Get ebook by ID | `LocalLibraryServiceNative.getLocalEbookById()` | - |
| 2. Navigate to detail screen | `LocalEbookDetailScreen` widget | - |
| 3. Backend ebook fetch | `ApiService.getEbook(id)` | `GET /api/ebooks/{id}` → `get_ebook()` |
| 4. Read file metadata | - | `GET /api/metadata/read?file_path=...` → `read_metadata()` |
| 5. Metadata extraction | - | `metadata_service.read_metadata()` |
| 6. Get supported formats | - | `GET /api/metadata/formats` → `get_supported_formats()` |

---

## 5. Edit Ebook Metadata

**User Action**: User edits title, author, category, or other metadata fields

### Method Flow

| Step | Dart (Flutter) | Python (Backend) |
|------|----------------|------------------|
| 1. Initiate edit | `LocalEbookDetailScreen` (UI) | - |
| 2. Update local ebook | `LocalLibraryProvider.updateEbook()` | - |
| 3. Persist to local DB | `LocalLibraryServiceNative.updateLocalEbook()` | - |
| 4. Update via API (if online) | `EbookProvider.updateEbook()` | `PATCH /api/ebooks/{id}` → `update_ebook()` |
| 5. API service call | `ApiService.updateEbook()` | - |
| 6. Write metadata to file | - | `POST /api/metadata/write?file_path=...` → `write_metadata()` |
| 7. Metadata file write | - | `metadata_service.write_metadata()` |
| 8. Sync local database | `DatabaseService.updateEbook()` | - |
| 9. Refresh ebook list | `LocalLibraryProvider.loadEbooks()` | - |

---

## 6. Cloud/Local Sync

**User Action**: User triggers synchronization to scan folder and import books to backend

### Method Flow

| Step | Dart (Flutter) | Python (Backend) |
|------|----------------|------------------|
| 1. Trigger sync | `LibraryProvider.triggerSync()` | - |
| 2. API sync request | `ApiService.triggerSync()` | `POST /api/sync/trigger` → `trigger_sync()` |
| 3. Initialize sync status | - | `sync_service.set_initializing()` |
| 4. Background sync task | - | `perform_sync()` → `sync_service.sync_local_folder()` |
| 5. Scan directory | - | `os.walk(path)` in `SyncService` |
| 6. Process each file | - | `sync_service._process_file()` |
| 7. Extract metadata | - | `metadata_service.read_metadata()` |
| 8. Add to database | - | `db.add(new_ebook)` |
| 9. Poll sync status | `ApiService.getSyncStatus()` | `GET /api/sync/status` → `get_sync_status()` |
| 10. Get status | - | `sync_service.get_status()` |
| 11. Reload stats | `LibraryProvider.loadStats()` | `GET /api/ebooks/stats` → `get_library_stats()` |

---

## Additional Flows

### Delete Ebook from Index

| Step | Dart (Flutter) | Python (Backend) |
|------|----------------|------------------|
| 1. Delete from local index | `LocalLibraryProvider.deleteFromIndex()` | - |
| 2. Remove from DB | `LocalLibraryServiceNative.deleteLocalEbook()` | - |
| 3. Delete via API | `ApiService.deleteEbook()` | `DELETE /api/ebooks/{id}` → `delete_ebook()` |

### Open Ebook File

| Step | Dart (Flutter) | Python (Backend) |
|------|----------------|------------------|
| 1. Open with system app | `LocalLibraryProvider.openEbook()` | - |
| 2. Platform-specific open | `PlatformUtils.openFile()` | - |

### Open Containing Folder

| Step | Dart (Flutter) | Python (Backend) |
|------|----------------|------------------|
| 1. Open folder | `LocalLibraryProvider.openContainingFolder()` | - |
| 2. Platform-specific explore | `PlatformUtils.openFolder()` | - |

### Clear Library Index

| Step | Dart (Flutter) | Python (Backend) |
|------|----------------|------------------|
| 1. Clear index | `LocalLibraryProvider.clearIndex()` | - |
| 2. Remove all entries | `LocalLibraryServiceNative.clearAllLocalEbooks()` | - |

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                      Flutter Frontend                            │
├─────────────────────────────────────────────────────────────────┤
│  Screens          │  Providers              │  Services          │
│  ─────────────    │  ────────────────────   │  ─────────────     │
│  HomeScreen       │  LocalLibraryProvider   │  ApiService        │
│  LocalLibrary     │  LibraryProvider        │  LocalLibraryServ  │
│  EbookDetail      │  EbookProvider          │  DatabaseService   │
│  LocalDetail      │                         │  EpubMetadataServ  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP (REST API)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Python Backend                              │
├─────────────────────────────────────────────────────────────────┤
│  Routes           │  Services               │  Models            │
│  ─────────────    │  ────────────────────   │  ─────────────     │
│  /api/ebooks      │  SyncService            │  Ebook             │
│  /api/metadata    │  MetadataService        │  SyncLog           │
│  /api/sync        │  SearchService          │  Tag               │
│  /api/cloud       │  OpenLibraryService     │                    │
│                   │  TaxonomyService        │                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Files Reference

### Flutter (Dart)

| Layer | File | Description |
|-------|------|-------------|
| Providers | `lib/providers/local_library_provider.dart` | Local library state management |
| Providers | `lib/providers/library_provider.dart` | Cloud library & stats management |
| Providers | `lib/providers/ebook_provider.dart` | Ebook CRUD operations |
| Services | `lib/services/api_service.dart` | HTTP client for backend |
| Services | `lib/services/local_library_service_native.dart` | Local file scanning & DB |
| Services | `lib/services/epub_metadata_service.dart` | EPUB metadata extraction |
| Screens | `lib/screens/home_screen.dart` | Main dashboard |
| Screens | `lib/screens/local_library_screen.dart` | Local library view |
| Screens | `lib/screens/local_ebook_detail_screen.dart` | Ebook detail view |

### Python (Backend)

| Layer | File | Description |
|-------|------|-------------|
| Routes | `app/routes/ebooks.py` | Ebook CRUD endpoints |
| Routes | `app/routes/metadata.py` | Metadata read/write endpoints |
| Routes | `app/routes/sync.py` | Sync trigger endpoints |
| Services | `app/services/sync_service.py` | Folder sync logic |
| Services | `app/services/metadata_service.py` | Metadata extraction |
| Services | `app/services/search_service.py` | Full-text search |
| Services | `app/services/openlibrary_service.py` | Open Library API |
| Services | `app/services/metadata_classifier.py` | AI classification |

---

*Last updated: February 2026*
