#!/bin/bash
# Quick Backend Test - Starts only the FastAPI backend for testing

echo "================================================"
echo "  Starting Ebook Organizer Backend Only"
echo "================================================"
echo ""

cd backend

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    echo "Installing dependencies..."
    pip install -r requirements.txt
else
    source venv/bin/activate
fi

echo ""
echo "Starting FastAPI backend on http://127.0.0.1:8000"
echo "Press Ctrl+C to stop"
echo ""
echo "================================================"
echo ""

python -m app.main
