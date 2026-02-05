"""
Ebook Taxonomy and Classification System

This module contains the hierarchical taxonomy structure and classification
logic for organizing ebooks into Category/SubGenre hierarchies.

Ported from: online-library-organizer/ebook_organizer.py
"""

import re
from typing import Tuple, Optional
from pathlib import Path


# =============================================================================
# HIERARCHICAL TAXONOMY
# =============================================================================
# Structure: Category -> SubGenre -> [aliases that map to this subgenre]
# Aliases include Open Library subject terms for better API matching
# The "Other" subgenre in each category is the fallback for unrecognized genres

TAXONOMY = {
    "Fiction": {
        "Fantasy": [
            "fantasy", "fantasy fiction", "epic fantasy", "urban fantasy", "high fantasy",
            "dark fantasy", "sword and sorcery", "mythic fiction", "fantasy, epic",
            "fiction, fantasy, epic", "fiction, fantasy, general", "fantastic fiction",
            "english fantasy fiction", "magic", "wizards", "dragons"
        ],
        "Science Fiction": [
            "science fiction", "sci-fi", "sf", "scifi", "speculative fiction",
            "cyberpunk", "space opera", "dystopian", "post-apocalyptic",
            "fiction, science fiction", "science fiction, general"
        ],
        "Mystery & Thriller": [
            "mystery", "thriller", "suspense", "crime", "detective",
            "crime fiction", "noir", "psychological thriller", "legal thriller",
            "mystery and detective stories", "crime & mystery", "thrillers",
            "detective and mystery stories", "murder", "mystery fiction"
        ],
        "Horror": [
            "horror", "gothic", "supernatural", "dark fiction", "ghost stories",
            "horror fiction", "horror tales", "occult fiction"
        ],
        "Romance": [
            "romance", "romantic fiction", "love story", "romantic suspense",
            "historical romance", "contemporary romance", "love", "romance fiction"
        ],
        "Historical Fiction": [
            "historical fiction", "historical novel", "historical",
            "fiction, historical", "history fiction"
        ],
        "Literary": [
            "literary fiction", "literary", "classic", "classics", "classic fiction",
            "literature", "fiction in english", "english fiction", "english literature",
            "american fiction", "american literature", "contemporary fiction",
            "modern fiction", "novel", "novels", "general fiction", "fiction"
        ],
        "Humor": [
            "humor", "humour", "comedy", "satire", "humorous fiction",
            "wit and humor", "humorous stories"
        ],
        "Adventure": [
            "adventure", "action", "action adventure", "adventure fiction",
            "adventure stories", "sea stories", "war stories"
        ],
        "Short Stories": [
            "short stories", "short fiction", "anthology", "collected stories",
            "short stories, english", "fiction, anthologies"
        ],
        "Drama": [
            "drama", "plays", "family saga", "domestic fiction", "theatrical"
        ],
        "Poetry": [
            "poetry", "poems", "verse", "poetic works", "english poetry",
            "american poetry"
        ],
        "Young Adult Fiction": [
            "young adult fiction", "ya fiction", "teen fiction", "teenage",
            "coming of age", "juvenile fiction", "children's fiction"
        ],
        "Other": []
    },
    "Non-Fiction": {
        "Biography & Memoir": [
            "biography", "autobiography", "memoir", "memoirs", "biographical",
            "life story", "personal narrative", "biography & autobiography",
            "biographies", "personal memoirs"
        ],
        "History": [
            "history", "historical", "ancient history", "world history",
            "military history", "cultural history", "medieval history", "modern history",
            "ancient civilization", "archaeology", "world war", "wars",
            "history, general", "united states history", "european history",
            "indian history", "asian history"
        ],
        "Science & Technology": [
            "science", "physics", "chemistry", "biology", "astronomy",
            "natural science", "earth science", "environmental science",
            "popular science", "mathematics", "math", "maths",
            "technology", "computer science", "programming", "engineering",
            "artificial intelligence", "software", "electronics", "computers",
            "technology & engineering", "science, general"
        ],
        "Business & Finance": [
            "business", "economics", "finance", "management", "entrepreneurship",
            "investing", "marketing", "leadership", "money", "business & economics",
            "success in business", "business success", "commerce"
        ],
        "Self-Help": [
            "self-help", "self help", "personal development", "motivation",
            "self improvement", "self-improvement", "productivity", "success", "habits",
            "self-actualization", "self-culture", "conduct of life", "inspiration"
        ],
        "Philosophy & Religion": [
            "philosophy", "philosophical", "ethics", "logic", "metaphysics",
            "existentialism", "stoicism", "religion", "spirituality", "spiritual",
            "theology", "mysticism", "meditation", "yoga", "mythology",
            "vedanta", "hinduism", "buddhism", "islam", "christianity",
            "religious aspects", "philosophy, general"
        ],
        "Psychology": [
            "psychology", "psychiatry", "mental health", "cognitive science",
            "behavioral science", "psychoanalysis", "neuroscience",
            "psychology, general", "psychological aspects"
        ],
        "Politics & Society": [
            "politics", "political science", "sociology", "social science",
            "current affairs", "government", "international relations",
            "anthropology", "cultural studies", "social life and customs",
            "politics and government"
        ],
        "Arts & Entertainment": [
            "art", "music", "fine arts", "art history", "photography",
            "architecture", "design", "film", "cinema", "performing arts",
            "art instruction", "graphic design", "dance", "fashion",
            "painting", "music theory"
        ],
        "Health & Wellness": [
            "health", "fitness", "medicine", "nutrition", "diet",
            "exercise", "wellness", "medical", "cooking", "cookbooks",
            "mental health", "health & fitness"
        ],
        "Travel & Culture": [
            "travel", "geography", "culture", "tourism", "exploration",
            "travel writing", "voyages and travels"
        ],
        "Essays & Criticism": [
            "essays", "essay", "collected essays", "literary criticism",
            "criticism", "literary essays", "book reviews"
        ],
        "Other": []
    },
    "Children": {
        "Picture Books": [
            "picture book", "picture books", "baby books", "infancy",
            "bedtime", "bedtime stories", "stories in rhyme"
        ],
        "Stories": [
            "children's fiction", "children's stories", "children's literature",
            "fairy tales", "fables", "juvenile literature", "kids books"
        ],
        "Educational": [
            "children's educational", "educational", "learning",
            "young readers nonfiction", "children's nonfiction", "juvenile nonfiction"
        ],
        "Young Adult": [
            "young adult", "ya", "teen", "teenage", "young adult fiction",
            "coming of age"
        ],
        "Other": []
    },
    "Comics & Graphic Novels": {
        "Graphic Novels": [
            "graphic novel", "graphic novels", "comics", "comic book",
            "sequential art", "comic books, strips, etc"
        ],
        "Manga": [
            "manga", "anime", "japanese comics", "manhwa", "manhua"
        ],
        "Indian Comics": [
            "indian comics", "amar chitra katha", "panchatantra",
            "indian mythology comics"
        ],
        "Superheroes": [
            "superheroes", "superhero comics", "marvel", "dc comics"
        ],
        "Other": []
    },
    "Reference": {
        "Encyclopedias": [
            "encyclopedia", "encyclopaedia", "encyclopedias", "dictionaries"
        ],
        "Textbooks": [
            "textbook", "textbooks", "academic", "coursebook", "study guide",
            "educational material", "course material"
        ],
        "Guides & Handbooks": [
            "handbook", "guide", "reference", "manual", "how-to",
            "almanac", "atlas", "dictionary"
        ],
        "Other": []
    }
}

# Folder name to (Category, SubGenre) mapping
# Maps source folder names to their canonical taxonomy location
FOLDER_TO_TAXONOMY = {
    # Comics (use full names only to avoid partial match issues)
    'amar chitra katha': ('Comics & Graphic Novels', 'Indian Comics'),
    'indian comics': ('Comics & Graphic Novels', 'Indian Comics'),
    'panchatantra': ('Comics & Graphic Novels', 'Indian Comics'),
    'comics': ('Comics & Graphic Novels', 'Graphic Novels'),
    'graphic novels': ('Comics & Graphic Novels', 'Graphic Novels'),
    'manga': ('Comics & Graphic Novels', 'Manga'),
    
    # History
    'historic rare': ('Non-Fiction', 'History'),
    'history': ('Non-Fiction', 'History'),
    'indian history': ('Non-Fiction', 'History'),
    
    # Philosophy & Religion
    'j krishnamurthi': ('Non-Fiction', 'Philosophy & Religion'),
    'j krishnamurti': ('Non-Fiction', 'Philosophy & Religion'),
    'ayn rand': ('Non-Fiction', 'Philosophy & Religion'),
    'philosophy': ('Non-Fiction', 'Philosophy & Religion'),
    'osho': ('Non-Fiction', 'Philosophy & Religion'),
    'spirituality': ('Non-Fiction', 'Philosophy & Religion'),
    'vedanta': ('Non-Fiction', 'Philosophy & Religion'),
    'religion': ('Non-Fiction', 'Philosophy & Religion'),
    
    # Children
    'tell me why': ('Children', 'Educational'),
    'how it works': ('Non-Fiction', 'Science & Technology'),
    'kids': ('Children', 'Stories'),
    'children': ('Children', 'Stories'),
    
    # Science & Technology
    'science': ('Non-Fiction', 'Science & Technology'),
    'programming': ('Non-Fiction', 'Science & Technology'),
    'technology': ('Non-Fiction', 'Science & Technology'),
    'vedic maths': ('Non-Fiction', 'Science & Technology'),
    'vedic math': ('Non-Fiction', 'Science & Technology'),
    
    # Fiction categories
    'fiction': ('Fiction', 'Literary'),
    'novels': ('Fiction', 'Literary'),
    'sci-fi': ('Fiction', 'Science Fiction'),
    'science fiction': ('Fiction', 'Science Fiction'),
    'fantasy': ('Fiction', 'Fantasy'),
    'mystery': ('Fiction', 'Mystery & Thriller'),
    'thriller': ('Fiction', 'Mystery & Thriller'),
    'crime': ('Fiction', 'Mystery & Thriller'),
    'romance': ('Fiction', 'Romance'),
    'horror': ('Fiction', 'Horror'),
    'adventure': ('Fiction', 'Adventure'),
    'poetry': ('Fiction', 'Poetry'),
    
    # Biography
    'biography': ('Non-Fiction', 'Biography & Memoir'),
    'biographies': ('Non-Fiction', 'Biography & Memoir'),
    'autobiography': ('Non-Fiction', 'Biography & Memoir'),
    
    # Business & Self-help
    'business': ('Non-Fiction', 'Business & Finance'),
    'finance': ('Non-Fiction', 'Business & Finance'),
    'self-help': ('Non-Fiction', 'Self-Help'),
    'self help': ('Non-Fiction', 'Self-Help'),
    
    # Arts
    'art': ('Non-Fiction', 'Arts & Entertainment'),
    'music': ('Non-Fiction', 'Arts & Entertainment'),
    
    # Reference
    'textbooks': ('Reference', 'Textbooks'),
    'encyclopedia': ('Reference', 'Encyclopedias'),
}

