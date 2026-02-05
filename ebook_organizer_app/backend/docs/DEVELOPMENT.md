# Development Setup Guide

## Prerequisites

- Python 3.10+
- Node.js 18+ (for Flutter web)
- Flutter SDK 3.9+

---

## Backend Setup

### 1. Create Virtual Environment
```bash
cd ebook_organizer_app/backend
python -m venv venv

# Windows
venv\Scripts\activate

# Linux/Mac
source venv/bin/activate
```

### 2. Install Dependencies
```bash
pip install -r requirements.txt
```

### 3. Configure Environment
```bash
# Copy example config
cp .env.example .env

# Edit .env with your settings
# At minimum, set a secure SECRET_KEY for production
```

### 4. Run Development Server
```bash
# Using Python module
python -m app.main

# Or using uvicorn directly
uvicorn app.main:app --reload --port 8000
```

### 5. Run Tests
```bash
pip install pytest pytest-cov httpx

# Run all tests
pytest tests/ -v

# Run with coverage
pytest tests/ -v --cov=app --cov-report=html
```

---

## Frontend Setup (Flutter)

### 1. Get Dependencies
```bash
cd ebook_organizer_app/ebook_organizer_gui
flutter pub get
```

### 2. Run Development Build
```bash
# Desktop (Windows/Linux)
flutter run -d windows

# Web
flutter run -d chrome

# Debug mode with hot reload
flutter run -d windows --debug
```

### 3. Build Release
```bash
flutter build windows --release
flutter build web --release
```

---

## Using Docker

### Full Stack
```bash
cd ebook_organizer_app
docker-compose up --build
```

### Backend Only
```bash
cd ebook_organizer_app/backend
docker build -t ebook-backend .
docker run -p 8000:8000 ebook-backend
```

---

## Project Structure
```
ebook_organizer_app/
├── backend/
│   ├── app/
│   │   ├── main.py          # FastAPI entry point
│   │   ├── config.py        # Settings management
│   │   ├── middleware.py    # Logging & error handling
│   │   ├── logging_config.py
│   │   ├── models/          # SQLAlchemy & Pydantic
│   │   ├── routes/          # API endpoints
│   │   └── services/        # Business logic
│   ├── tests/               # pytest tests
│   ├── docs/                # Documentation
│   └── requirements.txt
│
├── ebook_organizer_gui/
│   └── lib/
│       ├── main.dart        # Flutter entry
│       ├── models/          # Data models
│       ├── providers/       # State management
│       ├── screens/         # UI screens
│       ├── services/        # API & DB services
│       └── widgets/         # Reusable components
│
└── docker-compose.yml
```

---

## Common Tasks

### Add Database Migration
```bash
# Not yet implemented - using auto-create tables
```

### View API Docs
Open http://localhost:8000/docs after starting backend.

### Check Logs
Backend logs are written to:
- Console (human-readable)
- `backend/logs/app.log` (JSON structured)
- `backend/logs/error.log` (errors only)
