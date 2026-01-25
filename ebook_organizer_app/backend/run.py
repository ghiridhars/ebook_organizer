"""
Simple runner script for the backend
"""
import sys
import os

# Add the parent directory to the path so 'app' module can be found
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Now import and run
import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="127.0.0.1",
        port=8000,
        reload=True,
        log_level="info"
    )
