# Ebook Organizer

A cross-platform desktop ebook organizer with metadata extraction, taxonomy-based classification, file reorganization, and cloud storage integration scaffolding.

## Architecture

**Flutter Frontend + FastAPI Backend**

- **Frontend**: Flutter (Windows, Linux, Web) — Material Design 3 with light/dark theme
- **Backend**: FastAPI (Python) — metadata extraction, classification, file organization, local folder sync
- **Database**: SQLite with FTS5 full-text search (backend) + sqflite (frontend local cache)
- **Cloud**: Google Drive & OneDrive integration (scaffolded, OAuth not yet implemented)

The Flutter app **auto-starts the Python backend** as a child process on launch (desktop platforms).

## Features

- Multi-platform support (Windows, Linux, Web)
- Local folder scanning with background sync
- Metadata extraction for EPUB, PDF, MOBI/AZW/AZW3 formats
- Multi-strategy classification (embedded metadata → folder-based → Open Library API → title keywords)
- Hierarchical taxonomy system (Category → SubGenre → Author)
- File reorganization into `Category/SubGenre/Author/` folder structure (preview + execute)
- MOBI/AZW/AZW3 to EPUB conversion (pure Python, no Calibre needed)
- Full-text search with FTS5 and autocomplete suggestions
- Library statistics dashboard
- Metadata read/write (EPUB & PDF writable; MOBI read-only)
- Batch classification of multiple ebooks
- Light/dark theme with persistence
- Responsive Material Design 3 UI

### Not Yet Implemented
- Google Drive / OneDrive OAuth authentication
- Cloud file sync (local scan works; cloud sync endpoints are scaffolded)

## Quick Start

### Option 1: Launcher Scripts (Recommended)

**Windows:**
```batch
cd ebook_organizer_app
start.bat
```

**Linux/Mac:**
```bash
cd ebook_organizer_app
chmod +x start.sh
./start.sh
```

These scripts set up a Python venv, install dependencies, start the backend, then launch the Flutter app.

### Option 2: Docker (Backend Only)

```bash
cd ebook_organizer_app
docker-compose up -d

# Backend available at:
#   API: http://localhost:8000
#   Docs: http://localhost:8000/docs
#   Health: http://localhost:8000/health
```

Then run the Flutter frontend separately:
```bash
cd ebook_organizer_gui
flutter pub get
flutter run -d windows   # or -d linux, -d chrome
```

### Option 3: Manual Setup

**1. Start Backend**
```bash
cd ebook_organizer_app/backend
python -m venv venv
# Windows: venv\Scripts\activate
# Linux/Mac: source venv/bin/activate
pip install -r requirements.txt
python run.py
```

**2. Start Frontend** (in a new terminal)
```bash
cd ebook_organizer_app/ebook_organizer_gui
flutter pub get
flutter run -d windows   # or -d linux, -d chrome
```

### Option 4: Make Commands

```bash
cd ebook_organizer_app
make help          # View all available commands
make install       # Install Python + Flutter deps
make setup         # install + init DB
make dev           # Run backend + Flutter in parallel
make backend       # Run backend only
make flutter       # Run Flutter app only
make test          # Run pytest
make docker-up     # Start Docker containers
make docker-down   # Stop Docker containers
```

## Prerequisites

