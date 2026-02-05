"""
Unit tests for metadata classifier service
"""

import pytest
from pathlib import Path
from app.services.metadata_classifier import (
    is_printable_text,
    is_valid_author,
    clean_author_name,
    extract_from_filename,
    classify_book,
    ClassificationResult
)


class TestIsPrintableText:
    """Test printable text validation"""
    
    def test_valid_text(self):
        """Test valid printable text"""
        assert is_printable_text("Isaac Asimov") is True
        assert is_printable_text("Science Fiction") is True
        assert is_printable_text("René Descartes") is True  # Non-ASCII but valid
    
    def test_invalid_text(self):
        """Test invalid text patterns"""
        assert is_printable_text("b'binary_data'") is False
        assert is_printable_text(r"\x01\x02\x03") is False
        assert is_printable_text(None) is False
        assert is_printable_text("") is False
    
    def test_mixed_text(self):
        """Test text with mixed printable and non-printable"""
        # Mostly printable should pass
        assert is_printable_text("Hello World!") is True
        # Too many non-printable should fail
        assert is_printable_text("a\x00\x01\x02\x03\x04") is False


class TestIsValidAuthor:
    """Test author validation"""
    
    def test_valid_authors(self):
        """Test valid author names"""
        assert is_valid_author("Isaac Asimov") is True
        assert is_valid_author("J.K. Rowling") is True
        assert is_valid_author("Arthur C. Clarke") is True
    
    def test_blacklisted_authors(self):
        """Test blacklisted author values"""
        assert is_valid_author("unknown") is False
        assert is_valid_author("Unknown Author") is False
        assert is_valid_author("admin") is False
        assert is_valid_author("calibre") is False
        assert is_valid_author("various") is False
    
    def test_blacklisted_patterns(self):
        """Test blacklisted patterns"""
        assert is_valid_author("123") is False
        assert is_valid_author("ab") is False  # Too short
        assert is_valid_author("https://example.com") is False
        assert is_valid_author("example.com") is False
    
    def test_none_and_empty(self):
        """Test None and empty string"""
        assert is_valid_author(None) is False
        assert is_valid_author("") is False
        assert is_valid_author("   ") is False


class TestCleanAuthorName:
    """Test author name cleaning"""
    
    def test_remove_suffixes(self):
        """Test removal of common suffixes"""
        assert clean_author_name("Isaac Asimov, author") == "Isaac Asimov"
        assert clean_author_name("Jane Doe editor") == "Jane Doe"
        assert clean_author_name("John Smith, translator") == "John Smith"
    
    def test_remove_years(self):
        """Test removal of birth/death years"""
        assert clean_author_name("Charles Dickens, 1812-1870") == "Charles Dickens"
        assert clean_author_name("Author Name 1954-") == "Author Name"
    
    def test_remove_punctuation(self):
        """Test removal of trailing punctuation"""
        assert clean_author_name("Author Name.") == "Author Name"
        assert clean_author_name("Author Name,") == "Author Name"
        assert clean_author_name("Author Name;") == "Author Name"
    
    def test_combined_cleaning(self):
        """Test multiple cleaning operations"""
        assert clean_author_name("Charles Dickens, 1812-1870, author.") == "Charles Dickens"
    
    def test_none_and_empty(self):
        """Test None and empty string"""
        assert clean_author_name(None) is None
        assert clean_author_name("") is None
        assert clean_author_name("   ") is None


class TestExtractFromFilename:
    """Test author extraction from filenames"""
    
    def test_author_dash_title(self):
        """Test 'Author - Title' pattern"""
        path = Path("/library/Isaac Asimov - Foundation.epub")
        assert extract_from_filename(path) == "Isaac Asimov"
        
        path = Path("/library/Arthur C. Clarke - 2001 A Space Odyssey.epub")
        assert extract_from_filename(path) == "Arthur C. Clarke"
    
    def test_title_parentheses_author(self):
        """Test 'Title (Author)' pattern"""
        path = Path("/library/Foundation (Isaac Asimov).epub")
        assert extract_from_filename(path) == "Isaac Asimov"
    
    def test_title_brackets_author(self):
        """Test 'Title [Author]' pattern """
        path = Path("/library/Foundation [Isaac Asimov].epub")
        assert extract_from_filename(path) == "Isaac Asimov"
    
    def test_cleanup_junk(self):
        """Test cleanup of junk patterns"""
        path = Path("/library/Isaac Asimov - Foundation (PDFDrive).epub")
        result = extract_from_filename(path)
        assert result == "Isaac Asimov"
        
        path = Path("/library/Book Title (z-lib.org).epub")
        result = extract_from_filename(path)
        # Should not extract junk
        assert result is None or "z-lib" not in result
    
    def test_underscores(self):
        """Test handling of underscores"""
        path = Path("/library/Isaac_Asimov_-_Foundation.epub")
        result = extract_from_filename(path)
        assert result == "Isaac Asimov"
    
    def test_no_pattern_match(self):
        """Test when no pattern matches"""
        path = Path("/library/randombook.epub")
        assert extract_from_filename(path) is None


class TestClassifyBook:
    """Test comprehensive book classification"""
    
    def test_embedded_metadata_priority(self):
        """Test that valid embedded metadata takes priority"""
        path = Path("/library/random/book.epub")
        result = classify_book(path, embedded_genre="Science Fiction", embedded_author="Isaac Asimov")
        
        assert result.category == "Fiction"
        assert result.sub_genre == "Science Fiction"
        assert result.author == "Isaac Asimov"
        assert result.metadata_source == "embedded"
    
    def test_folder_fallback(self):
        """Test folder-based classification when no embedded data"""
        path = Path("/library/fantasy/book.epub")
        result = classify_book(path)
        
        assert result.category == "Fiction"
        assert result.sub_genre == "Fantasy"
        assert result.metadata_source == "folder"
    
    def test_invalid_embedded_author(self):
        """Test that invalid embedded authors are rejected"""
        path = Path("/library/book.epub")
        result = classify_book(path, embedded_author="unknown")
        
        assert result.author is None  # Invalid author should be rejected
    
    def test_clean_embedded_author(self):
        """Test that embedded author is cleaned"""
        path = Path("/library/book.epub")
        result = classify_book(
            path,
            embedded_genre="Science Fiction",
            embedded_author="Isaac Asimov, 1920-1992, author"
        )
        
        assert result.author == "Isaac Asimov"
    
    def test_filename_author_fallback(self):
        """Test filename author extraction when embedded is invalid"""
        path = Path("/library/Isaac Asimov - Foundation.epub")
        result = classify_book(path, embedded_author="unknown")
        
        # Should extract from filename since embedded is invalid
        assert result.author == "Isaac Asimov"
        assert result.metadata_source == "filename"
    
    def test_completely_unknown(self):
        """Test completely unknown book"""
        path = Path("/library/random/unknown_book.epub")
        result = classify_book(path)
        
        # Should return incomplete result
        assert isinstance(result, ClassificationResult)
        # May have None values for category/subgenre/author


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
