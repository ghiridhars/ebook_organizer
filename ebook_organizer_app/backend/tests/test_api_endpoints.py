"""
Integration tests for Ebook API endpoints
"""

import pytest
from fastapi.testclient import TestClient


class TestHealthEndpoints:
    """Test health check endpoints"""
    
    def test_root_endpoint(self, client: TestClient):
        """Test root endpoint returns API status"""
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "online"
        assert data["service"] == "Ebook Organizer API"
        assert "version" in data
    
    def test_health_endpoint(self, client: TestClient):
        """Test health endpoint returns detailed status"""
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "database" in data
        assert "cloud_services" in data


class TestEbookEndpoints:
    """Test ebook CRUD endpoints"""
    
    def test_list_ebooks_empty(self, client: TestClient):
        """Test listing ebooks when database is empty"""
        response = client.get("/api/ebooks/")
        assert response.status_code == 200
        data = response.json()
        assert data["ebooks"] == []
        assert data["total"] == 0
    
    def test_list_ebooks_with_pagination(self, client: TestClient):
        """Test pagination parameters are accepted"""
        response = client.get("/api/ebooks/?skip=0&limit=10")
        assert response.status_code == 200
        data = response.json()
        assert "ebooks" in data
        assert "total" in data
    
    def test_list_ebooks_with_filters(self, client: TestClient):
        """Test filter parameters are accepted"""
        response = client.get("/api/ebooks/?category=Fiction&format=epub")
        assert response.status_code == 200
        assert "ebooks" in response.json()
    
    def test_get_ebook_not_found(self, client: TestClient):
        """Test getting non-existent ebook returns 404"""
        response = client.get("/api/ebooks/999")
        assert response.status_code == 404
    
    def test_library_stats(self, client: TestClient):
        """Test library statistics endpoint"""
        response = client.get("/api/ebooks/stats/library")
        assert response.status_code == 200
        data = response.json()
        assert "total_ebooks" in data
        assert "by_category" in data


class TestMetadataEndpoints:
    """Test metadata extraction endpoints"""
    
    def test_classify_missing_file(self, client: TestClient):
        """Test classifying non-existent file returns error"""
        response = client.post(
            "/api/metadata/classify",
            json={"file_path": "/nonexistent/file.epub"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is False
        assert "error" in data
    
    def test_classify_invalid_format(self, client: TestClient):
        """Test classifying unsupported format returns error"""
        response = client.post(
            "/api/metadata/classify",
            json={"file_path": "/path/to/file.txt"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is False


class TestErrorHandling:
    """Test error handling and responses"""
    
    def test_404_returns_structured_error(self, client: TestClient):
        """Test 404 errors return structured JSON"""
        response = client.get("/api/nonexistent")
        assert response.status_code == 404
        data = response.json()
        assert "error" in data or "detail" in data
    
    def test_request_has_request_id(self, client: TestClient):
        """Test responses include request ID header"""
        response = client.get("/")
        # Request ID should be in headers
        assert "x-request-id" in response.headers
    
    def test_validation_error_response(self, client: TestClient):
        """Test validation errors return detailed info"""
        response = client.get("/api/ebooks/?limit=-1")
        # Should either accept or return validation error
        assert response.status_code in [200, 422]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
