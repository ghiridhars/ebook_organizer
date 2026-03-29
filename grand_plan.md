# Software Architecture Plan: Lightweight eBook Library

## 1. System Overview
A resource-efficient, self-hosted eBook library manager designed for low-power ARM environments (specifically Raspberry Pi). The system eschews heavy existing frameworks (like Calibre) in favor of a modular, asynchronous architecture focusing on rapid metadata extraction, SQLite-based indexing, and browser-based client rendering.

## 2. Technology Stack
* **Backend / API:** Python 3.11+ with FastAPI (Uvicorn ASGI).
* **Database:** SQLite (using SQLAlchemy or Tortoise ORM for async DB operations).
* **Frontend:** Svelte + TailwindCSS (compiled to static assets).
* **Reverse Proxy:** Caddy (handles automatic HTTPS and static file serving).
* **Core Libraries:**
    * `watchdog`: File system event monitoring.
    * `ebooklib`: EPUB metadata/XML parsing.
    * `Pillow`: Cover image extraction and thumbnail generation.
    * `epub.js`: In-browser eBook rendering.

## 3. Data Architecture (SQLite Schema)
Do not store binary blobs in the database. Store file references.

### Table: `books`
| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | Integer | Primary Key, Auto-increment | Unique identifier. |
| `title` | String | Not Null, Indexed | Extracted from `content.opf`. |
| `author` | String | Indexed | Extracted from `content.opf`. |
| `file_path` | String | Unique, Not Null | Absolute/Relative path to the `.epub`. |
| `cover_path` | String | Nullable | Path to cached thumbnail in `/static/covers`. |
| `added_timestamp` | DateTime| Default `NOW()` | Ingestion time. |

*Note: Utilize SQLite FTS5 (Full-Text Search) extension on `title` and `author` columns for high-performance querying without high memory overhead.*

## 4. Core Subsystems & Logic Flow

### A. The Ingestion Engine (Watcher)
* **Process:** A background daemon utilizing `watchdog` to monitor a configured `/library/raw_books` directory.
* **Trigger:** `on_created` event for `.epub` extensions.
* **Action:** Dispatches the file path to the Extraction Pipeline. Moves the processed file to `/library/processed/Author/BookTitle.epub` to maintain file system hygiene.

### B. The Extraction Pipeline (Parser)
* **Process:** Unzips the EPUB archive in memory.
* **Metadata:** Parses `OEBPS/content.opf` (or equivalent as defined in `META-INF/container.xml`) using `ebooklib`. Extracts `dc:title`, `dc:creator`, and `dc:identifier`.
* **Cover Art:** Locates the cover image via the `<meta name="cover" content="...">` tag, extracts the image file, resizes it using `Pillow` to a standard thumbnail (e.g., 400x600px, WebP format for compression), and saves it to `/library/covers`.
* **Database Commit:** Writes the extracted data and file paths to the SQLite database.

### C. The API Layer (FastAPI endpoints)
* `GET /api/books`: Returns a paginated JSON list of books (supports `?search=` query).
* `GET /api/books/{id}`: Returns full metadata for a specific book.
* `GET /api/books/{id}/download`: Serves the raw `.epub` file as an attachment.
* `GET /api/books/{id}/stream`: Serves the `.epub` file using range requests for browser rendering.

### D. The Client Interface (Svelte + EPUB.js)
* **Library View:** A responsive grid displaying book covers. Utilizes intersection observers to lazy-load cover images.
* **Reader View:** Implements `epub.js` to render the book inside an HTML `div`. Fetches the book via the `/api/books/{id}/stream` endpoint. Stores reading progress (CFI) in browser `localStorage`.

## 5. Deployment & Hardware Strategy (Raspberry Pi)

### Hardware Profile
* **Target Device:** Raspberry Pi 5 (4GB RAM recommended for optimal extraction concurrency).
* **Storage:** External NVMe SSD via PCIe HAT (preferred for I/O speed during database indexing) or a high-endurance A2 MicroSD card.
* **Environmental Considerations:** Given tropical ambient temperatures and potential power grid fluctuations, an official Active Cooler is required to prevent thermal throttling, alongside a stable 27W USB-C PD official power supply to prevent brownouts.

### Deployment Containerization (Docker Compose)
The application will be deployed as a multi-container Docker application to isolate dependencies from the host OS.

```yaml
version: '3.8'

services:
  caddy:
    image: caddy:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
    depends_on:
      - backend
      - frontend

  backend:
    build: ./backend
    volumes:
      - ./data:/app/data
      - ./library:/library
    environment:
      - DB_PATH=/app/data/library.db
      - WATCH_DIR=/library/raw_books

  frontend:
    build: ./frontend
    # Serves static compiled files internally to Caddy

volumes:
  caddy_data: