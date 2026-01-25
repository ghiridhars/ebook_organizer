# Ebook Organizer - Docker & Makefile Guide

## 🚀 Quick Start

### Using Docker Compose

```bash
# Start the backend service
make docker-up

# Or manually:
docker-compose up -d
```

The backend will be available at:
- API: http://localhost:8000
- API Documentation: http://localhost:8000/docs
- Health Check: http://localhost:8000/health

### Using Make Commands

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

## 🛠️ Development Workflow

### Option 1: Local Development (Recommended for Flutter)
```bash
# Terminal 1: Backend
make backend

# Terminal 2: Flutter
cd ebook_organizer_gui
flutter run -d windows
```

### Option 2: Docker Backend + Local Flutter
```bash
# Start backend in Docker
make docker-up

# Run Flutter locally
cd ebook_organizer_gui
flutter run -d windows
```

### Option 3: Full Parallel Local Development
```bash
# Starts both in separate PowerShell windows
make dev
```

## 🐳 Docker Commands

| Command | Description |
|---------|-------------|
| `make docker-build` | Build Docker images |
| `make docker-up` | Start services (detached) |
| `make docker-down` | Stop all services |
| `make docker-logs` | View live logs |
| `make docker-flutter` | Build Flutter in Docker |

## 📝 Makefile Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all commands |
| `make install` | Install Python + Flutter deps |
| `make setup` | Full setup with DB init |
| `make backend` | Run backend locally |
| `make flutter` | Run Flutter locally |
| `make dev` | Run both in parallel |
| `make test` | Run backend tests |
| `make test-setup` | Test backend connection |
| `make clean` | Clean build artifacts |
| `make clean-all` | Deep clean (+ deps) |

## 🔧 Configuration

### Environment Variables

Create `backend/.env` file:
```env
DATABASE_URL=sqlite:///./ebook_organizer.db
GOOGLE_DRIVE_CLIENT_ID=your_client_id
GOOGLE_DRIVE_CLIENT_SECRET=your_client_secret
ONEDRIVE_CLIENT_ID=your_client_id
ONEDRIVE_CLIENT_SECRET=your_client_secret
```

### Docker Compose Override

Create `docker-compose.override.yml` for local customizations:
```yaml
version: '3.8'

services:
  backend:
    environment:
      - DEBUG=1
    ports:
      - "8001:8000"  # Different port
```

## 🏗️ Building for Production

### Backend Docker Image
```bash
docker build -t ebook-organizer-backend:latest ./backend
docker run -p 8000:8000 ebook-organizer-backend:latest
```

### Flutter Desktop Build
```bash
cd ebook_organizer_gui

# Windows
flutter build windows --release

# Linux
flutter build linux --release

# macOS
flutter build macos --release
```

## 🐛 Troubleshooting

### Backend not starting
```bash
# Check logs
make docker-logs

# Or
docker-compose logs backend

# Restart
make docker-down
make docker-up
```

### Port already in use
```bash
# Check what's using port 8000
netstat -ano | findstr :8000

# Kill the process or change port in docker-compose.yml
```

### Database issues
```bash
# Reset database
rm backend/ebook_organizer.db
make docker-down
make docker-up
```

### Flutter build errors
```bash
# Clean Flutter cache
make clean
cd ebook_organizer_gui
flutter pub get
```

## 📚 Architecture

```
ebook_organizer_app/
├── backend/                    # Python FastAPI backend
│   ├── app/                   # Application code
│   ├── Dockerfile             # Backend container
│   ├── requirements.txt       # Python dependencies
│   └── run.py                 # Development runner
├── ebook_organizer_gui/       # Flutter frontend
│   ├── lib/                   # Flutter code
│   └── pubspec.yaml           # Flutter dependencies
├── docker-compose.yml         # Service orchestration
├── Makefile                   # Build automation
└── README_DOCKER.md           # This file
```

## 🔐 Security Notes

- **Never commit** `.env` files
- **Never commit** database files with real data
- Use environment variables for secrets
- Keep `requirements.txt` updated
- Regular security updates: `flutter upgrade` and `pip install -U`

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Make changes
4. Test with `make test`
5. Submit pull request

## 📄 License

See LICENSE file in repository root.
