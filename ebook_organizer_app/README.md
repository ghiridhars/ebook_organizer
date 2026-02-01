# Ebook Organizer - Multi-Platform Application

A modern, cross-platform ebook organizer with cloud storage integration (Google Drive & OneDrive).

## Architecture

**Flutter Frontend + FastAPI Backend**

- **Frontend**: Flutter (supports Windows, Linux, Web)
- **Backend**: FastAPI (Python) - handles cloud storage, metadata extraction
- **Database**: SQLite (local caching for offline mode)
- **Cloud**: Google Drive & OneDrive integration

## 🚀 Quick Start

### Option 1: Docker (Recommended)

```bash
# Start the backend service
docker-compose up -d

# The backend will be available at:
# - API: http://localhost:8000
# - API Documentation: http://localhost:8000/docs
# - Health Check: http://localhost:8000/health
```

### Option 2: Manual Setup

**1. Start Backend**
```bash
cd backend
pip install -r requirements.txt
python run.py
```

**2. Start Frontend** (in new terminal)
```bash
cd ebook_organizer_gui
flutter pub get

# Windows
flutter run -d windows

# Linux  
flutter run -d linux

# Web
flutter run -d chrome
```

### Option 3: Make Commands

```bash
# View all available commands
make help

# Install dependencies locally
make install

# Run backend locally
make backend

# Run Flutter app locally (separate terminal)
make flutter

# Run both backend and Flutter in parallel
make dev
```

## 📦 Docker Services

### Backend Service
- **Container**: `ebook_organizer_backend`
- **Port**: 8000
- **Auto-restart**: Yes
- **Hot-reload**: Enabled (dev mode)

### Flutter Builder Service
- **Purpose**: Build Flutter apps in containerized environment
- **Usage**: `make docker-flutter` or `docker-compose --profile build run flutter-builder`

## Project Structure

```
ebook_organizer_app/
├── backend/                    # FastAPI Backend
│   ├── app/
│   │   ├── main.py            # FastAPI application entry
│   │   ├── config.py          # Configuration
│   │   ├── models/            # Database & API models
│   │   ├── routes/            # API endpoints
│   │   ├── services/          # Business logic
│   │   └── utils/             # Utilities
│   └── requirements.txt       # Python dependencies
│
├── ebook_organizer_gui/       # Flutter Frontend
│   ├── lib/
│   │   ├── main.dart          # App entry point + backend auto-start
│   │   ├── models/            # Data models
│   │   ├── services/          # API client, database, backend manager
│   │   ├── providers/         # State management
│   │   ├── screens/           # UI screens
│   │   └── widgets/           # Reusable UI components
│   └── pubspec.yaml           # Flutter dependencies
│
├── docker-compose.yml         # Docker orchestration
├── Makefile                   # Build automation
├── start.bat / start.sh       # Cross-platform launchers
└── README.md                  # This file
```

## API Documentation

Once backend is running, visit:
- Swagger UI: http://127.0.0.1:8000/docs
- ReDoc: http://127.0.0.1:8000/redoc

### Key API Endpoints

- `GET /api/ebooks/` - List ebooks with filters
- `GET /api/ebooks/{id}` - Get single ebook
- `PATCH /api/ebooks/{id}` - Update ebook metadata
- `GET /api/ebooks/stats/library` - Library statistics
- `GET /api/cloud/providers` - Cloud provider status
- `POST /api/sync/trigger` - Trigger cloud sync

## Development

### Backend Development
```bash
cd backend
pip install -r requirements.txt
python run.py  # Auto-reload enabled
```

### Frontend Development
```bash
cd ebook_organizer_gui
flutter run  # Hot reload enabled
```

## Configuration

### Backend Configuration
Edit `backend/app/config.py` or create `backend/.env` file:

```env
API_HOST=127.0.0.1
API_PORT=8000
DEBUG=True
DATABASE_URL=sqlite:///./ebook_organizer.db
```

### Cloud Storage Setup (Coming Soon)
- Google Drive: OAuth credentials needed
- OneDrive: Microsoft App registration needed

## Troubleshooting

### Backend won't start
- Check Python version: `python --version` (need 3.8+)
- Install dependencies: `pip install -r requirements.txt`
- Check port 8000 is not in use

### Flutter won't run
- Check Flutter installation: `flutter doctor`
- Get dependencies: `flutter pub get`
- Enable desktop support: `flutter config --enable-windows-desktop` (Windows)

### Database issues
- Delete `ebook_organizer.db` to reset
- Check file permissions

## Technology Stack

**Frontend:**
- Flutter 3.35.6
- Material Design 3
- Provider (state management)
- sqflite (local database)
- http/dio (API client)

**Backend:**
- FastAPI 0.109.0
- SQLAlchemy (ORM)
- Pydantic (validation)
- Google/Microsoft APIs (cloud storage)

## Contributing

This is a work in progress. Key areas to contribute:
1. Cloud storage integration (Google Drive/OneDrive)
2. OAuth implementation
3. Metadata extraction enhancement
4. UI/UX improvements

