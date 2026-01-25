@echo off
REM Ebook Organizer Launcher for Windows
REM This script starts both the FastAPI backend and Flutter frontend

echo ========================================
echo Starting Ebook Organizer
echo ========================================
echo.

REM Change to the backend directory
cd /d "%~dp0backend"

echo [1/3] Checking Python installation...
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.8+ from https://python.org
    pause
    exit /b 1
)
echo Python found!
echo.

echo [2/3] Installing backend dependencies...
if not exist "venv" (
    echo Creating virtual environment...
    python -m venv venv
)

call venv\Scripts\activate.bat
pip install -r requirements.txt --quiet
echo Backend dependencies installed!
echo.

echo [3/3] Starting backend server...
start "Ebook Organizer Backend" cmd /k "cd /d "%~dp0backend" && venv\Scripts\activate.bat && python -m app.main"

REM Wait a bit for backend to start
timeout /t 5 /nobreak >nul

REM Change to Flutter app directory
cd /d "%~dp0ebook_organizer_gui"

echo.
echo Starting Flutter application...
echo ========================================
echo.

flutter run -d windows

REM Cleanup - this will run after Flutter app closes
echo.
echo Shutting down...
taskkill /FI "WINDOWTITLE eq Ebook Organizer Backend*" /F >nul 2>&1

pause
