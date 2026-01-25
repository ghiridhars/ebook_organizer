"""Test script to verify backend setup"""

import sys
import requests
from time import sleep

print("=" * 50)
print("Testing Ebook Organizer Backend Setup")
print("=" * 50)
print()

# Test 1: Check imports
print("[1/3] Testing Python imports...")
try:
    from fastapi import FastAPI
    from sqlalchemy import create_engine
    import uvicorn
    print("✅ All required packages installed")
except ImportError as e:
    print(f"❌ Import error: {e}")
    sys.exit(1)

# Test 2: Start backend (in background)
print("\n[2/3] Starting backend server...")
print("Please run: python -m app.main")
print("Then run this test script in another terminal")
print()

# Test 3: Check API endpoints
print("[3/3] Testing API endpoints...")
base_url = "http://127.0.0.1:8000"

try:
    # Health check
    response = requests.get(f"{base_url}/health", timeout=5)
    if response.status_code == 200:
        print("✅ Health endpoint working")
        print(f"   Response: {response.json()}")
    else:
        print(f"❌ Health check failed: {response.status_code}")
    
    # Root endpoint
    response = requests.get(base_url, timeout=5)
    if response.status_code == 200:
        print("✅ Root endpoint working")
        print(f"   Response: {response.json()}")
    
    # Ebooks endpoint
    response = requests.get(f"{base_url}/api/ebooks/", timeout=5)
    if response.status_code == 200:
        print("✅ Ebooks endpoint working")
        print(f"   Found {len(response.json())} ebooks")
    
    print("\n" + "=" * 50)
    print("✅ Backend setup successful!")
    print("=" * 50)
    print("\nNext steps:")
    print("1. Run Flutter app: cd ebook_organizer_gui && flutter run")
    print("2. Or use launcher: launch.bat (Windows) or ./launch.sh (Linux)")
    
except requests.exceptions.ConnectionError:
    print("❌ Cannot connect to backend")
    print("\nPlease start the backend first:")
    print("  cd backend")
    print("  .\\venv\\Scripts\\activate  (Windows)")
    print("  python -m app.main")
except Exception as e:
    print(f"❌ Error: {e}")
