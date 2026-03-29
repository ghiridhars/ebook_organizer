# Realistic Implementation Plan: eBook Organizer on Raspberry Pi 5

> Companion to `grand_plan.md`. This document captures every implementation detail
> derived from auditing the existing codebase and aligning it with the Pi deployment vision.

---

## Table of Contents

1. [Current State Assessment](#1-current-state-assessment)
2. [Target Architecture](#2-target-architecture)
3. [Hardware & Environment](#3-hardware--environment)
4. [Phase 1 — ARM Backend Deployment & SQLite Tuning](#phase-1--arm-backend-deployment--sqlite-tuning)
5. [Phase 2 — Watchdog Auto-Ingest](#phase-2--watchdog-auto-ingest)
6. [Phase 3 — Cover Art Extraction & Thumbnails](#phase-3--cover-art-extraction--thumbnails)
7. [Phase 4 — Ebook File Serving & Streaming](#phase-4--ebook-file-serving--streaming)
8. [Phase 5 — Full Web UI (Library, Reader, Classification, Reorganization)](#phase-5--full-web-ui-library-reader-classification-reorganization)
9. [Phase 6 — Infrastructure & Production Deployment](#phase-6--infrastructure--production-deployment)
10. [Appendix A — Full File Inventory](#appendix-a--full-file-inventory)
11. [Appendix B — Dependency Audit](#appendix-b--dependency-audit)
12. [Appendix C — Decisions Log](#appendix-c--decisions-log)

---

## 1. Current State Assessment

### 1.1 What Already Exists

The ebook organizer is a **backend-centric application** deployed headless on the Pi (no desktop GUI). All user interaction is through a **lightweight web UI** served by the backend, accessible from any device on the LAN:

| Component | Technology | Status |
|-----------|-----------|--------|
| **Backend** | Python 3.11 + FastAPI 0.109 + Uvicorn 0.27 | ~80% feature-complete |
| **Web UI** | Vanilla JS + Alpine.js + TailwindCSS + epub.js | New (Phase 5) |
| **Flutter GUI** | Flutter (Desktop: Windows/Linux, Web: partial) | ~90% UI-complete — used for desktop dev only, NOT deployed on Pi |

### 1.2 Backend — Implemented Features

#### Database & ORM
- **Engine:** SQLite via SQLAlchemy 2.0.25
- **Migrations:** Alembic 1.13.1 with baseline migration in place
- **File:** `backend/app/models/database.py`
- **Connection:** `sqlite:///./ebook_organizer.db`, `check_same_thread=False`
- **Schema (4 tables):**

  | Table | Key Columns | Purpose |
  |-------|------------|---------|
  | `ebooks` | id, title, author, isbn, publisher, category, sub_genre, file_format, file_size, file_hash, cloud_provider, cloud_file_id, cloud_file_path, is_synced, sync_status, created_at, updated_at | Core book records |
  | `tags` | id, ebook_id (FK), name, created_at | User-defined tags |
  | `sync_logs` | id, cloud_provider, operation, status, books_processed/added/updated/failed, error_message, started_at, completed_at, duration_seconds | Sync history |
  | `cloud_configs` | id, provider (unique), is_enabled, is_authenticated, credentials_encrypted, folder_path, last_sync, created_at, updated_at | Cloud auth state |

- **FTS5 Virtual Table:** `ebooks_fts` on (title, author, description, category, sub_genre) with Porter stemmer, Unicode support, BM25 ranking
- **FTS5 Sync:** Auto-triggers on INSERT, UPDATE, DELETE

#### Metadata Extraction (3 formats)
- **EPUB:** Dublin Core metadata via `ebooklib` — title, creator, description, publisher, language, date, subjects, identifier. Read + Write.
- **PDF:** PDF Info dictionary via `pypdf` — Title, Author, Subject, Keywords. Read + Write.
- **MOBI/AZW:** Header extraction via `mobi` library. Read-only (proprietary format).
- **File:** `backend/app/services/metadata_service.py`
- **Supported formats constant:** `SUPPORTED_FORMATS`, `WRITABLE_FORMATS`
- **Write safety:** Backup original → write → restore on failure

#### Classification System (2-tier)
- **Tier 1 — Extraction** (`backend/app/services/metadata_classifier.py`):
  - Embedded metadata parsing
  - Folder name heuristics
  - Open Library API lookup (external call)
  - Filename pattern matching: `Author - Title`, `Title (Author)`, etc.
  - Author blacklist (junk values, "PDFDrive", etc.)

- **Tier 2 — Taxonomy** (`backend/app/services/taxonomy.py`):
  - 2-level hierarchy: Category → Sub-Genre
  - **Fiction:** 14 sub-genres (Fantasy, Sci-Fi, Mystery & Thriller, Horror, Romance, Historical, Literary, Humor, Adventure, Short Stories, Drama, Poetry, YA Fiction, Other)
  - **Non-Fiction:** 15 sub-genres (Biography, History, Science & Tech, Business, Self-Help, Philosophy, Psychology, Politics, Arts, Health, Travel, Essays, and more)
  - Subject-term aliases map to Open Library vocabulary
  - Priority matching: Biography/Autobiography > BISAC codes > keywords > taxonomy aliases

#### File Organization Service
- **File:** `backend/app/services/file_organizer_service.py`
- Generates reorganization plans (preview/dry-run)
- Executes file moves/copies with DB path updates
- Path collision resolution (appends numeric suffix)
- Windows-safe folder naming (removes forbidden chars)
- **Output structure:**
  ```
  Destination/
  ├── Category/
  │   └── SubGenre/
  │       └── Author Name/
  │           ├── Title1.epub
  │           └── Title2.pdf
  └── Unclassified/
      └── Mystery File.mobi
  ```

#### Sync Service
- **File:** `backend/app/services/sync_service.py`
- Local folder sync: scan directory → extract metadata → populate DB
- Duplicate detection via file path
- Background task processing with status: idle, scanning, processing, completed, failed
- Real-time status via `GET /api/sync/status`

#### Search Service
- **File:** `backend/app/services/search_service.py`
- FTS5 full-text search with BM25 relevance
- Default pagination: 20 results, max 100
- Typeahead suggestions endpoint
- `LIMIT :limit OFFSET :offset` — works fine for 100k+ rows

#### Format Conversion
- **File:** `backend/app/routes/conversion.py`
- MOBI → EPUB (pure Python, no Calibre dependency)
- Extracts MOBI HTML via `mobi` library → creates EPUB via `ebooklib`
- Image preservation, BeautifulSoup HTML cleanup
- UUID-based identifiers

#### Cloud Providers (Scaffolded)
- **File:** `backend/app/services/cloud_provider_service.py`
- Abstract base: `CloudProviderBase` with get_auth_url, handle_callback, refresh_token, list_files, download_file, upload_file
- Google Drive: OAuth 2.0 (scaffolded, not production-tested)
- OneDrive: MSAL auth (scaffolded, not production-tested)
- Local filesystem: Fully implemented

#### All API Endpoints (Current)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/health` | Health check |
| GET | `/api/ebooks/` | List ebooks with filtering & pagination |
| GET | `/api/ebooks/{id}` | Get single ebook with tags |
| PATCH | `/api/ebooks/{id}` | Update metadata |
| DELETE | `/api/ebooks/{id}` | Remove from DB |
| GET | `/api/ebooks/search?q=...` | FTS5 search |
| GET | `/api/ebooks/search/suggestions?prefix=...` | Typeahead |
| GET | `/api/ebooks/stats/library` | Aggregate stats |
| GET | `/api/metadata/read?file_path=...` | Extract metadata from file |
| PUT | `/api/metadata/write?file_path=...` | Write metadata to file |
| POST | `/api/metadata/extract` | Upload + extract (legacy) |
| GET | `/api/metadata/supported-formats` | Format capabilities |
| GET | `/api/organization/taxonomy` | Category/sub-genre tree |
| POST | `/api/organization/classify/{ebook_id}` | Classify single book |
| POST | `/api/organization/batch-classify` | Classify multiple |
| GET | `/api/organization/stats` | Classification coverage |
| GET | `/api/organization/preview` | Dry-run reorganization |
| POST | `/api/sync/trigger` | Start sync (background) |
| GET | `/api/sync/status` | Sync progress |
| GET | `/api/cloud/providers` | List provider status |
| POST | `/api/cloud/providers/{provider}/authenticate` | OAuth URL |
| GET | `/api/cloud/providers/{provider}/callback` | OAuth callback |
| POST | `/api/cloud/providers/{provider}/disconnect` | Revoke |
| GET | `/api/cloud/providers/{provider}/files` | List cloud files |
| POST | `/api/conversion/mobi-to-epub` | Convert MOBI→EPUB |
| GET | `/api/conversion/check-calibre` | Check Calibre availability |

### 1.3 Frontend (Flutter) — Implemented Features

- **Providers (state management):** EbookProvider, LibraryProvider, LocalLibraryProvider, ThemeProvider
- **Screens:** HomeScreen, LocalLibraryScreen, ClassificationScreen, ReorganizeScreen, EbookDetailScreen, LocalEbookDetailScreen
- **Services:** ApiService (HTTP REST), BackendService (auto-starts Python backend as subprocess on desktop), DatabaseService (local SQLite via sqflite_common_ffi), ConversionService, BackendMetadataService
- **UI:** Material Design 3, dark/light/system themes, grid/list view, staggered grid, skeleton loading, cached images, online/offline indicator
- **Local DB:** Separate `local_library.db` with `local_ebooks` table (file_path, file_name, title, author, file_format, file_size, etc.)
- **Platform matrix:**

  | Platform | Status | Notes |
  |----------|--------|-------|
  | Windows | ✅ Full | All features |
  | Linux | ✅ Full | GTK 3.0 dep, ARM64 compatible |
  | Web | ⚠️ Partial | No dir scanning, in-memory storage |

### 1.4 What's MISSING for the Pi Vision

| Gap | Severity | Phase |
|-----|----------|-------|
| No ARM Docker image | Blocker | 1 |
| No SQLite perf tuning | High (100k books) | 1 |
| No file watcher / auto-ingest | High | 2 |
| No cover art extraction | Medium | 3 |
| No `cover_path` in DB schema | Medium | 3 |
| No static file serving | Medium | 3 |
| No ebook download endpoint | High | 4 |
| No ebook streaming endpoint | High (epub.js needs it) | 4 |
| No web UI for remote access | High | 5 |
| No epub.js reader | High | 5 |
| No reverse proxy config | Low | 6 |
| No systemd / autostart | Low | 6 |
| `Pillow` not in deps | Blocker for covers | 3 |
| `watchdog` not in deps | Blocker for watcher | 2 |

---

## 2. Target Architecture (Headless)

```
┌─────────────────────────────────────────────────────────┐
│               Raspberry Pi 5 (8GB) — Headless            │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Caddy Reverse Proxy  :80/:443                   │   │
│  │  /api/*    → backend:8000                        │   │
│  │  /web/*    → static web UI                       │   │
│  │  /static/* → covers/assets                       │   │
│  └──────────────────────┬───────────────────────────┘   │
│                          │                               │
│                          ▼                               │
│  ┌──────────────────────────────────────────────────┐   │
│  │           FastAPI Backend (:8000)                 │   │
│  │                                                   │   │
│  │  ┌──────────┐ ┌────────────┐ ┌──────────────┐   │   │
│  │  │ Watcher  │ │ Metadata   │ │ Cover        │   │   │
│  │  │ Service  │ │ Pipeline   │ │ Service      │   │   │
│  │  │(watchdog)│→│(extract →  │→│(Pillow →     │   │   │
│  │  │          │ │ classify)  │ │ WebP thumb)  │   │   │
│  │  └──────────┘ └────────────┘ └──────────────┘   │   │
│  │                                                   │   │
│  │  ┌──────────┐ ┌────────────┐ ┌──────────────┐   │   │
│  │  │ Search   │ │ File Org   │ │ Streaming    │   │   │
│  │  │ (FTS5)   │ │ Service    │ │ Endpoints    │   │   │
│  │  └──────────┘ └────────────┘ └──────────────┘   │   │
│  │                                                   │   │
│  │         SQLite (WAL mode, 64MB cache)            │   │
│  │         ebook_organizer.db                        │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  Volumes:                                                │
│  /library/       ← organized ebook storage               │
│  /library/inbox/ ← watchdog monitored drop folder        │
│  /data/          ← SQLite DB + covers cache              │
│  /data/covers/   ← WebP thumbnails (400×600)             │
│                                                          │
│  All access: laptop/phone/tablet → http://pi-ip/web/     │
└─────────────────────────────────────────────────────────┘
```

### Access Modes

| Mode | Client | How |
|------|--------|-----|
| **Primary (browser)** | Vanilla JS + Alpine.js + epub.js | `http://pi-ip/web/` — browse, search, read, classify, reorganize |
| **API (developer)** | Swagger UI | `http://pi-ip/docs` or `http://pi-ip:8000/docs` |
| **SSH (admin)** | Terminal | `ssh pi@pi-ip` — Docker logs, config, backup |

---

## 3. Hardware & Environment

| Spec | Value |
|------|-------|
| **Device** | Raspberry Pi 5 |
| **RAM** | 8GB |
| **CPU** | Broadcom BCM2712, 4× Cortex-A76 @ 2.4GHz |
| **Architecture** | ARM64 (aarch64) |
| **Storage** | External NVMe SSD via PCIe HAT (recommended) or high-endurance A2 MicroSD |
| **Cooling** | Official Active Cooler (required — prevents thermal throttling) |
| **Power** | 27W USB-C PD official PSU (prevents brownouts) |
| **OS** | Raspberry Pi OS Lite (64-bit, Bookworm) or Ubuntu Server 24.04 ARM64 — **headless, no desktop environment** |
| **Library size** | 100,000+ ebooks |
| **Disk estimate** | ~500GB for 100k ebooks (avg 5MB each) + ~5GB covers (50KB × 100k) + <1GB DB |

### Memory Budget (8GB)

| Component | Estimated RAM | Notes |
|-----------|--------------|-------|
| OS (headless) | ~150MB | No desktop environment, CLI only |
| FastAPI backend | ~250MB idle, ~500MB during batch ops | Python runtime + deps |
| SQLite (mmap + cache) | ~320MB | 256MB mmap + 64MB cache |
| Caddy proxy | ~30MB | Very lightweight |
| Cover cache (hot) | ~100MB | OS file cache for frequently accessed covers |
| **Total estimated** | **~850MB typical, ~1.1GB peak** | **6.9GB free for OS file cache / batch ops** |

---

## Phase 1 — ARM Backend Deployment & SQLite Tuning

### Step 1.1: Update Dockerfile for ARM64

**File to modify:** `ebook_organizer_app/backend/Dockerfile`

**Current state:**
```dockerfile
FROM python:3.11-slim
# ... no platform specified, no build tools for native extensions
```

**Required changes:**
- Base image → `python:3.11-slim-bookworm` (has ARM64 manifest in Docker Hub)
- Add `build-essential` and `python3-dev` for compiling `cryptography` wheel (dependency of `python-jose`)
- Add `libsqlite3-dev` to ensure latest SQLite with FTS5 support
- Keep `curl` for healthcheck

**Target Dockerfile:**
```dockerfile
FROM python:3.11-slim-bookworm
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    build-essential \
    python3-dev \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Notes:**
- Removed `--reload` from CMD (production mode; dev can override via docker-compose)
- `start-period` increased to 40s (ARM may be slower to start)
- Multi-arch build command: `docker buildx build --platform linux/arm64,linux/amd64 -t ebook-organizer-backend .`

### Step 1.2: Docker Compose for Pi

**File to modify:** `ebook_organizer_app/docker-compose.yml`

**Add Pi-specific profile or create `docker-compose.pi.yml`:**

```yaml
version: '3.8'

services:
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: ebook_organizer_backend
    ports:
      - "8000:8000"
    volumes:
      - ./backend:/app
      - ebook_data:/app/data
      - /mnt/library:/library          # External SSD mount point
      - /mnt/library/inbox:/library/inbox  # Watchdog drop folder
    environment:
      - DATABASE_URL=sqlite:///./data/ebook_organizer.db
      - WATCH_DIR=/library/inbox
      - LIBRARY_DIR=/library
      - COVERS_DIR=/app/data/covers
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '3.0'
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      start_period: 40s
      retries: 3

  caddy:
    image: caddy:2-alpine   # Alpine has ARM64 support
    container_name: ebook_caddy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      backend:
        condition: service_healthy
    restart: unless-stopped

volumes:
  ebook_data:
  caddy_data:
  caddy_config:
```

### Step 1.3: SQLite Performance Tuning

**File to modify:** `ebook_organizer_app/backend/app/models/database.py`

**Current state:** Basic `create_engine` with only `check_same_thread=False`. No pragmas.

**Required changes — add event listener after engine creation:**

```python
from sqlalchemy import event

@event.listens_for(engine, "connect")
def set_sqlite_pragmas(dbapi_connection, connection_record):
    cursor = dbapi_connection.cursor()
    # WAL mode: allows concurrent reads during writes
    cursor.execute("PRAGMA journal_mode=WAL")
    # NORMAL sync: safe with WAL, ~2x faster than FULL
    cursor.execute("PRAGMA synchronous=NORMAL")
    # 64MB page cache (negative = KB, so -65536 = 64MB)
    cursor.execute("PRAGMA cache_size=-65536")
    # 256MB memory-mapped I/O for fast reads
    cursor.execute("PRAGMA mmap_size=268435456")
    # Enable foreign keys
    cursor.execute("PRAGMA foreign_keys=ON")
    # Temp tables in memory (faster than disk on Pi with NVMe)
    cursor.execute("PRAGMA temp_store=MEMORY")
    cursor.close()
```

**Why each pragma matters for 100k books on Pi:**
- `WAL` — critical: allows the watchdog to write new books while the web UI reads concurrently
- `synchronous=NORMAL` — safe with WAL; avoids fsync on every write (NVMe mitigates risk)
- `cache_size=-65536` — 64MB cache keeps hot index pages in memory (100k book index ≈ 20MB)
- `mmap_size=268435456` — 256MB mmap lets SQLite bypass read() syscalls; Pi 5 has plenty of RAM
- `temp_store=MEMORY` — temp query results stay in RAM instead of hitting disk

### Step 1.4: FTS5 Optimization on Startup

**File to modify:** `ebook_organizer_app/backend/app/services/search_service.py`

**Add to initialization or startup:**
```python
# Run after FTS5 table is created/verified
db.execute(text("INSERT INTO ebooks_fts(ebooks_fts) VALUES('optimize')"))
```

This merges FTS5 b-tree segments for faster queries. Should run periodically (e.g., weekly cron or on startup if >1 day since last optimize).

### Phase 1 Verification

- [ ] `docker buildx build --platform linux/arm64 -t ebook-backend .` succeeds
- [ ] Container starts on Pi 5 and `/health` returns 200
- [ ] `pytest` passes inside ARM container
- [ ] Insert 100k dummy records: `INSERT INTO ebooks (title, author, ...) SELECT ...` in a loop
- [ ] `GET /api/ebooks/search?q=python` returns in <200ms with 100k records
- [ ] `PRAGMA journal_mode` returns `wal` when querying from inside container
- [ ] Memory usage stays under 500MB at idle with 100k records

---

## Phase 2 — Watchdog Auto-Ingest

### Step 2.1: Add Dependency

**File to modify:** `ebook_organizer_app/backend/requirements.txt`

**Add:**
```
watchdog>=4.0.0
```

### Step 2.2: Add Config Settings

**File to modify:** `ebook_organizer_app/backend/app/config.py`

**Add to Settings class:**
```python
WATCH_DIR: str = "/library/inbox"        # Directory to watch for new ebooks
LIBRARY_DIR: str = "/library"            # Organized library root
COVERS_DIR: str = "./data/covers"        # Cover thumbnail storage
WATCH_DEBOUNCE_SECONDS: float = 2.0      # Wait after file creation before processing
WATCH_ENABLED: bool = True               # Toggle watcher on/off
AUTO_ORGANIZE: bool = True               # Move to organized structure after ingest
AUTO_CONVERT_MOBI: bool = True           # Convert MOBI→EPUB on ingest
```

### Step 2.3: Create Watcher Service

**File to create:** `ebook_organizer_app/backend/app/services/watcher_service.py`

**Behavior:**
1. Uses `watchdog.observers.Observer` to monitor `WATCH_DIR`
2. Listens for `FileCreatedEvent` matching extensions: `.epub`, `.pdf`, `.mobi`, `.azw`, `.azw3`
3. On event:
   a. Wait `WATCH_DEBOUNCE_SECONDS` (handles partial writes from network copies / USB transfers)
   b. Verify file is complete (check file size stability over 2 consecutive checks)
   c. Call `metadata_service.extract_metadata(file_path)` — reuse existing
   d. Call `metadata_classifier.classify(metadata)` — reuse existing
   e. If `AUTO_CONVERT_MOBI` and format is MOBI/AZW: convert to EPUB using existing conversion logic
   f. Extract cover art via cover_service (Phase 3) — skip if not yet implemented
   g. Save to database via existing DB session
   h. If `AUTO_ORGANIZE`: move file to `{LIBRARY_DIR}/{Category}/{SubGenre}/{Author}/{filename}` via `file_organizer_service`
   i. Log result (success/failure, time taken)

**Key functions:**
- `class EbookEventHandler(FileSystemEventHandler)` — handles `on_created`
- `class WatcherService` — singleton, manages Observer lifecycle
  - `start()` — creates observer, starts watching
  - `stop()` — graceful shutdown
  - `get_status()` → `{"running": bool, "watch_dir": str, "files_processed": int, "last_processed": datetime, "errors": int}`

**Error handling:**
- Catch and log individual file processing failures (don't crash the watcher)
- If a file fails, move it to `{WATCH_DIR}/_failed/` with error log
- Max retries: 3 per file, then move to failed

**Thread safety:**
- Processing runs in a thread pool (watchdog callbacks are in a separate thread)
- Use `asyncio.run_coroutine_threadsafe()` to bridge watchdog threads → FastAPI async

### Step 2.4: Create Watcher Route

**File to create:** `ebook_organizer_app/backend/app/routes/watcher.py`

**Endpoints:**
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/watcher/status` | Watcher status (running, files processed count, errors) |
| POST | `/api/watcher/start` | Start watcher if stopped |
| POST | `/api/watcher/stop` | Stop watcher |
| GET | `/api/watcher/failed` | List files that failed processing |
| POST | `/api/watcher/retry/{filename}` | Retry a failed file |

### Step 2.5: Integrate into App Lifecycle

**File to modify:** `ebook_organizer_app/backend/app/main.py`

**On startup (using lifespan context manager or `on_event`):**
```python
from app.services.watcher_service import WatcherService

watcher = WatcherService()

@app.on_event("startup")
async def start_watcher():
    if settings.WATCH_ENABLED:
        watcher.start()

@app.on_event("shutdown")
async def stop_watcher():
    watcher.stop()
```

**Register route:**
```python
from app.routes.watcher import router as watcher_router
app.include_router(watcher_router, prefix="/api/watcher", tags=["watcher"])
```

### Phase 2 Verification

- [ ] Drop `test.epub` into `WATCH_DIR` → appears in `GET /api/ebooks/` within 5s
- [ ] Drop `test.pdf` → metadata extracted, appears in DB
- [ ] Drop `test.mobi` with `AUTO_CONVERT_MOBI=True` → EPUB created alongside, both in DB
- [ ] Drop `photo.jpg` → ignored, no error
- [ ] Drop 100 EPUBs rapidly (simulate bulk USB copy) → all processed, no crashes
- [ ] Kill backend mid-processing → restart → watcher resumes, no data corruption
- [ ] `GET /api/watcher/status` returns accurate counts
- [ ] Failed file moved to `_failed/` with error log

---

## Phase 3 — Cover Art Extraction & Thumbnails

### Step 3.1: Add Dependency

**File to modify:** `ebook_organizer_app/backend/requirements.txt`

**Add:**
```
Pillow>=10.0.0
```

**ARM64 note:** Pillow has pre-built ARM64 wheels on PyPI. If compilation is needed, `libjpeg-dev`, `libwebp-dev`, `zlib1g-dev` must be in Dockerfile.

**Update Dockerfile apt-get line:**
```
libjpeg-dev libwebp-dev zlib1g-dev
```

### Step 3.2: Database Migration — Add cover_path

**File to create:** `ebook_organizer_app/backend/alembic/versions/xxxx_add_cover_path.py`

**Migration:**
```python
def upgrade():
    op.add_column('ebooks', sa.Column('cover_path', sa.String(), nullable=True))

def downgrade():
    op.drop_column('ebooks', 'cover_path')
```

**Also update:**
- `backend/app/models/database.py` — add `cover_path = Column(String, nullable=True)` to Ebook model
- `backend/app/models/schemas.py` — add `cover_path: Optional[str] = None` and computed `cover_url: Optional[str] = None` to EbookResponse

### Step 3.3: Create Cover Service

**File to create:** `ebook_organizer_app/backend/app/services/cover_service.py`

**Behavior:**

```
extract_cover(file_path: str, ebook_id: int) -> Optional[str]
```

1. **EPUB cover extraction:**
   - Open with `ebooklib.epub.read_epub()`
   - Find cover: check `<meta name="cover" content="...">` in OPF
   - Fallback: look for item with `properties="cover-image"` or media type `image/*` with "cover" in ID
   - Extract image bytes

2. **PDF cover extraction:**
   - Use `pypdf.PdfReader` → extract first page as image
   - Alternative: if PDF has embedded images in metadata, use those
   - Note: Pure `pypdf` can't render pages to images. Options:
     - **Option A:** Use `pdf2image` + `poppler-utils` (apt package, works on ARM64) — best quality
     - **Option B:** Extract embedded XObject images from first page via pypdf — lower quality but no extra deps
   - **Recommendation:** Option A with `poppler-utils` in Dockerfile

3. **MOBI cover extraction:**
   - `mobi` library extracts to temp dir → look for image files
   - Usually `cover.jpg` or first image in extracted content

4. **Thumbnail generation (all formats):**
   ```python
   from PIL import Image
   img = Image.open(raw_cover_bytes)
   img.thumbnail((400, 600), Image.LANCZOS)
   output_path = f"{COVERS_DIR}/{ebook_id}.webp"
   img.save(output_path, "WEBP", quality=80)
   return output_path
   ```

5. **Update DB:** Set `cover_path` on the ebook record

**Lazy generation pattern:**
- Covers are generated on first access OR during batch job
- `GET /api/ebooks/{id}/cover` → if cover_path exists, serve it; if not, generate on-the-fly then cache

**Batch extraction:**
```
POST /api/ebooks/extract-covers
  Body: {"ebook_ids": [1, 2, 3, ...]}  // or empty for all missing
```
- Runs as background task (like sync)
- Processes in batches of 50 to avoid memory spikes
- Reports progress via status endpoint

### Step 3.4: Mount Static Covers

**File to modify:** `ebook_organizer_app/backend/app/main.py`

```python
from fastapi.staticfiles import StaticFiles
import os

# Create covers directory if it doesn't exist
os.makedirs(settings.COVERS_DIR, exist_ok=True)

app.mount("/static/covers", StaticFiles(directory=settings.COVERS_DIR), name="covers")
```

### Step 3.5: Add Cover Endpoint

**File to modify:** `ebook_organizer_app/backend/app/routes/ebooks.py`

```python
@router.get("/{ebook_id}/cover")
async def get_ebook_cover(ebook_id: int, db: Session = Depends(get_db)):
    ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
    if not ebook:
        raise HTTPException(404, "Ebook not found")
    if ebook.cover_path and os.path.exists(ebook.cover_path):
        return FileResponse(ebook.cover_path, media_type="image/webp")
    # Generate on-the-fly
    cover_path = await cover_service.extract_cover(ebook.cloud_file_path, ebook_id)
    if cover_path:
        return FileResponse(cover_path, media_type="image/webp")
    # Return placeholder
    raise HTTPException(404, "No cover available")
```

### Phase 3 Verification

- [ ] EPUB with embedded cover → `/static/covers/{id}.webp` created, 400×600, <50KB
- [ ] PDF → first-page thumbnail generated
- [ ] MOBI → cover extracted from content
- [ ] Book without cover → 404 returned (frontend shows placeholder)
- [ ] Batch extraction of 1000 books completes without OOM (monitor `docker stats`)
- [ ] Cover directory for 100k books < 5GB disk usage
- [ ] `GET /api/ebooks/{id}/cover` returns image with correct `Content-Type: image/webp`

---

## Phase 4 — Ebook File Serving & Streaming

### Step 4.1: Add Download Endpoint

**File to modify:** `ebook_organizer_app/backend/app/routes/ebooks.py`

```python
from fastapi.responses import FileResponse

@router.get("/{ebook_id}/download")
async def download_ebook(ebook_id: int, db: Session = Depends(get_db)):
    ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
    if not ebook:
        raise HTTPException(404, "Ebook not found")

    file_path = ebook.cloud_file_path  # Local filesystem path
    if not file_path or not os.path.exists(file_path):
        raise HTTPException(404, "File not found on disk")

    filename = f"{ebook.title}.{ebook.file_format}" if ebook.title else os.path.basename(file_path)
    media_types = {
        "epub": "application/epub+zip",
        "pdf": "application/pdf",
        "mobi": "application/x-mobipocket-ebook",
    }
    media_type = media_types.get(ebook.file_format, "application/octet-stream")

    return FileResponse(
        path=file_path,
        filename=filename,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'}
    )
```

### Step 4.2: Add Streaming Endpoint (for epub.js)

**epub.js requires HTTP Range request support to progressively load chapters.**

```python
from starlette.responses import Response
from starlette.background import BackgroundTask

@router.get("/{ebook_id}/stream")
async def stream_ebook(ebook_id: int, request: Request, db: Session = Depends(get_db)):
    ebook = db.query(Ebook).filter(Ebook.id == ebook_id).first()
    if not ebook:
        raise HTTPException(404, "Ebook not found")

    file_path = ebook.cloud_file_path
    if not file_path or not os.path.exists(file_path):
        raise HTTPException(404, "File not found on disk")

    # FileResponse from Starlette supports Range requests automatically
    # when used with StaticFiles or when the client sends Range headers
    media_types = {
        "epub": "application/epub+zip",
        "pdf": "application/pdf",
        "mobi": "application/x-mobipocket-ebook",
    }
    return FileResponse(
        path=file_path,
        media_type=media_types.get(ebook.file_format, "application/octet-stream"),
        headers={
            "Accept-Ranges": "bytes",
            "Cache-Control": "public, max-age=86400",  # Cache 24h
        }
    )
```

**Note:** Starlette's `FileResponse` supports Range requests natively as of v0.27+. Verify this works by testing with:
```bash
curl -H "Range: bytes=0-1024" http://localhost:8000/api/ebooks/1/stream -I
# Should return 206 Partial Content
```

### Step 4.3: File Path Verification

**Concern:** The `ebooks` table uses `cloud_file_path` for both cloud and local paths. During local sync (`sync_service.py`), the local filesystem path is stored in `cloud_file_path` with `cloud_provider="local"`.

**Verify in:** `ebook_organizer_app/backend/app/services/sync_service.py`
- Confirm that scanning a local directory populates `cloud_file_path` with the absolute filesystem path
- Confirm that the file watcher (Phase 2) also stores the absolute path

**If paths are relative:** Resolve them against `LIBRARY_DIR` before serving.

### Step 4.4: Security — Path Traversal Prevention

**The streaming endpoint MUST validate that the resolved file path is within `LIBRARY_DIR` to prevent path traversal attacks.**

```python
real_path = os.path.realpath(file_path)
library_real = os.path.realpath(settings.LIBRARY_DIR)
if not real_path.startswith(library_real):
    raise HTTPException(403, "Access denied")
```

### Phase 4 Verification

- [ ] `GET /api/ebooks/{id}/download` → browser downloads the file
- [ ] `GET /api/ebooks/{id}/stream` with Range header → 206 Partial Content
- [ ] `GET /api/ebooks/{id}/stream` without Range → 200 OK with full file
- [ ] CORS headers allow `http://pi-ip` origin to access stream endpoint
- [ ] Non-existent file → 404 (not 500)
- [ ] Path traversal attempt (e.g., `cloud_file_path = "../../etc/passwd"`) → 403 blocked

---

## Phase 5 — Full Web UI (Library, Reader, Classification, Reorganization)

> **This is the sole user interface on the headless Pi.** All features previously available only
> in the Flutter desktop GUI must be accessible here. The web UI is the primary way users
> interact with the system from any device (laptop, phone, tablet) on the LAN.

### Design Decision: Why Not Svelte

The `grand_plan.md` suggests Svelte + TailwindCSS. However:
- Adding a Node.js build pipeline on Pi is unnecessary overhead
- The web UI needs to be **self-contained** — no build step, no Node.js runtime
- Vanilla JS + Alpine.js (14KB, no build step) + TailwindCSS (CDN) achieves this
- Alpine.js provides enough reactivity for form handling, filtering, and modals

**Can upgrade to Svelte later** if the web UI grows in complexity beyond what Alpine.js handles comfortably.

### Step 5.1: Create Web UI Directory

**Directory:** `ebook_organizer_app/backend/static/web/`

### Step 5.2: Library Page — `index.html`

**Features:**
- Responsive cover grid (CSS Grid, 3-6 columns depending on viewport)
- Search bar → calls `GET /api/ebooks/search?q=...`
- Category filter dropdown → populated from `GET /api/organization/taxonomy`
- Infinite scroll or pagination (page buttons)
- Each card: cover image (`/api/ebooks/{id}/cover`), title, author, format badge
- Click card → detail page

**Tech:**
- Alpine.js for reactivity (`x-data`, `x-for`, `x-on:click`)
- TailwindCSS CDN for styling
- `fetch()` for API calls
- Lazy loading covers with `loading="lazy"` on `<img>` tags

**Approximate size:** ~10KB HTML + ~5KB JS (before CDN deps)

### Step 5.3: Reader Page — `reader.html`

**Features:**
- Full-screen epub.js reader
- Top bar: book title, back button, theme toggle (light/dark/sepia)
- Navigation: left/right arrows, swipe on touch devices
- Progress bar at bottom
- Reading position saved to `localStorage` as CFI (Canonical Fragment Identifier)
- On load: check localStorage for saved position → restore

**epub.js integration:**
```javascript
// Load the book from streaming endpoint
const book = ePub(`/api/ebooks/${bookId}/stream`);
const rendition = book.renderTo("reader-container", {
    width: "100%",
    height: "100%",
    spread: "none"  // Single page on mobile
});

// Restore saved position
const savedCfi = localStorage.getItem(`book-${bookId}-cfi`);
if (savedCfi) {
    rendition.display(savedCfi);
} else {
    rendition.display();
}

// Save position on page turn
rendition.on("relocated", (location) => {
    localStorage.setItem(`book-${bookId}-cfi`, location.start.cfi);
});

// Arrow key navigation
rendition.on("keyup", (e) => {
    if (e.key === "ArrowLeft") rendition.prev();
    if (e.key === "ArrowRight") rendition.next();
});

// Touch swipe (for phone/tablet access to Pi)
let touchStart = null;
rendition.on("touchstart", (e) => touchStart = e.changedTouches[0].screenX);
rendition.on("touchend", (e) => {
    const diff = e.changedTouches[0].screenX - touchStart;
    if (Math.abs(diff) > 50) diff > 0 ? rendition.prev() : rendition.next();
});
```

**epub.js loading — bundle locally (no CDN dependency on Pi):**
- Download `epub.min.js` (~120KB) → `static/web/lib/epub.min.js`
- Download `jszip.min.js` (~30KB) → `static/web/lib/jszip.min.js` (epub.js peer dep)

### Step 5.4: Detail Page — `book.html`

**Features:**
- Cover image (large)
- Full metadata: title, author, ISBN, publisher, category, sub-genre, format, size, date added
- Tags list with add/remove functionality
- Buttons: "Read" (→ reader.html for EPUBs), "Download" (all formats)
- Edit metadata inline (title, author, tags — see Step 5.7)
- Related books by same author (stretch goal)

### Step 5.5: Classification Page — `classify.html`

> **Previously Flutter-only.** This replaces the Flutter `ClassificationScreen` for headless use.

**Features:**
- Table of unclassified or uncategorized ebooks (where `category` is null or "Unknown")
- For each book: title, author, current category (if any), detected category (from classifier)
- "Accept" button → applies the classifier's suggestion via `PUT /api/ebooks/{id}`
- "Override" dropdown → manually select category + sub-genre from taxonomy
- "Classify All" bulk action → calls `POST /api/metadata/classify-all` (the existing batch endpoint)
- Progress indicator for batch classification (polls status endpoint)

**API endpoints used (already exist):**
- `GET /api/ebooks/` with `?category=Unknown` or `?is_classified=false` filter
- `PUT /api/ebooks/{id}` — update category/sub-genre
- `POST /api/metadata/classify` — classify single book
- `POST /api/metadata/classify-all` — batch classify
- `GET /api/organization/taxonomy` — get category/sub-genre tree

**Alpine.js component:**
```javascript
Alpine.data('classifier', () => ({
    books: [],
    taxonomy: {},
    loading: false,
    async init() {
        this.taxonomy = await fetch('/api/organization/taxonomy').then(r => r.json());
        await this.loadUnclassified();
    },
    async loadUnclassified() {
        this.loading = true;
        this.books = await fetch('/api/ebooks/?limit=50&category=Unknown').then(r => r.json());
        this.loading = false;
    },
    async acceptSuggestion(book) {
        await fetch(`/api/metadata/classify`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ ebook_id: book.id })
        });
        await this.loadUnclassified();
    },
    async overrideCategory(book, category, subGenre) {
        await fetch(`/api/ebooks/${book.id}`, {
            method: 'PUT',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ category, sub_genre: subGenre })
        });
        await this.loadUnclassified();
    },
    async classifyAll() {
        this.loading = true;
        await fetch('/api/metadata/classify-all', { method: 'POST' });
        // Poll for completion...
        await this.loadUnclassified();
    }
}));
```

### Step 5.6: Reorganization Page — `reorganize.html`

> **Previously Flutter-only.** This replaces the Flutter `ReorganizeScreen` for headless use.

**Features:**
- Current library structure preview (tree view of `/library/` organized by category/author)
- "Preview Reorganization" → calls `POST /api/organization/preview` and shows proposed moves
- Diff-style view: current path → proposed path for each book
- "Apply" button → calls `POST /api/organization/reorganize` to execute the file moves
- Progress indicator with books processed / total count
- Option to select organization schema: `by-category`, `by-author`, `by-format`

**API endpoints used (already exist):**
- `POST /api/organization/preview` — dry run of reorganization
- `POST /api/organization/reorganize` — execute reorganization
- `GET /api/organization/taxonomy` — get taxonomy tree for display

**UI layout:**
```
┌──────────────────────────────────────────────────┐
│ Reorganize Library                                │
│                                                   │
│ Schema: [by-category ▼]  [Preview Changes]       │
│                                                   │
│ ┌───────────────────┬───────────────────────────┐│
│ │ Current Path      │ Proposed Path             ││
│ ├───────────────────┼───────────────────────────┤│
│ │ /inbox/book1.epub │ /Fiction/Sci-Fi/Author/.. ││
│ │ /inbox/book2.pdf  │ /Non-Fiction/Science/...  ││
│ │ ...               │ ...                       ││
│ └───────────────────┴───────────────────────────┘│
│                                                   │
│ 47 books will be moved.  [Apply Reorganization]  │
└──────────────────────────────────────────────────┘
```

### Step 5.7: Metadata Editor — inline in `book.html`

> **Previously Flutter-only.** This provides the edit functionality from the Flutter `EbookDetailScreen`.

**Features:**
- Toggle between "view" and "edit" mode on the detail page
- Editable fields: title, author, ISBN, publisher, description, category, sub-genre
- Tag management: add new tags, remove existing tags
- "Save" → `PUT /api/ebooks/{id}` with updated fields
- "Re-extract Metadata" → `POST /api/metadata/extract/{id}` to re-read from file
- "Re-classify" → `POST /api/metadata/classify` with the book's ID
- Validation: required fields (title), format checks (ISBN)

**Alpine.js component:**
```javascript
Alpine.data('metadataEditor', () => ({
    book: null,
    editing: false,
    form: {},
    saving: false,
    async init() {
        const id = new URLSearchParams(location.search).get('id');
        this.book = await fetch(`/api/ebooks/${id}`).then(r => r.json());
        this.form = { ...this.book };
    },
    startEditing() { this.editing = true; this.form = { ...this.book }; },
    cancelEditing() { this.editing = false; },
    async save() {
        this.saving = true;
        await fetch(`/api/ebooks/${this.book.id}`, {
            method: 'PUT',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(this.form)
        });
        this.book = await fetch(`/api/ebooks/${this.book.id}`).then(r => r.json());
        this.editing = false;
        this.saving = false;
    },
    async reExtract() {
        await fetch(`/api/metadata/extract/${this.book.id}`, { method: 'POST' });
        this.book = await fetch(`/api/ebooks/${this.book.id}`).then(r => r.json());
    },
    async reClassify() {
        await fetch(`/api/metadata/classify`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ ebook_id: this.book.id })
        });
        this.book = await fetch(`/api/ebooks/${this.book.id}`).then(r => r.json());
    }
}));
```

### Step 5.8: Library Stats Dashboard — `stats.html`

> **Previously only available via Flutter's `LibraryProvider`.** Provides an overview of the library.

**Features:**
- Total books count, total size, format breakdown (pie chart or bar)
- Category distribution (how many books per Fiction/Non-Fiction, per sub-genre)
- Recently added books (last 7 days)
- Watcher status: active/paused, files in inbox queue, last ingested file
- Storage usage: library dir size, covers dir size, DB size
- Quick actions: "Classify All Unclassified", "Optimize Search Index"

**API endpoints used:**
- `GET /api/ebooks/stats` — aggregate counts (may need to add this endpoint)
- `GET /api/ebooks/?sort=created_at&order=desc&limit=10` — recently added
- `GET /api/watcher/status` — watcher status (from Phase 2)
- `GET /api/organization/taxonomy` — for category breakdown

**New endpoint needed (simple):**
```python
# In ebook_organizer_app/backend/app/routes/ebooks.py
@router.get("/stats")
async def get_library_stats(db: Session = Depends(get_db)):
    total = db.query(func.count(Ebook.id)).scalar()
    total_size = db.query(func.sum(Ebook.file_size)).scalar() or 0
    formats = db.query(Ebook.file_format, func.count(Ebook.id)).group_by(Ebook.file_format).all()
    categories = db.query(Ebook.category, func.count(Ebook.id)).group_by(Ebook.category).all()
    return {
        "total_books": total,
        "total_size_bytes": total_size,
        "formats": {fmt: count for fmt, count in formats},
        "categories": {cat or "Uncategorized": count for cat, count in categories},
    }
```

### Step 5.9: Navigation — Shared Layout

All pages share a common navigation header:
```html
<nav class="bg-gray-800 text-white p-4 flex gap-4">
    <a href="/web/" class="hover:underline">📚 Library</a>
    <a href="/web/classify.html" class="hover:underline">🏷️ Classify</a>
    <a href="/web/reorganize.html" class="hover:underline">📁 Reorganize</a>
    <a href="/web/stats.html" class="hover:underline">📊 Stats</a>
</nav>
```

Extract into a `nav.html` fragment loaded via `fetch()` + `innerHTML`, or simply duplicate in each page (only 4 lines).

### Step 5.10: Mount Web UI in FastAPI

**File to modify:** `ebook_organizer_app/backend/app/main.py`

```python
# Serve web UI (must be after API routes to avoid conflicts)
app.mount("/web", StaticFiles(directory="static/web", html=True), name="web-ui")
```

**`html=True`** enables `index.html` fallback (SPA-like routing).

### Step 5.11: CORS Update

**File to modify:** `ebook_organizer_app/backend/app/main.py`

Current CORS allows `localhost` patterns only. For Pi LAN access, update:
```python
allow_origins=[
    "http://localhost:*",
    "http://127.0.0.1:*",
    "http://192.168.*.*",   # Local network
    "http://pi-hostname",    # mDNS name
]
```
Or use `allow_origins=["*"]` for local-only Pi (no internet exposure).

### Phase 5 Verification

- [ ] `http://pi-ip:8000/web/` → library grid loads with covers
- [ ] Search "python" → filtered results appear
- [ ] Category filter → books filtered by category
- [ ] Click book → detail page with metadata
- [ ] Click "Read" on EPUB → epub.js renders book
- [ ] Swipe left/right → pages turn
- [ ] Close browser, reopen same book → reading position restored
- [ ] Access from phone on same WiFi → responsive layout works
- [ ] PDF books show download button only (no epub.js reader for PDF)
- [ ] Page loads in <2s on LAN (total asset size <200KB excluding covers)
- [ ] **Classify page:** shows unclassified books, "Accept" applies suggestion
- [ ] **Classify page:** "Override" lets user pick category/sub-genre from taxonomy dropdown
- [ ] **Classify page:** "Classify All" triggers batch classification with progress
- [ ] **Reorganize page:** "Preview" shows proposed file moves
- [ ] **Reorganize page:** "Apply" executes reorganization, files move on disk
- [ ] **Metadata editor:** toggle edit mode on detail page, save changes persisted
- [ ] **Metadata editor:** "Re-extract" and "Re-classify" buttons work
- [ ] **Stats page:** shows total books, format breakdown, category distribution
- [ ] **Stats page:** watcher status displays (active/paused, queue count)
- [ ] **Navigation:** all pages reachable from shared nav bar

---

## Phase 6 — Infrastructure & Production Deployment

### Step 6.1: Caddyfile

**File to create:** `ebook_organizer_app/Caddyfile`

```caddyfile
:80 {
    # API proxy
    handle /api/* {
        reverse_proxy backend:8000
    }

    # Health endpoint
    handle /health {
        reverse_proxy backend:8000
    }

    # Swagger docs
    handle /docs* {
        reverse_proxy backend:8000
    }
    handle /redoc* {
        reverse_proxy backend:8000
    }
    handle /openapi.json {
        reverse_proxy backend:8000
    }

    # Static covers
    handle /static/* {
        reverse_proxy backend:8000
    }

    # Web UI (default)
    handle /web/* {
        reverse_proxy backend:8000
    }

    # Root → redirect to web UI
    handle / {
        redir /web/ permanent
    }

    # Compression
    encode gzip

    # Logging
    log {
        output file /data/access.log
        format json
    }
}
```

### Step 6.2: Systemd Service (Non-Docker Alternative)

**File to create:** `ebook_organizer_app/deploy/ebook-organizer.service`

```ini
[Unit]
Description=eBook Organizer Backend
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/ebook-organizer/backend
ExecStart=/opt/ebook-organizer/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5
Environment=DATABASE_URL=sqlite:///./data/ebook_organizer.db
Environment=WATCH_DIR=/mnt/library/inbox
Environment=LIBRARY_DIR=/mnt/library
Environment=COVERS_DIR=./data/covers

[Install]
WantedBy=multi-user.target
```

**Install:**
```bash
sudo cp deploy/ebook-organizer.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ebook-organizer
sudo systemctl start ebook-organizer
```

### Step 6.3: Pi Storage Setup

**Recommended layout (NVMe SSD):**
```
/mnt/library/                   # Mount point for NVMe SSD
├── inbox/                      # Watchdog monitored folder (drop ebooks here)
├── Fiction/                    # Organized by file_organizer_service
│   ├── Fantasy/
│   │   └── Brandon Sanderson/
│   │       └── The Way of Kings.epub
│   └── Science Fiction/
│       └── ...
├── Non-Fiction/
│   └── ...
└── Unclassified/

/opt/ebook-organizer/           # Application
├── backend/                    # Python backend code
├── venv/                       # Python virtual environment
└── data/
│   ├── ebook_organizer.db      # SQLite database
│   ├── ebook_organizer.db-wal  # WAL file
│   └── covers/                 # WebP thumbnails
│       ├── 1.webp
│       ├── 2.webp
│       └── ...
```

**fstab entry for NVMe SSD:**
```
/dev/nvme0n1p1  /mnt/library  ext4  defaults,noatime  0  2
```

(`noatime` avoids unnecessary access time writes → better SSD longevity)

### Step 6.4: Backup Strategy

**Daily SQLite backup script (`/opt/ebook-organizer/backup.sh`):**
```bash
#!/bin/bash
BACKUP_DIR="/mnt/library/_backups"
DB_PATH="/opt/ebook-organizer/data/ebook_organizer.db"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"
sqlite3 "$DB_PATH" ".backup '$BACKUP_DIR/ebook_organizer_$DATE.db'"

# Keep only last 7 daily backups
find "$BACKUP_DIR" -name "ebook_organizer_*.db" -mtime +7 -delete
```

**Cron:**
```
0 3 * * * /opt/ebook-organizer/backup.sh
```

### Step 6.5: Monitoring

**Minimal monitoring for Pi:**
- Backend health: `curl http://localhost:8000/health` in cron → alert on failure
- Disk space: alert when SSD is >80% full
- Temperature: `vcgencmd measure_temp` → alert if >75°C

### Phase 6 Verification

- [ ] `docker compose up -d` starts backend + Caddy on Pi
- [ ] `http://pi-ip/` redirects to `/web/`
- [ ] `http://pi-ip/api/ebooks/` works through Caddy
- [ ] `http://pi-ip/docs` shows Swagger UI
- [ ] Reboot Pi → services auto-start within 60s
- [ ] Backup cron produces valid SQLite backup file
- [ ] Access from phone on same WiFi works
- [ ] 24h stability test: no OOM, no crashes, temp stays <70°C

---

## Appendix A — Full File Inventory

### Files to Modify

| File | Phase | Changes |
|------|-------|---------|
| `backend/Dockerfile` | 1 | ARM64 base image, build deps, remove --reload |
| `docker-compose.yml` | 1, 6 | Resource limits, volumes, Caddy service |
| `backend/app/models/database.py` | 1, 3 | SQLite pragmas, add cover_path column |
| `backend/app/models/schemas.py` | 3 | Add cover_path/cover_url to EbookResponse |
| `backend/app/main.py` | 2, 3, 5 | Mount static files, start watcher, register routes, CORS update |
| `backend/app/config.py` | 2 | Add WATCH_DIR, LIBRARY_DIR, COVERS_DIR, WATCH_ENABLED, AUTO_ORGANIZE, AUTO_CONVERT_MOBI |
| `backend/requirements.txt` | 2, 3 | Add watchdog, Pillow |
| `backend/app/routes/ebooks.py` | 3, 4 | Add cover, download, stream endpoints |
| `backend/app/services/search_service.py` | 1 | Add FTS5 optimize on startup |
| `backend/app/services/metadata_service.py` | 2 | (May need minor changes to integrate with watcher pipeline) |
| `backend/app/services/sync_service.py` | 2 | (Verify local path storage behavior) |

### Files to Create

| File | Phase | Purpose |
|------|-------|---------|
| `backend/app/services/watcher_service.py` | 2 | Watchdog file watcher service |
| `backend/app/services/cover_service.py` | 3 | Cover extraction + thumbnail generation |
| `backend/app/routes/watcher.py` | 2 | Watcher control API |
| `backend/alembic/versions/xxxx_add_cover_path.py` | 3 | DB migration for cover_path |
| `backend/static/web/index.html` | 5 | Library browser page |
| `backend/static/web/book.html` | 5 | Book detail page |
| `backend/static/web/reader.html` | 5 | epub.js reader page |
| `backend/static/web/app.js` | 5 | Shared JS (API calls, Alpine.js components) |
| `backend/static/web/style.css` | 5 | Custom styles beyond Tailwind |
| `backend/static/web/lib/epub.min.js` | 5 | epub.js library (bundled, ~120KB) |
| `backend/static/web/lib/jszip.min.js` | 5 | JSZip (epub.js dependency, ~30KB) |
| `backend/static/web/classify.html` | 5 | Classification page |
| `backend/static/web/reorganize.html` | 5 | Library reorganization page |
| `backend/static/web/stats.html` | 5 | Library stats dashboard |
| `Caddyfile` | 6 | Reverse proxy configuration |
| `docker-compose.pi.yml` | 6 | Pi-specific Docker Compose (optional) |
| `deploy/ebook-organizer.service` | 6 | Systemd unit file |
| `deploy/backup.sh` | 6 | Daily backup script |

### Files to Reference (Reuse Patterns From)

| File | Reuse For |
|------|-----------|
| `backend/app/services/file_organizer_service.py` | Path generation in watcher's post-ingest move |
| `backend/app/services/metadata_classifier.py` | Classification pipeline that watcher feeds into |
| `backend/app/services/search_service.py` | FTS5 setup pattern for web UI search API calls |
| `backend/app/services/sync_service.py` | Background task pattern for batch operations |
| `backend/app/routes/sync.py` | Route pattern for watcher.py (background task + status) |

---

## Appendix B — Dependency Audit

### Current Dependencies (ARM64 Compatibility)

| Package | Version | ARM64 | Notes |
|---------|---------|-------|-------|
| fastapi | 0.109.0 | ✅ Pure Python | |
| uvicorn[standard] | 0.27.0 | ⚠️ | `uvloop` needs compilation; can install without [standard] on ARM |
| pydantic | 2.5.3 | ✅ | Rust-based core has ARM64 wheels |
| sqlalchemy | 2.0.25 | ✅ Pure Python | |
| alembic | 1.13.1 | ✅ Pure Python | |
| ebooklib | >=0.18 | ✅ Pure Python | |
| pypdf | >=4.0.0 | ✅ Pure Python | |
| mobi | >=0.3.3 | ✅ Pure Python | |
| python-jose[cryptography] | 3.3.0 | ⚠️ | `cryptography` needs Rust compiler or pre-built wheel |
| passlib[bcrypt] | 1.7.4 | ⚠️ | `bcrypt` needs compilation |
| httpx | >=0.27.0 | ✅ Pure Python | |
| google-api-python-client | 2.116.0 | ✅ Pure Python | |
| msal | 1.26.0 | ✅ Pure Python | |

### New Dependencies to Add

| Package | Version | ARM64 | Purpose | Phase |
|---------|---------|-------|---------|-------|
| watchdog | >=4.0.0 | ✅ | Wheels available; uses inotify on Linux (native) | 2 |
| Pillow | >=10.0.0 | ✅ | ARM64 wheels on PyPI; may need libjpeg-dev | 3 |
| pdf2image | >=1.16.0 | ✅ Pure Python | PDF→image for covers; requires poppler-utils apt | 3 (optional) |

### System Packages Needed in Dockerfile

```
build-essential python3-dev     # For compiling cryptography, bcrypt
libsqlite3-dev                  # Ensure FTS5 support in SQLite
curl                            # Health check
libjpeg-dev libwebp-dev zlib1g-dev  # Pillow image format support
poppler-utils                   # pdf2image backend (optional, for PDF covers)
```

---

## Appendix C — Decisions Log

| # | Decision | Rationale | Alternative Considered |
|---|----------|-----------|----------------------|
| 1 | **Web UI: Vanilla JS + Alpine.js** (not Svelte) | No build pipeline needed; ultra-light (~15KB); Pi serves static files directly | Svelte (requires Node.js build step; overkill for the page count) |
| 2 | **Headless deployment — web UI only** | Pi runs headless (no display); saves ~1GB RAM (no desktop + Flutter); web UI serves all devices on LAN; simpler deployment | Flutter desktop on Pi (requires desktop environment, Dart VM ~200MB, GTK deps, display) |
| 3 | **epub.js as the primary reader** | Headless Pi has no local GUI; epub.js provides in-browser EPUB reading from any device | Dart epub renderer (complex, requires Flutter), Calibre web (heavy, different stack) |
| 4 | **Docker primary, systemd secondary** | Docker isolates deps cleanly; systemd as escape hatch for power users | Native-only (fragile dep management on Pi OS) |
| 5 | **Cloud sync deferred** | Pi is a local device; cloud scaffolding exists for later | Prioritize cloud (adds complexity, not core to Pi use case) |
| 6 | **Cover format: WebP** | Best compression at quality (20-50KB per cover); browser support universal | JPEG (larger files), PNG (much larger), AVIF (limited browser support) |
| 7 | **PDF covers via pdf2image + poppler** | Best quality page rendering; poppler has ARM64 apt package | pypdf XObject extraction (lower quality, no extra deps) |
| 8 | **MOBI auto-convert to EPUB on ingest** | No browser MOBI reader exists; conversion service already works | Keep MOBI as-is (can't read in browser) |
| 9 | **Reading progress in localStorage** | Simplest; no backend changes needed; per-device (acceptable for Pi use) | Store in DB (syncs across devices but adds API + schema complexity) |
| 10 | **SQLite WAL mode** | Essential for concurrent read/write (watcher writes while web UI reads) | Default journal mode (blocks readers during writes) |
| 11 | **256MB mmap for SQLite** | Pi 5 8GB has plenty of RAM; dramatically speeds up read-heavy workloads | Default (no mmap; slower for 100k records) |
| 12 | **NVMe SSD recommended** | 100k ebooks + covers + DB = 500GB+; microSD too slow for batch ingest | MicroSD (slower, less durable, cheaper) |
| 13 | **Web UI handles classification + reorganization** | Headless eliminates Flutter screens; web UI must be feature-complete sole interface | Defer to CLI scripts (poor UX), or keep Flutter on a separate machine (split management) |

---

## Implementation Order & Dependencies

```
Phase 1 (ARM + SQLite)
    │
    └── Phase 2 (Watchdog) ──┐
                              ├── Phase 3 (Covers) ──┐
                              │                       │
                              │   Phase 4 (Streaming) ┤
                              │                       │
                              └───────────────────────┴── Phase 5 (Full Web UI)
                                                              │
                                                              └── Phase 6 (Infrastructure)
```

- **Phase 1** is the foundation — everything else depends on it
- **Phase 2** (watchdog) enables automated ingest — prerequisite for Phases 3-5
- **Phase 3** (covers) depends on Phase 2 (integration into ingest pipeline)
- **Phase 4** (streaming) is independent but needed before Phase 5
- **Phase 5** (web UI) depends on Phases 3 + 4 (covers + streaming must work); this is the **sole user interface**
- **Phase 6** wraps everything together for production deployment

---

## Further Considerations

1. **PDF reading in browser**: epub.js only handles EPUB. Add Mozilla's pdf.js (~500KB) alongside. **Recommendation: add pdf.js in Phase 5 alongside epub.js** — essential for headless since there's no desktop fallback.

2. **MOBI auto-conversion**: No browser MOBI reader exists. The conversion service already converts MOBI→EPUB. **Recommendation: add auto-convert step to watchdog pipeline (Phase 2, Step 2.3e).**

3. **100k initial import**: First-time ingestion of 100k ebooks will take significant time (metadata extraction + classification + cover generation). **Recommendation: batch import mode** with progress tracking and pause/resume, extending the existing sync service's background task pattern. The stats dashboard (Step 5.8) should show import progress.

4. **Flutter GUI on development machines**: The Flutter desktop app remains fully functional for use on Windows/Linux/Mac development machines — it simply is not deployed on the Pi. No Flutter code needs to be removed from the repo; it coexists alongside the headless Pi deployment.

5. **Multi-device reading progress sync**: With headless deployment, multiple family members may read from different devices. `localStorage`-based progress (Decision #9) is per-device. Consider adding optional server-side reading progress storage in a future phase if cross-device sync is needed.
