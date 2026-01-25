#!/bin/bash
# Unified Launcher for Ebook Organizer (Linux/Mac)
# Starts both FastAPI backend and Flutter frontend

echo "================================================"
echo "  Ebook Organizer - Multi-Platform Launcher"
echo "================================================"
echo ""

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "[ERROR] Python3 not found. Please install Python 3.8+"
    exit 1
fi

# Check if Flutter is available
if ! command -v flutter &> /dev/null; then
    echo "[ERROR] Flutter not found. Please install Flutter"
    exit 1
fi

echo "[1/4] Installing Python backend dependencies..."
cd backend

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
    if [ $? -ne 0 ]; then
        echo "[ERROR] Failed to create virtual environment"
        exit 1
    fi
fi

# Activate virtual environment and install dependencies
source venv/bin/activate
echo "Installing backend requirements..."
pip install -q -r requirements.txt
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to install backend dependencies"
    exit 1
fi

echo "[2/4] Starting FastAPI backend server..."
cd ..

# Start backend in background
(cd backend && source venv/bin/activate && python -m app.main) &
BACKEND_PID=$!

# Wait for backend to start
echo "Waiting for backend to start..."
sleep 5

echo "[3/4] Installing Flutter dependencies..."
cd ebook_organizer_gui
flutter pub get > /dev/null
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to install Flutter dependencies"
    kill $BACKEND_PID
    exit 1
fi

echo "[4/4] Starting Flutter application..."
echo ""
echo "================================================"
echo "  Both services are running!"
echo "================================================"
echo "  Backend:  http://127.0.0.1:8000"
echo "  Frontend: Starting Flutter app..."
echo "================================================"
echo ""

# Start Flutter app
flutter run -d linux

# When Flutter exits, cleanup
echo ""
echo "[INFO] Flutter app closed. Stopping backend..."
kill $BACKEND_PID 2>/dev/null

echo ""
echo "================================================"
echo "  Ebook Organizer Stopped"
echo "================================================"