# Blacklist patterns for genre values (used before taxonomy lookup)
GENRE_BLACKLIST_PATTERNS = [
    r'^https?',           # URLs
    r'^www\.',            # URLs
    r'archive\.org',      # Archive.org references
    r'^IndirectObject',   # PyPDF2 bug
    r'^\d+$',             # Pure numbers
    r'^.{1,2}$',          # Too short (1-2 chars)
    r' -- ',              # Library of Congress format
]

# Keywords in title/filename that hint at category
TITLE_KEYWORDS = {
    ('Fiction', 'Science Fiction'): ['sci-fi', 'starship', 'alien invasion', 'space station'],
    ('Fiction', 'Fantasy'): ['sword and sorcery', 'epic fantasy', 'dark lord'],
    ('Fiction', 'Mystery & Thriller'): ['murder mystery', 'detective story', 'whodunit'],
    ('Fiction', 'Horror'): ['horror stories', 'haunted house', 'supernatural horror'],
    ('Non-Fiction', 'History'): ['world history', 'ancient history', 'military history'],
    ('Non-Fiction', 'Biography & Memoir'): ['biography of', 'life of', 'autobiography of'],
    ('Non-Fiction', 'Philosophy & Religion'): ['philosophy of', 'ethics of'],
    ('Non-Fiction', 'Science & Technology'): ['introduction to physics', 'chemistry basics'],
    ('Non-Fiction', 'Self-Help'): ['how to succeed', 'self improvement'],
    ('Non-Fiction', 'Business & Finance'): ['business strategy', 'financial planning'],
    ('Children', 'Educational'): ['tell me why', 'how it works', 'for kids'],
    ('Comics & Graphic Novels', 'Indian Comics'): ['amar chitra katha', 'panchatantra tales'],
}


