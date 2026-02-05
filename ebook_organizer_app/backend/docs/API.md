# Ebook Organizer API Documentation

## Base URL
```
http://localhost:8000
```

## Authentication
Currently no authentication required. Future versions will implement OAuth2.

---

## Endpoints

### Health & Status

#### GET /
Root health check.
```json
{"status": "online", "service": "Ebook Organizer API", "version": "1.0.0"}
```

#### GET /health
Detailed health status.
```json
{"status": "healthy", "database": "connected", "cloud_services": {...}}
```

---

### Ebooks (`/api/ebooks`)

#### GET /api/ebooks/search
Full-text search with FTS5 ranking.

**Query Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| q | string | Yes | Search query |
| category | string | No | Filter by category |
| format | string | No | Filter by format (epub, pdf, mobi) |
| page | int | No | Page number (default: 1) |
| page_size | int | No | Results per page (default: 20, max: 100) |

**Response:**
```json
{
  "query": "foundation",
  "total": 15,
  "page": 1,
  "page_size": 20,
  "results": [
    {
      "id": 1,
      "title": "Foundation",
      "author": "Isaac Asimov",
      "category": "Fiction",
      "sub_genre": "Science Fiction",
      "format": "epub",
      "score": 2.45,
      "snippet": "The <mark>Foundation</mark> series..."
    }
  ]
}
```

#### GET /api/ebooks/search/suggestions
Get autocomplete suggestions.

**Query Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| prefix | string | Yes | Search prefix (min 2 chars) |
| limit | int | No | Max suggestions (default: 5) |

#### GET /api/ebooks/
List ebooks with filters.

**Query Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| skip | int | Offset for pagination |
| limit | int | Max results (1-1000) |
| category | string | Filter by category |
| sub_genre | string | Filter by sub-genre |
| author | string | Filter by author (partial match) |
| search | string | Basic search in title/author |
| format | string | Filter by file format |

#### GET /api/ebooks/{id}
Get single ebook by ID.

#### PATCH /api/ebooks/{id}
Update ebook metadata.

**Request Body:**
```json
{
  "title": "New Title",
  "author": "New Author",
  "category": "Fiction",
  "tags": ["favorite", "to-read"]
}
```

#### DELETE /api/ebooks/{id}
Delete ebook from local database.

#### GET /api/ebooks/stats/library
Library statistics.

```json
{
  "total_books": 150,
  "by_category": {"Fiction": 80, "Non-Fiction": 70},
  "by_format": {"epub": 100, "pdf": 50},
  "total_size_mb": 1024.5,
  "last_sync": "2024-01-15T10:30:00Z"
}
```

---

### Metadata (`/api/metadata`)

#### POST /api/metadata/classify
Classify an ebook file.

**Request:**
```json
{"file_path": "/path/to/book.epub"}
```

**Response:**
```json
{
  "success": true,
  "file_path": "/path/to/book.epub",
  "category": "Fiction",
  "sub_genre": "Science Fiction",
  "author": "Isaac Asimov",
  "metadata_source": "embedded"
}
```

#### POST /api/metadata/extract-comprehensive
Full metadata extraction with classification.

---

## Error Responses

All errors return structured JSON:
```json
{
  "success": false,
  "error": {
    "code": 404,
    "message": "Ebook not found",
    "request_id": "abc12345"
  }
}
```

Response headers include `X-Request-ID` for tracking.

---

## Interactive Docs

- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc
