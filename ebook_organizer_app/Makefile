.PHONY: help install setup backend flutter dev docker-up docker-down docker-build docker-logs docker-flutter test test-setup clean clean-all

# Detect OS
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    DETECTED_OS := linux
endif
ifeq ($(UNAME_S),Darwin)
    DETECTED_OS := macos
endif
ifeq ($(OS),Windows_NT)
    DETECTED_OS := windows
endif

# Default target
help:
	@echo "Ebook Organizer - Development Commands"
	@echo "======================================"
	@echo ""
	@echo "Setup Commands:"
	@echo "  make install          - Install all dependencies (Python + Flutter)"
	@echo "  make setup            - Complete setup (install + init DB)"
	@echo ""
	@echo "Development Commands:"
	@echo "  make backend          - Run Python backend (local)"
	@echo "  make flutter          - Run Flutter app (local)"
	@echo "  make dev              - Run both backend and flutter in parallel"
	@echo ""
	@echo "Docker Commands:"
	@echo "  make docker-build     - Build Docker images"
	@echo "  make docker-up        - Start services with Docker Compose"
	@echo "  make docker-down      - Stop Docker services"
	@echo "  make docker-logs      - View Docker logs"
	@echo "  make docker-flutter   - Build Flutter app in Docker"
	@echo ""
	@echo "Testing:"
	@echo "  make test             - Run backend tests"
	@echo "  make test-setup       - Test backend connectivity"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean            - Clean build artifacts"
	@echo "  make clean-all        - Deep clean (including dependencies)"

# Installation
install:
	@echo "Installing Python dependencies..."
	cd backend && pip install -r requirements.txt
	@echo ""
	@echo "Installing Flutter dependencies..."
	cd ebook_organizer_gui && flutter pub get
	@echo ""
	@echo "Dependencies installed"

setup: install
	@echo "Initializing database..."
	python test_setup.py
	@echo ""
	@echo "Setup complete"

# Local Development
backend:
	@echo "Starting Python backend..."
	cd backend && python run.py

flutter:
	@echo "Starting Flutter app..."
	cd ebook_organizer_gui && flutter run

# Run both in parallel
dev:
	@echo "Starting backend and Flutter in parallel..."
ifeq ($(DETECTED_OS),windows)
	@powershell -Command "Start-Process powershell -ArgumentList '-NoExit', '-Command', 'cd backend; python run.py'"
	@timeout /t 5 /nobreak >nul
	@powershell -Command "Start-Process powershell -ArgumentList '-NoExit', '-Command', 'cd ebook_organizer_gui; flutter run -d windows'"
else
	cd backend && python run.py &
	sleep 5
	cd ebook_organizer_gui && flutter run
endif

# Docker Commands
docker-build:
	@echo "Building Docker images..."
	docker-compose build

docker-up:
	@echo "Starting services with Docker Compose..."
	docker-compose up -d
	@echo ""
	@echo "Services started"
	@echo "  Backend: http://localhost:8000"
	@echo "  API Docs: http://localhost:8000/docs"

docker-down:
	@echo "Stopping Docker services..."
	docker-compose down

docker-logs:
	docker-compose logs -f

docker-flutter:
	@echo "Building Flutter app in Docker..."
	docker-compose --profile build run --rm flutter-builder

# Testing
test:
	@echo "Running backend tests..."
	cd backend && python -m pytest

test-setup:
	@echo "Testing backend setup..."
	python test_setup.py

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	cd ebook_organizer_gui && flutter clean
	rm -rf backend/__pycache__ backend/**/__pycache__
	rm -rf backend/.pytest_cache
	@echo "Clean complete"

clean-all: clean
	@echo "Deep cleaning..."
	rm -rf backend/venv
	rm -rf ebook_organizer_gui/.dart_tool
	rm -rf ebook_organizer_gui/build
	@echo "Deep clean complete"

# Quick start
start: docker-up

stop: docker-down