# =============================================================================
# CLASSIFICATION FUNCTIONS
# =============================================================================

def classify_genre(raw_genre: Optional[str]) -> Tuple[Optional[str], Optional[str]]:
    """
    Classify a raw genre string into the canonical taxonomy (case-insensitive).
    
    Args:
        raw_genre: Raw genre string from embedded metadata
        
    Returns:
        tuple: (Category, SubGenre) or (None, None) if not classifiable
    """
    if not raw_genre:
        return None, None
    
    # Normalize to lowercase for case-insensitive matching
    genre_lower = raw_genre.lower().strip()
    
    # Check against blacklist patterns first
    for pattern in GENRE_BLACKLIST_PATTERNS:
        if re.match(pattern, raw_genre, re.IGNORECASE):
            return None, None
    
    # Too long - likely a description, not a genre
    if len(raw_genre) > 50:
        return None, None
    
    # Search through taxonomy for a match
    for category, subgenres in TAXONOMY.items():
        for subgenre, aliases in subgenres.items():
            if subgenre == "Other":
                continue  # Skip "Other" - it's a fallback only
            
            # Check if raw genre matches subgenre name
            if genre_lower == subgenre.lower():
                return category, subgenre
            
            # Check if raw genre matches any alias
            for alias in aliases:
                if genre_lower == alias.lower():
                    return category, subgenre
                # Partial match - genre contains alias (for compound genres)
                if alias.lower() in genre_lower and len(alias) > 4:
                    return category, subgenre
    
    # Special handling for broad categories
    if 'fiction' in genre_lower and 'non' not in genre_lower:
        return 'Fiction', 'Other'
    if 'non-fiction' in genre_lower or 'nonfiction' in genre_lower:
        return 'Non-Fiction', 'Other'
    
    return None, None


def classify_from_folder(filepath: Path) -> Tuple[Optional[str], Optional[str]]:
    """
    Try to classify from parent folder names (case-insensitive).
    
    Args:
        filepath: Path to the ebook file
        
    Returns:
        tuple: (Category, SubGenre) or (None, None) if not found
    """
    for parent in filepath.parents:
        folder_name = parent.name.lower()
        
        # Direct match in folder mapping (case-insensitive)
        if folder_name in FOLDER_TO_TAXONOMY:
            return FOLDER_TO_TAXONOMY[folder_name]
        
        # Partial match - folder contains key (case-insensitive)
        for key, (category, subgenre) in FOLDER_TO_TAXONOMY.items():
            if key.lower() in folder_name:
                return category, subgenre
    
    return None, None


def classify_from_title(title: Optional[str]) -> Tuple[Optional[str], Optional[str]]:
    """
    Try to classify from title keywords (case-insensitive).
    
    Args:
        title: Book title or filename
        
    Returns:
        tuple: (Category, SubGenre) or (None, None) if not found
    """
    if not title:
        return None, None
    
    title_lower = title.lower()
    
    for (category, subgenre), keywords in TITLE_KEYWORDS.items():
        for keyword in keywords:
            # Case-insensitive keyword matching
            if keyword.lower() in title_lower:
                return category, subgenre
    
    return None, None
