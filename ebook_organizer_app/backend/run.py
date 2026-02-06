"""
Runner script for the Ebook Organizer backend

Supports both development mode (with Python) and production mode (PyInstaller bundle).
"""
import sys
import os

# Detect if running as a PyInstaller frozen executable
IS_FROZEN = getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS')

if IS_FROZEN:
    # When frozen, the app directory is in the temp extraction folder
    # PyInstaller extracts to sys._MEIPASS
    base_path = sys._MEIPASS
    sys.path.insert(0, base_path)
    # Set working directory to the executable's directory for database access
    exe_dir = os.path.dirname(sys.executable)
    os.chdir(exe_dir)
else:
    # Development mode - add the parent directory to the path
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Now import and run
import uvicorn

if __name__ == "__main__":
    # Get configuration based on mode
    host = "127.0.0.1"
    port = 8000
    
    if IS_FROZEN:
        # Production mode: no reload, optimized settings
        print(f"Starting Ebook Organizer Backend (production mode)")
        print(f"Server running at http://{host}:{port}")
        uvicorn.run(
            "app.main:app",
            host=host,
            port=port,
            reload=False,  # Cannot reload frozen executable
            log_level="info",
            access_log=True,
        )
    else:
        # Development mode: enable reload for faster development
        print(f"Starting Ebook Organizer Backend (development mode)")
        uvicorn.run(
            "app.main:app",
            host=host,
            port=port,
            reload=True,
            log_level="info",
        )
