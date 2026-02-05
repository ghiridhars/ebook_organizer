"""
Open Library API Integration Service

Provides metadata lookup and classification using the Open Library API.
Includes caching and rate limiting to be respectful to the API.

API Documentation: https://openlibrary.org/dev/docs/api/search
"""

import urllib.request
import urllib.parse
import urllib.error
import json
import time
from typing import Optional, Dict, List, Tuple

from app.services.taxonomy import TAXONOMY, classify_genre


# =============================================================================
# CONFIGURATION
# =============================================================================
OPENLIBRARY_API_URL = "https://openlibrary.org/search.json"
API_TIMEOUT = 10  # seconds
API_RATE_LIMIT_DELAY = 0.1  # seconds between requests
API_CACHE: Dict[str, Optional[Dict]] = {}  # In-memory cache


# =============================================================================
# API FUNCTIONS
# =============================================================================

def query_openlibrary(title: str, author: Optional[str] = None) -> Optional[Dict]:
    """
    Query Open Library API to get book metadata.
    
    Args:
        title: Book title to search for
        author: Optional author name to narrow search
        
    Returns:
        dict: {'author': str, 'subjects': list, 'title': str} or None if not found
    """
    global API_CACHE
    
    # Check cache first
    cache_key = f"{title}|{author or ''}"
    if cache_key in API_CACHE:
        return API_CACHE[cache_key]
    
    try:
        # Build search query
        query_parts = []
        if title:
            # Use title: field for more accurate matching
            query_parts.append(f"title:{urllib.parse.quote(title)}")
        if author:
            query_parts.append(f"author:{urllib.parse.quote(author)}")
        
        if not query_parts:
            return None
        
        query = "+".join(query_parts)
        url = f"{OPENLIBRARY_API_URL}?q={query}&fields=title,author_name,subject&limit=1"
        
        # Make request with timeout
        req = urllib.request.Request(url, headers={'User-Agent': 'EbookOrganizer/1.0'})
        with urllib.request.urlopen(req, timeout=API_TIMEOUT) as response:
            data = json.loads(response.read().decode('utf-8'))
        
        # Rate limiting - be nice to the server
        time.sleep(API_RATE_LIMIT_DELAY)
        
        # Parse response
        if data.get('docs') and len(data['docs']) > 0:
            doc = data['docs'][0]
            result = {
                'title': doc.get('title'),
                'author': doc.get('author_name', [None])[0],
                'subjects': doc.get('subject', [])
            }
            API_CACHE[cache_key] = result
            return result
        
        # Cache negative result too
        API_CACHE[cache_key] = None
        return None
        
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError, 
            TimeoutError, Exception) as e:
        # Silently fail - API lookup is best-effort
        print(f"Open Library API error: {e}")
        API_CACHE[cache_key] = None
        return None


