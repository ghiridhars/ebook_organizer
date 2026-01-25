#!/bin/bash
# Ebook Organizer Launcher for Linux/Mac
# This script starts both the FastAPI backend and Flutter frontend

echo "========================================"
echo "Starting Ebook Organizer"
echo "========================================"
echo ""

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change to backend directory
cd "$SCRIPT_DIR/backend"

echo "[1/3] Checking Python installation..."
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed"
    echo "Please install Python 3.8+ from your package manager"
    exit 1
fi
echo "Python found!"
echo ""

echo "[2/3] Installing backend dependencies..."
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate
pip install -r requirements.txt --quiet
echo "Backend dependencies installed!"
echo ""

echo "[3/3] Starting backend server..."
python -m app.main &
BACKEND_PID=$!

# Wait for backend to start
sleep 5

# Change to Flutter app directory
cd "$SCRIPT_DIR/ebook_organizer_gui"

echo ""
echo "Starting Flutter application..."
echo "========================================"
echo ""

# Run Flutter on Linux
flutter run -d linux

# Cleanup - this will run after Flutter app closes
echo ""
echo "Shutting down..."
kill $BACKEND_PID 2>/dev/null

echo "Goodbye!"
