"""
Metadata ClassifierService

Handles intelligent classification of ebooks using multiple strategies:
1. Embedded metadata (genre/subject fields)
2. Folder-based classification
3. Open Library API lookup
4. Title/filename keyword analysis

Also provides author validation and extraction utilities.
"""

import re
from typing import Optional, Tuple
from pathlib import Path
from dataclasses import dataclass

from app.services.taxonomy import (
    classify_genre,
    classify_from_folder,
    classify_from_title
)
from app.services.openlibrary_service import lookup_book_metadata


# =============================================================================
# AUTHOR VALIDATION
# =============================================================================

# Blacklist for invalid/junk author values
AUTHOR_BLACKLIST = {
    'unknown', 'unknown author', 'none', 'null', 'n/a', 'na',
    'admin', 'administrator', 'user', 'owner',
    'author', 'writer', 'editor',
    'various', 'various authors', 'anonymous',
    'a', 'b', 'c', 'x', 'y', 'z',  # Single letters
    # PDF/ebook tool artifacts
    'nullobject', 'null object',
    'calibre', 'calibre user',
    'acrobat', 'adobe',
    # Website watermarks
    'gnv64', 'mobilism', 'libgen', 'z-library',
    'downmagaz.net', 'downmagaz', 'useruplod.net', 'userupload',
}

# Patterns that indicate junk author values
AUTHOR_BLACKLIST_PATTERNS = [
    r'^IndirectObject',   # PyPDF2 bug
    r'^\d+$',             # Pure numbers  
    r'^.{1,2}$',          # Too short (1-2 chars)
    r'^https?://',        # URLs
    r'^www\.',            # URLs
    r'\.com$',            # Domain names
    r'\.net$',            # Domain names
    r'\.org$',            # Domain names
]

# Filename patterns for extracting author/title
FILENAME_PATTERNS = [
    # "Author - Title" pattern (common for epubs)
    r'^(?P<author>[^-]+?)\s*[-–—]\s*(?P<title>.+)$',
    
    # "Title -Author" pattern (another common style)
    r'^(?P<title>.+?)\s*[-–—]\s*(?P<author>[^-]+)$',
    
    # "Title (Author)" pattern
    r'^(?P<title>.+?)\s*\((?P<author>[^)]+)\)$',
    
    # "Title [Author]" pattern
    r'^(?P<title>.+?)\s*\[(?P<author>[^\]]+)\]$',
    
    # "Title_Author_Publisher_Year" pattern (underscores)
    r'^(?P<title>.+?)_(?P<author>[A-Z][a-z]+(?:_[A-Z][a-z]+)+)(?:_\d{4})?(?:_.+)?$',
]


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def is_printable_text(text: Optional[str]) -> bool:
    """Check if text is valid printable string (not binary garbage)."""
    if not text or not isinstance(text, str):
        return False
    
    # Check for common binary garbage patterns
    if text.startswith(("b'", 'b"')):
        return False
    
    # Check for hex escape sequences (binary data)
    if r'\x' in text or '\\x' in text:
        return False
    
    # Check ratio of printable characters
    printable_count = sum(1 for c in text if c.isprintable() or c.isspace())
    if len(text) > 0 and printable_count / len(text) < 0.8:
        return False
    
    # Check for too many non-ASCII characters in a row
    non_ascii_streak = 0
    max_streak = 0
    for c in text:
        if ord(c) > 127:
            non_ascii_streak += 1
            max_streak = max(max_streak, non_ascii_streak)
        else:
            non_ascii_streak = 0
    
    # Allow some non-ASCII (for names like Schrödinger) but not garbage
    if max_streak > 5:
        return False
    
    return True


def is_valid_author(author: Optional[str]) -> bool:
    """Check if author value is valid (not junk)."""
    if not author:
        return False
    
    # First check if it's printable text at all
    if not is_printable_text(author):
        return False
    
    author_lower = author.lower().strip()
    
    # Check blacklist
    if author_lower in AUTHOR_BLACKLIST:
        return False
    
    # Check patterns
    for pattern in AUTHOR_BLACKLIST_PATTERNS:
        if re.match(pattern, author, re.IGNORECASE):
            return False
    
    return True


def clean_author_name(author: Optional[str]) -> Optional[str]:
    """Clean up author name formatting."""
    if not author:
        return None
    
    # Remove common suffixes like "author", "editor"
    author = re.sub(r'\s+(author|editor|translator|compiled by)\s*$', '', author, flags=re.IGNORECASE)
    
    # Remove birth/death years like "1835-1910" or "1954-"
    author = re.sub(r',?\s*\d{4}\s*-\s*\d{0,4}\s*$', '', author)
    
    # Remove trailing punctuation
    author = author.rstrip('.,;:')
    
    return author.strip() if author.strip() else None