def classify_from_api_subjects(subjects: List[str]) -> Tuple[Optional[str], Optional[str]]:
    """
    Classify a book based on Open Library subjects.
    
    Args:
        subjects: List of subject strings from Open Library
        
    Returns:
        tuple: (Category, SubGenre) or (None, None) if not classifiable
    """
    if not subjects:
        return None, None
    
    # Join all subjects for scanning (case-insensitive)
    all_subjects_upper = ' | '.join(s.upper() for s in subjects)
    
    # Priority 1: Biography/Autobiography - these are very specific
    # Check ALL subjects first before anything else
    if 'BIOGRAPHY' in all_subjects_upper or 'AUTOBIOGRAPHY' in all_subjects_upper:
        return 'Non-Fiction', 'Biography & Memoir'
    
    # Priority 2: Check for explicit BISAC codes which are reliable
    for subject in subjects:
        subject_upper = subject.upper()
        
        # BISAC Fiction categories
        if subject_upper.startswith('FICTION /') or 'FICTION /' in subject_upper:
            if 'FANTASY' in subject_upper:
                return 'Fiction', 'Fantasy'
            if 'SCIENCE FICTION' in subject_upper:
                return 'Fiction', 'Science Fiction'
            if 'MYSTERY' in subject_upper or 'THRILLER' in subject_upper:
                return 'Fiction', 'Mystery & Thriller'
            if 'HORROR' in subject_upper:
                return 'Fiction', 'Horror'
            if 'ROMANCE' in subject_upper:
                return 'Fiction', 'Romance'
            if 'HISTORICAL' in subject_upper:
                return 'Fiction', 'Historical Fiction'
            if 'LITERARY' in subject_upper:
                return 'Fiction', 'Literary'
            # Generic fiction
            return 'Fiction', 'Literary'
        
        # BISAC Non-Fiction categories
        if 'SELF-HELP' in subject_upper:
            return 'Non-Fiction', 'Self-Help'
        if 'BUSINESS & ECONOMICS' in subject_upper:
            return 'Non-Fiction', 'Business & Finance'
        if 'TECHNOLOGY & ENGINEERING' in subject_upper:
            return 'Non-Fiction', 'Science & Technology'
        if ('HISTORY /' in subject_upper or subject_upper.startswith('HISTORY')) and len(subject) > 10:
            return 'Non-Fiction', 'History'
        if 'PSYCHOLOGY' in subject_upper:
            return 'Non-Fiction', 'Psychology'
        if 'RELIGION' in subject_upper or 'PHILOSOPHY' in subject_upper:
            return 'Non-Fiction', 'Philosophy & Religion'
        if 'HEALTH' in subject_upper or 'FITNESS' in subject_upper:
            return 'Non-Fiction', 'Health & Wellness'
        if 'COOKING' in subject_upper or 'COOKBOOK' in subject_upper:
            return 'Non-Fiction', 'Health & Wellness'
    
    # Priority 3: Check for common genre keywords in subjects
    for subject in subjects:
        subject_lower = subject.lower().strip()
        
        # Skip very generic subjects
        if len(subject_lower) < 4:
            continue
        if subject_lower in ['fiction', 'nonfiction', 'non-fiction', 'book', 'books', 'history']:
            continue
        
        # Fiction genres
        if 'fantasy' in subject_lower:
            return 'Fiction', 'Fantasy'
        if 'science fiction' in subject_lower or 'sci-fi' in subject_lower:
            return 'Fiction', 'Science Fiction'
        if 'mystery' in subject_lower or 'detective' in subject_lower:
            return 'Fiction', 'Mystery & Thriller'
        if 'thriller' in subject_lower or 'suspense' in subject_lower:
            return 'Fiction', 'Mystery & Thriller'
        if 'horror' in subject_lower:
            return 'Fiction', 'Horror'
        if 'romance' in subject_lower:
            return 'Fiction', 'Romance'
        
        # Non-fiction genres
        if 'programming' in subject_lower or 'computer' in subject_lower:
            return 'Non-Fiction', 'Science & Technology'
        if 'mathematics' in subject_lower or 'physics' in subject_lower:
            return 'Non-Fiction', 'Science & Technology'
    
    # Priority 4: Try to match against taxonomy aliases
    best_match = (None, None)
    best_priority = 999
    
    # Define priority for categories (lower = higher priority)
    category_priority = {
        'Non-Fiction': 1,
        'Fiction': 2,
        'Children': 3,
        'Comics & Graphic Novels': 4,
        'Reference': 5
    }
    
    for subject in subjects:
        subject_lower = subject.lower().strip()
        
        # Skip very generic subjects
        if len(subject_lower) < 4:
            continue
        if subject_lower in ['fiction', 'nonfiction', 'non-fiction', 'book', 'books', 'history']:
            continue
        
        # Try to match against taxonomy
        for category, subgenres in TAXONOMY.items():
            for subgenre, aliases in subgenres.items():
                if subgenre == "Other":
                    continue
                
                # Check if subject matches subgenre or any alias
                matched = False
                if subject_lower == subgenre.lower():
                    matched = True
                else:
                    for alias in aliases:
                        if alias.lower() in subject_lower or subject_lower in alias.lower():
                            matched = True
                            break
                
                if matched:
                    priority = category_priority.get(category, 10)
                    if priority < best_priority:
                        best_priority = priority
                        best_match = (category, subgenre)
    
    return best_match


def lookup_book_metadata(filepath_or_title: str, existing_author: Optional[str] = None) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """
    Look up book metadata using Open Library API.
    
    Args:
        filepath_or_title: File path or cleaned title to search
        existing_author: Author name if already known (for better search)
        
    Returns:
        tuple: (author, category, subgenre) - any may be None if not found
    """
    # If filepath, extract clean title from filename
    if '/' in filepath_or_title or '\\' in filepath_or_title:
        from pathlib import Path
        import re
        
        filepath = Path(filepath_or_title)
        filename = filepath.stem
        
        # Remove common junk patterns
        filename = re.sub(r'@\w+', '', filename)
        filename = re.sub(r'\s*\(\s*PDFDrive\s*\)\s*', '', filename, flags=re.IGNORECASE)
        filename = re.sub(r'\s*\(\s*z-lib\.org\s*\)\s*', '', filename, flags=re.IGNORECASE)
        filename = re.sub(r'\[.*?\]', '', filename)
        filename = re.sub(r'\(.*?\)', '', filename)
        filename = re.sub(r'_+', ' ', filename)
        filename = re.sub(r'\s*-\s*', ' ', filename)
        filename = re.sub(r'\b(19|20)\d{2}\b', '', filename)
        filename = re.sub(r'\b(epub|pdf|mobi|azw3?)\b', '', filename, flags=re.IGNORECASE)
        filename = re.sub(r'\s+', ' ', filename).strip()
        
        if len(filename) < 3:
            return None, None, None
        
        title = filename
    else:
        title = filepath_or_title
    
    # Query the API
    result = query_openlibrary(title, existing_author)
    if not result:
        return None, None, None
    
    # Get author from API if we don't have one
    api_author = result.get('author')
    
    # Classify based on subjects
    subjects = result.get('subjects', [])
    category, subgenre = classify_from_api_subjects(subjects)
    
    return api_author, category, subgenre


def clear_cache():
    """Clear the API cache (useful for testing)"""
    global API_CACHE
    API_CACHE.clear()


def get_cache_size() -> int:
    """Get the number of cached API results"""
    return len(API_CACHE)
