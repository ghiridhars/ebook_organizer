FROM python:3.11-slim-bookworm

WORKDIR /app

# Install system dependencies for ARM64 native compilation
# build-essential + python3-dev: compile cryptography, bcrypt wheels
# libsqlite3-dev: ensure FTS5 support in SQLite
# libjpeg-dev + libwebp-dev + zlib1g-dev: Pillow image format support (Phase 3)
# curl: healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    build-essential \
    python3-dev \
    libsqlite3-dev \
    libjpeg-dev \
    libwebp-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p /app/data/covers /app/static/web/lib

# Expose port
EXPOSE 8000

# Health check (increased start-period for ARM boot time)
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run the application (no --reload in production)
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