## Next Steps

1. **Quick Start**: Run `docker-compose up -d` and visit http://localhost:8000/docs
2. **Test Flutter app**: `cd ebook_organizer_gui && flutter run`
3. **Implement cloud storage**: Add OAuth for Google Drive/OneDrive
4. **Integrate metadata extraction**: Port existing Python code
5. **Production deployment**: Configure environment variables
│   │   ├── models/            # Data models
│   │   ├── services/          # API & database services
│   │   ├── providers/         # State management
│   │   ├── screens/           # UI screens
│   │   └── widgets/           # Reusable widgets
│   └── pubspec.yaml           # Flutter dependencies
│
├── launch.bat                 # Windows launcher
└── launch.sh                  # Linux/Mac launcher
```

## Features

### Current (MVP)
- ✅ Multi-platform support (Windows, Linux, Web)
- ✅ Local SQLite database for offline caching
- ✅ REST API backend with FastAPI
- ✅ Search and filter ebooks
- ✅ Library statistics dashboard
- ✅ Responsive Material Design UI
- ✅ Online/offline mode indication

### Planned
- 🔄 Google Drive integration
- 🔄 OneDrive integration
- 🔄 OAuth authentication
- 🔄 Metadata extraction (EPUB, PDF, MOBI)
- 🔄 Bulk operations
- 🔄 Drag-and-drop organization
- 🔄 Cloud sync

## Prerequisites

- **Flutter**: 3.35.6+ ([Install Flutter](https://flutter.dev/docs/get-started/install))
- **Python**: 3.8+ ([Install Python](https://python.org))
- **Git**: For version control

## Quick Start

### Option 1: Using Launcher Script (Recommended)

**Windows:**
```batch
launch.bat
```

**Linux/Mac:**
```bash
chmod +x launch.sh
./launch.sh
```

### Option 2: Manual Launch

**1. Start Backend**
```bash
cd backend
python -m venv venv

# Windows
venv\Scripts\activate
# Linux/Mac
source venv/bin/activate

pip install -r requirements.txt
python -m app.main
```

Backend will run at: http://127.0.0.1:8000

**2. Start Frontend** (in new terminal)
```bash
cd ebook_organizer_gui
flutter pub get

# Windows
flutter run -d windows

# Linux
flutter run -d linux

# Web
flutter run -d chrome
```

## API Documentation

Once backend is running, visit:
- Swagger UI: http://127.0.0.1:8000/docs
- ReDoc: http://127.0.0.1:8000/redoc

## Development

### Backend Development
```bash
cd backend
source venv/bin/activate  # or venv\Scripts\activate on Windows
python -m app.main  # Auto-reload enabled
```

### Frontend Development
```bash
cd ebook_organizer_gui
flutter run  # Hot reload enabled
```

### Key API Endpoints

- `GET /api/ebooks/` - List ebooks with filters
- `GET /api/ebooks/{id}` - Get single ebook
- `PATCH /api/ebooks/{id}` - Update ebook metadata
- `GET /api/ebooks/stats/library` - Library statistics
- `GET /api/cloud/providers` - Cloud provider status
- `POST /api/sync/trigger` - Trigger cloud sync

## Configuration

### Backend Configuration
Edit `backend/app/config.py` or create `.env` file:

```env
API_HOST=127.0.0.1
API_PORT=8000
DEBUG=True
DATABASE_URL=sqlite:///./ebook_organizer.db
```

### Cloud Storage Setup (Coming Soon)
- Google Drive: OAuth credentials needed
- OneDrive: Microsoft App registration needed

## Troubleshooting

### Backend won't start
- Check Python version: `python --version` (need 3.8+)
- Install dependencies: `pip install -r requirements.txt`
- Check port 8000 is not in use

### Flutter won't run
- Check Flutter installation: `flutter doctor`
- Get dependencies: `flutter pub get`
- Enable desktop support: `flutter config --enable-windows-desktop` (Windows)

### Database issues
- Delete `ebook_organizer.db` to reset
- Check file permissions

## Technology Stack

**Frontend:**
- Flutter 3.35.6
- Material Design 3
- Provider (state management)
- sqflite (local database)
- http/dio (API client)

**Backend:**
- FastAPI 0.109.0
- SQLAlchemy (ORM)
- Pydantic (validation)
- Google/Microsoft APIs (cloud storage)

## Contributing

This is a work in progress. Key areas to contribute:
1. Cloud storage integration (Google Drive/OneDrive)
2. OAuth implementation
3. Metadata extraction enhancement
4. UI/UX improvements

## License

See LICENSE file

## Next Steps

1. **Install Python dependencies**: `cd backend && pip install -r requirements.txt`
2. **Test backend**: `python -m app.main` then visit http://127.0.0.1:8000/docs
3. **Test Flutter app**: `cd ebook_organizer_gui && flutter run`
4. **Implement cloud storage**: Add OAuth for Google Drive/OneDrive
5. **Integrate metadata extraction**: Port existing Python code from `online-library-organizer/`
