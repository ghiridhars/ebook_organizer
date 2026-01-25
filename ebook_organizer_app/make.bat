@echo off
REM Makefile wrapper for Windows
REM This allows running: make.bat flutter, make.bat backend, etc.

setlocal enabledelayedexpansion

if "%1"=="" (
    echo.
    echo Ebook Organizer - Windows Build Commands
    echo.
    echo Usage: make.bat [command]
    echo.
    echo Commands:
    echo   backend          - Run Python backend
    echo   flutter          - Run Flutter app  
    echo   dev              - Run both in parallel
    echo   docker-up        - Start Docker services
    echo   docker-down      - Stop Docker services
    echo   docker-logs      - View Docker logs
    echo   install          - Install all dependencies
    echo   setup            - Full setup with DB init
    echo   test-setup       - Test backend connection
    echo   clean            - Clean build artifacts
    echo.
    exit /b 0
)

set CMD=%1

if "%CMD%"=="backend" (
    cd backend
    python run.py
    exit /b !ERRORLEVEL!
)

if "%CMD%"=="flutter" (
    cd ebook_organizer_gui
    flutter run -d windows
    exit /b !ERRORLEVEL!
)

if "%CMD%"=="dev" (
    start /B powershell -NoExit -Command "cd backend; python run.py"
    timeout /t 5 /nobreak >nul
    start /B powershell -NoExit -Command "cd ebook_organizer_gui; flutter run -d windows"
    exit /b 0
)

if "%CMD%"=="docker-up" (
    docker-compose up -d
    exit /b !ERRORLEVEL!
)

if "%CMD%"=="docker-down" (
    docker-compose down
    exit /b !ERRORLEVEL!
)

if "%CMD%"=="docker-logs" (
    docker-compose logs -f
    exit /b !ERRORLEVEL!
)

if "%CMD%"=="install" (
    echo Installing Python dependencies...
    cd backend
    pip install -r requirements.txt
    cd ..
    echo.
    echo Installing Flutter dependencies...
    cd ebook_organizer_gui
    flutter pub get
    cd ..
    echo.
    echo Dependencies installed
    exit /b 0
)

if "%CMD%"=="setup" (
    call make.bat install
    python test_setup.py
    exit /b !ERRORLEVEL!
)

if "%CMD%"=="test-setup" (
    python test_setup.py
    exit /b !ERRORLEVEL!
)

if "%CMD%"=="clean" (
    echo Cleaning build artifacts...
    cd ebook_organizer_gui
    flutter clean
    cd ..
    rmdir /s /q backend\__pycache__ 2>nul
    rmdir /s /q backend\.pytest_cache 2>nul
    echo Clean complete
    exit /b 0
)

echo Unknown command: %CMD%
exit /b 1