- **Python**: 3.10+ ([Install Python](https://python.org))
- **Flutter SDK**: 3.9+ ([Install Flutter](https://flutter.dev/docs/get-started/install))
- **Git**: For version control

## Project Structure

```
ebook_organizer_app/
├── backend/                    # FastAPI Backend
│   ├── app/
│   │   ├── main.py            # FastAPI app, CORS, lifespan, route mounting
│   │   ├── config.py          # Pydantic settings (.env support)
│   │   ├── middleware.py       # Request logging middleware
│   │   ├── models/
│   │   │   ├── database.py    # SQLAlchemy models (Ebook, Tag, SyncLog, CloudConfig)
│   │   │   └── schemas.py     # Pydantic request/response schemas
│   │   ├── routes/
│   │   │   ├── ebooks.py      # CRUD, search, stats
│   │   │   ├── cloud.py       # Cloud provider status
│   │   │   ├── metadata.py    # Read/write/classify metadata
│   │   │   ├── sync.py        # Local folder sync
│   │   │   ├── conversion.py  # MOBI→EPUB conversion
│   │   │   └── organization.py # Taxonomy, classification, file reorganization
│   │   └── services/
│   │       ├── database.py           # DB engine, session, FTS5 init
│   │       ├── metadata_service.py   # EPUB/PDF/MOBI metadata read/write
│   │       ├── metadata_classifier.py # Multi-strategy classification
│   │       ├── taxonomy.py           # Category/SubGenre taxonomy tree
│   │       ├── organization_service.py # Batch classify, browse, stats
│   │       ├── file_organizer_service.py # File move/copy reorganization
│   │       ├── sync_service.py       # Local folder scan + DB insert
│   │       ├── search_service.py     # FTS5 full-text search
│   │       └── openlibrary_service.py # Open Library API integration
│   ├── tests/                  # pytest tests
│   ├── docs/                   # API.md, DEVELOPMENT.md
│   ├── requirements.txt
│   ├── Dockerfile
│   └── run.py
│
├── ebook_organizer_gui/       # Flutter Frontend
│   ├── lib/
│   │   ├── main.dart          # App entry point, backend auto-start, MultiProvider
│   │   ├── models/            # Ebook, LocalEbook, LibraryStats, CloudProvider, EbookFileData
│   │   ├── providers/         # EbookProvider, LibraryProvider, LocalLibraryProvider, ThemeProvider
│   │   ├── screens/           # Home, LocalLibrary, EbookDetail, Classification, Reorganize
│   │   ├── services/          # API, Backend, Database, Metadata, Conversion, LocalLibrary
│   │   └── widgets/           # EbookCard, Grid, SearchBar, FilterChips, StatsDashboard, Skeletons
│   └── pubspec.yaml
│
├── docker-compose.yml         # Docker orchestration
├── Makefile                   # Build automation
├── start.bat                  # Windows launcher
└── start.sh                   # Linux/Mac launcher

online-library-organizer/      # Standalone Python CLI organizer (plan-based workflow)
```

## API Endpoints

Once the backend is running, interactive docs are at:
- **Swagger UI**: http://127.0.0.1:8000/docs
- **ReDoc**: http://127.0.0.1:8000/redoc

| Group | Method | Path | Description |
|-------|--------|------|-------------|
| Health | GET | `/` | API status |
| Health | GET | `/health` | Detailed health (DB, services) |
| Ebooks | GET | `/api/ebooks/` | List with filters & pagination |
| Ebooks | GET | `/api/ebooks/search` | FTS5 full-text search |
| Ebooks | GET | `/api/ebooks/search/suggestions` | Autocomplete suggestions |
| Ebooks | GET | `/api/ebooks/{id}` | Get single ebook |
| Ebooks | PATCH | `/api/ebooks/{id}` | Update metadata |
| Ebooks | DELETE | `/api/ebooks/{id}` | Delete from local DB |
| Ebooks | GET | `/api/ebooks/stats/library` | Library statistics |
| Cloud | GET | `/api/cloud/providers` | Cloud provider status |
| Cloud | POST | `/api/cloud/providers/{provider}/authenticate` | Initiate OAuth (not yet implemented) |
| Cloud | POST | `/api/cloud/providers/{provider}/disconnect` | Disconnect provider |
| Metadata | GET | `/api/metadata/read` | Read ebook metadata from file |
| Metadata | PUT | `/api/metadata/write` | Write metadata to file (EPUB/PDF) |
| Metadata | GET | `/api/metadata/supported-formats` | Supported formats & capabilities |
| Metadata | POST | `/api/metadata/classify` | Classify an ebook file |
| Metadata | POST | `/api/metadata/extract-comprehensive` | Full extraction + classification |
| Sync | POST | `/api/sync/trigger` | Trigger local folder scan |
| Sync | GET | `/api/sync/status` | Sync progress status |
| Conversion | POST | `/api/conversion/mobi-to-epub` | Convert MOBI/AZW to EPUB |
| Conversion | GET | `/api/conversion/check-requirements` | Check conversion libraries |
| Organization | GET | `/api/organization/taxonomy` | Full taxonomy tree |
| Organization | GET | `/api/organization/stats` | Classification coverage stats |
| Organization | GET | `/api/organization/preview` | Preview classification (dry run) |
| Organization | POST | `/api/organization/classify/{id}` | Classify single ebook |
| Organization | POST | `/api/organization/batch-classify` | Batch classify ebooks |
| Organization | PUT | `/api/organization/classify/{id}` | Manual classification update |
| Organization | GET | `/api/organization/browse` | Browse by category/sub-genre |
| Organization | GET | `/api/organization/unclassified` | List unclassified ebooks |
| Organization | POST | `/api/organization/reorganize-preview` | Preview file reorganization |
| Organization | POST | `/api/organization/reorganize` | Execute file reorganization |

## Supported Ebook Formats

| Format | Read Metadata | Write Metadata | Convert To EPUB |
|--------|:---:|:---:|:---:|
| EPUB | ✅ | ✅ | — |
| PDF | ✅ | ✅ | — |
| MOBI | ✅ | ❌ | ✅ |
| AZW / AZW3 | ✅ | ❌ | ✅ |
| FB2 | ✅ | ❌ | — |

## Configuration

Edit `backend/app/config.py` or create `backend/.env`:

```env
API_HOST=127.0.0.1
API_PORT=8000
DEBUG=True
DATABASE_URL=sqlite:///./ebook_organizer.db
SUPPORTED_FORMATS=["epub","pdf","mobi","azw","azw3","fb2"]
MAX_FILE_SIZE_MB=100

# Cloud (not yet functional)
GOOGLE_DRIVE_CREDENTIALS_FILE=credentials_google.json
ONEDRIVE_CLIENT_ID=
ONEDRIVE_CLIENT_SECRET=
```

## Docker Services

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| `backend` | `ebook_organizer_backend` | 8000 | FastAPI with hot-reload, auto-restart, healthcheck |
| `flutter-builder` | — | — | Build Flutter Linux release (activated via `--profile build`) |

## Development

### Running Tests
```bash
cd ebook_organizer_app/backend
pytest
```

Tests cover API endpoints, metadata classifier, and taxonomy system.

### Logging
The backend uses structured logging with console output, JSON file logs, and a separate error log (see `backend/app/logging_config.py`).

## Technology Stack

**Frontend:**
- Flutter SDK ^3.9.2
- Material Design 3 (light/dark theme)
- Provider (state management)
- sqflite / sqflite_common_ffi (local database)
- http + dio (API clients)
- file_picker (folder selection)
- archive + xml (client-side EPUB metadata)
- process_run (backend process management)

**Backend:**
- Python 3.10+ (Docker uses 3.11)
- FastAPI 0.109.0
- SQLAlchemy 2.0 (ORM) + Alembic (migrations)
- Pydantic 2.x + pydantic-settings
- ebooklib, pypdf, mobi (metadata extraction)
- Open Library API (metadata enrichment)
- SQLite FTS5 (full-text search)

## Troubleshooting

### Backend won't start
- Check Python version: `python --version` (need 3.10+)
- Install dependencies: `pip install -r requirements.txt`
- Check port 8000 is not in use

### Flutter won't run
- Check Flutter: `flutter doctor`
- Get dependencies: `flutter pub get`
- Enable desktop: `flutter config --enable-windows-desktop`

### Database issues
- Delete `ebook_organizer.db` to reset
- Check file permissions

## Contributing

Areas that need work:
1. Google Drive / OneDrive OAuth implementation
2. Cloud file sync (backend endpoints are scaffolded)
3. Additional ebook format support
4. UI/UX improvements
