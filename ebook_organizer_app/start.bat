@echo off
REM Unified Launcher for Ebook Organizer
REM Starts both FastAPI backend and Flutter frontend

echo ================================================
echo   Ebook Organizer - Multi-Platform Launcher
echo ================================================
echo.

REM Check if Python is available
where python >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Python not found. Please install Python 3.8+ and add it to PATH.
    pause
    exit /b 1
)

REM Check if Flutter is available
where flutter >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Flutter not found. Please install Flutter and add it to PATH.
    pause
    exit /b 1
)

echo [1/4] Installing Python backend dependencies...
cd backend

REM Check if virtual environment exists
if not exist "venv\" (
    echo Creating virtual environment...
    python -m venv venv
    if %ERRORLEVEL% neq 0 (
        echo [ERROR] Failed to create virtual environment
        pause
        exit /b 1
    )
)

REM Activate virtual environment and install dependencies
call venv\Scripts\activate.bat
echo Installing backend requirements...
pip install -q -r requirements.txt
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to install backend dependencies
    pause
    exit /b 1
)

echo [2/4] Starting FastAPI backend server...
cd ..

REM Start backend in a new window
start "Ebook Organizer Backend" cmd /k "cd /d %CD%\backend && venv\Scripts\activate && python -m app.main"

REM Wait for backend to start
echo Waiting for backend to start...
timeout /t 5 /nobreak >nul

echo [3/4] Installing Flutter dependencies...
cd ebook_organizer_gui
call flutter pub get >nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to install Flutter dependencies
    pause
    exit /b 1
)

echo [4/4] Starting Flutter application...
echo.
echo ================================================
echo   Both services are starting!
echo ================================================
echo   Backend:  http://127.0.0.1:8000
echo   Frontend: Starting Flutter app...
echo ================================================
echo.

REM Start Flutter app (will open in default browser for web or desktop window)
flutter run -d windows

REM When Flutter exits, cleanup
echo.
echo [INFO] Flutter app closed. Stopping backend...
taskkill /FI "WINDOWTITLE eq Ebook Organizer Backend*" /T /F >nul 2>&1

echo.
echo ================================================
echo   Ebook Organizer Stopped
echo ================================================
pause
