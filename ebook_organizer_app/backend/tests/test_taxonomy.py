"""
Unit tests for taxonomy classification system
"""

import pytest
from pathlib import Path
from app.services.taxonomy import (
    classify_genre,
    classify_from_folder,
    classify_from_title,
    TAXONOMY
)


class TestClassifyGenre:
    """Test genre string classification"""
    
    def test_exact_match_fiction(self):
        """Test exact match for fiction genres"""
        assert classify_genre("Science Fiction") == ("Fiction", "Science Fiction")
        assert classify_genre("Fantasy") == ("Fiction", "Fantasy")
        assert classify_genre("Mystery") == ("Fiction", "Mystery & Thriller")
    
    def test_exact_match_nonfiction(self):
        """Test exact match for non-fiction genres"""
        assert classify_genre("Biography") == ("Non-Fiction", "Biography & Memoir")
        assert classify_genre("History") == ("Non-Fiction", "History")
        assert classify_genre("Philosophy") == ("Non-Fiction", "Philosophy & Religion")
    
    def test_case_insensitive(self):
        """Test case-insensitive matching"""
        assert classify_genre("FANTASY") == ("Fiction", "Fantasy")
        assert classify_genre("science fiction") == ("Fiction", "Science Fiction")
        assert classify_genre("BiOgRaPhY") == ("Non-Fiction", "Biography & Memoir")
    
    def test_alias_matching(self):
        """Test matching against aliases"""
        assert classify_genre("sci-fi") == ("Fiction", "Science Fiction")
        assert classify_genre("autobiography") == ("Non-Fiction", "Biography & Memoir")
        assert classify_genre("suspense") == ("Fiction", "Mystery & Thriller")
    
    def test_partial_matching(self):
        """Test partial matching for compound genres"""
        assert classify_genre("epic fantasy fiction") == ("Fiction", "Fantasy")
        assert classify_genre("science fiction, general") == ("Fiction", "Science Fiction")
    
    def test_blacklist_patterns(self):
        """Test that blacklisted patterns return None"""
        assert classify_genre("https://example.com") == (None, None)
        assert classify_genre("www.example.com") == (None, None)
        assert classify_genre("123") == (None, None)
        assert classify_genre("ab") == (None, None)  # Too short
    
    def test_too_long(self):
        """Test that overly long strings are rejected"""
        long_string = "a" * 60
        assert classify_genre(long_string) == (None, None)
    
    def test_none_and_empty(self):
        """Test None and empty string handling"""
        assert classify_genre(None) == (None, None)
        assert classify_genre("") == (None, None)
        assert classify_genre("   ") == (None, None)
    
    def test_broad_categories(self):
        """Test broad category fallbacks"""
        # "fiction" alone matches the "fiction" alias in Literary subgenre
        result = classify_genre("fiction")
        assert result[0] == "Fiction"  # Should be Fiction category
        
        assert classify_genre("non-fiction") == ("Non-Fiction", "Other")
        assert classify_genre("nonfiction") == ("Non-Fiction", "Other")


class TestClassifyFromFolder:
    """Test folder-based classification"""
    
    def test_direct_match(self):
        """Test direct folder name matching"""
        path = Path("/library/science fiction/book.epub")
        assert classify_from_folder(path) == ("Fiction", "Science Fiction")
        
        path = Path("/library/biography/book.epub")
        assert classify_from_folder(path) == ("Non-Fiction", "Biography & Memoir")
    
    def test_partial_match(self):
        """Test partial folder name matching"""
        path = Path("/library/my_science_fiction_books/book.epub")
        assert classify_from_folder(path) == ("Fiction", "Science Fiction")
    
    def test_case_insensitive(self):
        """Test case-insensitive folder matching"""
        path = Path("/library/SCIENCE FICTION/book.epub")
        assert classify_from_folder(path) == ("Fiction", "Science Fiction")
        
        path = Path("/library/Philosophy/book.epub")
        assert classify_from_folder(path) == ("Non-Fiction", "Philosophy & Religion")
    
    def test_nested_folders(self):
        """Test matching in nested directory structures"""
        path = Path("/home/user/books/fantasy/epic/book.epub")
        assert classify_from_folder(path) == ("Fiction", "Fantasy")
    
    def test_no_match(self):
        """Test when no folder matches"""
        path = Path("/library/random_folder/book.epub")
        assert classify_from_folder(path) == (None, None)
    
    def test_indian_comics(self):
        """Test specific Indian comics folders"""
        path = Path("/library/amar chitra katha/book.epub")
        assert classify_from_folder(path) == ("Comics & Graphic Novels", "Indian Comics")
        
        path = Path("/library/indian comics/book.epub")
        assert classify_from_folder(path) == ("Comics & Graphic Novels", "Indian Comics")


class TestClassifyFromTitle:
    """Test title/filename keyword classification"""
    
    def test_keyword_matching(self):
        """Test keyword matching in titles"""
        assert classify_from_title("Introduction to Physics") == ("Non-Fiction", "Science & Technology")
        assert classify_from_title("How to Succeed in Business") == ("Non-Fiction", "Self-Help")
    
    def test_case_insensitive(self):
        """Test case-insensitive title matching"""
        assert classify_from_title("TELL ME WHY BOOK") == ("Children", "Educational")
        assert classify_from_title("amar chitra katha - rama") == ("Comics & Graphic Novels", "Indian Comics")
    
    def test_no_match(self):
        """Test when no keywords match"""
        assert classify_from_title("Random Book Title") == (None, None)
        assert classify_from_title("") == (None, None)
        assert classify_from_title(None) == (None, None)


class TestTaxonomyStructure:
    """Test the taxonomy structure itself"""
    
    def test_all_categories_exist(self):
        """Test that expected categories exist"""
        expected_categories = [
            "Fiction", "Non-Fiction", "Children",
            "Comics & Graphic Novels", "Reference"
        ]
        for category in expected_categories:
            assert category in TAXONOMY
    
    def test_all_categories_have_other(self):
        """Test that all categories have an 'Other' subgenre"""
        for category, subgenres in TAXONOMY.items():
            assert "Other" in subgenres
    
    def test_fiction_subgenres(self):
        """Test that Fiction category has expected subgenres"""
        expected = ["Fantasy", "Science Fiction", "Mystery & Thriller", "Romance", "Horror"]
        for subgenre in expected:
            assert subgenre in TAXONOMY["Fiction"]
    
    def test_nonfiction_subgenres(self):
        """Test that Non-Fiction category has expected subgenres"""
        expected = ["Biography & Memoir", "History", "Science & Technology", 
                   "Business & Finance", "Self-Help", "Philosophy & Religion"]
        for subgenre in expected:
            assert subgenre in TAXONOMY["Non-Fiction"]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