def extract_from_filename(filepath: Path) -> Optional[str]:
    """Extract author from filename using pattern matching."""
    # Get filename without extension
    filename = filepath.stem
    
    # Clean up filename - remove common junk
    filename = re.sub(r'@\w+', '', filename)  # Remove @mentions
    filename = re.sub(r'\s*\(\s*PDFDrive\s*\)\s*', '', filename, flags=re.IGNORECASE)
    filename = re.sub(r'\s*\(\s*z-lib\.org\s*\)\s*', '', filename, flags=re.IGNORECASE)
    filename = re.sub(r'_+', ' ', filename)  # Replace underscores with spaces
    filename = filename.strip()
    
    for pattern in FILENAME_PATTERNS:
        match = re.match(pattern, filename, re.IGNORECASE)
        if match:
            groups = match.groupdict()
            author = groups.get('author', '').strip()
            title = groups.get('title', '').strip()
            
            # Validate: author should look like a name
            if author:
                word_count = len(author.split())
                
                # Heuristic: author names typically have 1-4 words
                if word_count <= 4:
                    # If the "author" part is longer than "title", they might be swapped
                    if title and len(author) > len(title) * 1.5 and word_count > 2:
                        # Swap - this is probably "Title - Author" not "Author - Title"
                        author, title = title, author
                    
                    # Clean up author
                    author = author.replace('_', ' ').strip()
                    
                    # Validate cleaned author
                    if is_valid_author(author):
                        return author
    
    return None


# =============================================================================
# CLASSIFICATION
# =============================================================================

@dataclass
class ClassificationResult:
    """Result of ebook classification"""
    category: Optional[str] = None
    sub_genre: Optional[str] = None
    author: Optional[str] = None
    metadata_source: str = "unknown"  # embedded, filename, folder, api, title, unknown
    

def classify_book(
    filepath: Path,
    embedded_genre: Optional[str] = None,
    embedded_author: Optional[str] = None
) -> ClassificationResult:
    """
    Classify a book into the taxonomy hierarchy using multiple strategies.
    
    Priority:
    1. Embedded metadata (if valid and in taxonomy)
    2. Folder-based classification
    3. Open Library API lookup (if enabled)
    4. Title/filename keyword classification (last resort)
    5. Fallback to uncategorized
    
    Args:
        filepath: Path to the ebook file
        embedded_genre: Genre from embedded metadata (optional)
        embedded_author: Author from embedded metadata (optional)
        
    Returns:
        ClassificationResult with category, sub_genre, author, and source
    """
    result = ClassificationResult()
    
    # Validate and clean embedded author
    if embedded_author and is_printable_text(embedded_author):
        cleaned_author = clean_author_name(embedded_author)
        if cleaned_author and is_valid_author(cleaned_author):
            result.author = cleaned_author
            result.metadata_source = "embedded"
    
    # Step 1: Try embedded genre
    if embedded_genre and is_printable_text(embedded_genre):
        category, subgenre = classify_genre(embedded_genre)
        if category and subgenre:
            result.category = category
            result.sub_genre = subgenre
            if result.metadata_source == "unknown":
                result.metadata_source = "embedded"
            return result
    
    # Step 2: Try folder-based classification
    category, subgenre = classify_from_folder(filepath)
    if category and subgenre:
        result.category = category
        result.sub_genre = subgenre
        if result.metadata_source == "unknown":
            result.metadata_source = "folder"
        return result
    
    # Step 3: Try Open Library API
    api_author, api_category, api_subgenre = lookup_book_metadata(str(filepath), result.author)
    if api_category and api_subgenre:
        result.category = api_category
        result.sub_genre = api_subgenre
        # Also use API author if we don't have a valid one
        if not result.author and api_author and is_valid_author(api_author):
            result.author = api_author
        result.metadata_source = "api"
        return result
    
    # Step 4: Try title/filename keywords (last resort - prone to false positives)
    category, subgenre = classify_from_title(filepath.stem)
    if category and subgenre:
        result.category = category
        result.sub_genre = subgenre
        if result.metadata_source == "unknown":
            result.metadata_source = "title"
        return result
    
    # Step 5: If still no author, try filename extraction
    if not result.author:
        filename_author = extract_from_filename(filepath)
        if filename_author:
            result.author = filename_author
            if result.metadata_source == "unknown":
                result.metadata_source = "filename"
    
    # No classification found - return incomplete result
    return result
