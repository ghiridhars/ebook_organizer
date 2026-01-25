@echo off
REM Quick Backend Test - Starts only the FastAPI backend for testing

echo ================================================
echo   Starting Ebook Organizer Backend Only
echo ================================================
echo.

cd backend

REM Check if virtual environment exists
if not exist "venv\" (
    echo Creating virtual environment...
    python -m venv venv
    call venv\Scripts\activate.bat
    echo Installing dependencies...
    pip install -r requirements.txt
) else (
    call venv\Scripts\activate.bat
)

echo.
echo Starting FastAPI backend on http://127.0.0.1:8000
echo Press Ctrl+C to stop
echo.
echo ================================================
echo.

python -m app.main
