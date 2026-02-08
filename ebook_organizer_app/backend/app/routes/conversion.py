"""
Conversion API endpoints
Handles ebook format conversions using pure Python libraries.
No external dependencies like Calibre required.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
import os
import tempfile
import shutil
import zipfile
import struct

router = APIRouter()


class ConversionRequest(BaseModel):
    """Request model for conversion operations"""
    file_path: str
    output_path: Optional[str] = None  # If not provided, uses same directory


class ConversionResponse(BaseModel):
    """Response model for conversion operations"""
    success: bool
    input_path: str
    output_path: Optional[str] = None
    message: str
    error: Optional[str] = None


def extract_mobi_html(input_path: str) -> tuple[str, str, str, list]:
    """
    Extract HTML content from a MOBI file.
    Returns (title, author, html_content, images).
    """
    try:
        import mobi
        
        # Try extracting with mobi library
        extracted_dir, extracted_html = mobi.extract(input_path)
        
        if extracted_html and os.path.exists(extracted_html):
            with open(extracted_html, 'r', encoding='utf-8', errors='ignore') as f:
                html_content = f.read()
            
            from bs4 import BeautifulSoup
            soup = BeautifulSoup(html_content, 'html.parser')
            
            # Extract title
            title_tag = soup.find('title')
            title = title_tag.get_text().strip() if title_tag else os.path.splitext(os.path.basename(input_path))[0]
            
            # Extract author
            author = "Unknown Author"
            author_meta = soup.find('meta', attrs={'name': 'author'})
            if author_meta and author_meta.get('content'):
                author = author_meta['content']
            
            # Get images
            images = []
            if extracted_dir and os.path.isdir(extracted_dir):
                for root, dirs, files in os.walk(extracted_dir):
                    for file in files:
                        if file.lower().endswith(('.jpg', '.jpeg', '.png', '.gif')):
                            img_path = os.path.join(root, file)
                            with open(img_path, 'rb') as img_f:
                                images.append((file, img_f.read()))
            
            # Cleanup extracted directory
            if extracted_dir and os.path.exists(extracted_dir):
                shutil.rmtree(extracted_dir, ignore_errors=True)
            
            return title, author, html_content, images
            
    except Exception as e:
        # If mobi library fails, try direct reading for simple cases
        pass
    
    # Fallback: try to read basic info from the MOBI header
    try:
        title = os.path.splitext(os.path.basename(input_path))[0]
        
        with open(input_path, 'rb') as f:
            data = f.read()
        
        # Very basic MOBI parsing - look for HTML content after the header
        # MOBI files contain HTML embedded in them
        html_start = data.find(b'<html')
        if html_start == -1:
            html_start = data.find(b'<HTML')
        if html_start == -1:
            html_start = data.find(b'<!DOCTYPE')
        
        if html_start != -1:
            # Find the end of HTML
            html_end = data.rfind(b'</html>')
            if html_end == -1:
                html_end = data.rfind(b'</HTML>')
            if html_end == -1:
                html_end = data.rfind(b'</body>')
            if html_end == -1:
                html_end = len(data)
            else:
                html_end += 7  # Include the closing tag
            
            html_bytes = data[html_start:html_end]
            html_content = html_bytes.decode('utf-8', errors='ignore')
            
            # Clean up the HTML (remove binary garbage)
            html_content = ''.join(c if c.isprintable() or c in '\n\r\t' else '' for c in html_content)
            
            return title, "Unknown Author", html_content, []
        
        raise Exception("Could not find HTML content in MOBI file")
        
    except Exception as e:
        raise Exception(f"Failed to extract MOBI content: {str(e)}")


def create_epub_from_content(output_path: str, title: str, author: str, html_content: str, images: list) -> bool:
    """
    Create an EPUB file from HTML content.
    """
    from ebooklib import epub
    from bs4 import BeautifulSoup
    import uuid
    
    book = epub.EpubBook()
    book.set_identifier(str(uuid.uuid4()))
    book.set_title(title)
    book.set_language('en')
    book.add_author(author)
    
    # Clean up HTML for EPUB
    soup = BeautifulSoup(html_content, 'html.parser')
    
    # Get body content or full HTML
    body = soup.find('body')
    if body:
        body_content = ''.join(str(child) for child in body.children)
    else:
        body_content = html_content
    
    # Create main chapter
    chapter = epub.EpubHtml(title=title, file_name='content.xhtml', lang='en')
    chapter.content = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <title>{title}</title>
    <style type="text/css">
        body {{ font-family: serif; line-height: 1.6; margin: 1em; }}
        p {{ text-indent: 1.5em; margin: 0.5em 0; }}
        h1, h2, h3 {{ text-indent: 0; }}
    </style>
</head>
<body>
{body_content}
</body>
</html>'''
    
    book.add_item(chapter)
    
    # Add images if any
    for img_name, img_data in images:
        ext = os.path.splitext(img_name)[1].lower()
        media_types = {
            '.jpg': 'image/jpeg',
            '.jpeg': 'image/jpeg', 
            '.png': 'image/png',
            '.gif': 'image/gif',
        }
        media_type = media_types.get(ext, 'image/jpeg')
        
        img_item = epub.EpubImage()
        img_item.file_name = f'images/{img_name}'
        img_item.media_type = media_type
        img_item.content = img_data
        book.add_item(img_item)
    
    # Add navigation
    book.toc = [epub.Link('content.xhtml', title, 'content')]
    book.add_item(epub.EpubNcx())
    book.add_item(epub.EpubNav())
    
    # Set spine
    book.spine = ['nav', chapter]
    
    # Write EPUB
    epub.write_epub(output_path, book)
    
    return os.path.exists(output_path)


def convert_mobi_to_epub_pure_python(input_path: str, output_path: str) -> tuple[bool, str]:
    """
    Convert MOBI to EPUB using pure Python libraries.
    """
    try:
        # Check required libraries
        try:
            from ebooklib import epub
            from bs4 import BeautifulSoup
        except ImportError as e:
            return False, f"Missing required library: {e}. Run: pip install ebooklib beautifulsoup4 lxml"
        
        # Extract MOBI content
        title, author, html_content, images = extract_mobi_html(input_path)
        
        if not html_content or len(html_content.strip()) < 100:
            return False, "Failed to extract meaningful content from MOBI file"
        
        # Create EPUB
        success = create_epub_from_content(output_path, title, author, html_content, images)
        
        if success:
            return True, "Conversion successful"
        else:
            return False, "Failed to create EPUB file"
            
    except Exception as e:
        return False, f"Conversion error: {str(e)}"


@router.post("/mobi-to-epub")
async def convert_mobi_to_epub(request: ConversionRequest):
    """
    Convert a MOBI/AZW file to EPUB format using pure Python.
    
    No external tools required.
    """
    input_path = request.file_path
    
    # Validate input file exists
    if not os.path.exists(input_path):
        raise HTTPException(status_code=404, detail=f"File not found: {input_path}")
    
    # Validate file extension
    ext = os.path.splitext(input_path)[1].lower()
    if ext not in ['.mobi', '.azw', '.azw3']:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid input format: {ext}. Expected .mobi, .azw, or .azw3"
        )
    
    # Determine output path
    if request.output_path:
        output_path = request.output_path
    else:
        # Same directory, same name, .epub extension
        output_path = os.path.splitext(input_path)[0] + ".epub"
    
    # Check if output already exists
    if os.path.exists(output_path):
        raise HTTPException(
            status_code=409,
            detail=f"Output file already exists: {output_path}. Delete it first or specify a different output path."
        )
    
    # Run conversion
    success, message = convert_mobi_to_epub_pure_python(input_path, output_path)
    
    if success and os.path.exists(output_path):
        return ConversionResponse(
            success=True,
            input_path=input_path,
            output_path=output_path,
            message=f"Successfully converted to EPUB: {os.path.basename(output_path)}"
        )
    else:
        return ConversionResponse(
            success=False,
            input_path=input_path,
            output_path=None,
            message="Conversion failed",
            error=message
        )


@router.get("/check-requirements")
async def check_requirements():
    """
    Check if required Python libraries are available.
    """
    requirements = {
        'mobi': False,
        'ebooklib': False,
        'beautifulsoup4': False,
        'lxml': False,
    }
    
    try:
        import mobi
        requirements['mobi'] = True
    except ImportError:
        pass
    
    try:
        from ebooklib import epub
        requirements['ebooklib'] = True
    except ImportError:
        pass
    
    try:
        from bs4 import BeautifulSoup
        requirements['beautifulsoup4'] = True
    except ImportError:
        pass
    
    try:
        import lxml
        requirements['lxml'] = True
    except ImportError:
        pass
    
    # mobi is optional now, we have fallback
    core_requirements = requirements['ebooklib'] and requirements['beautifulsoup4']
    
    return {
        "all_available": core_requirements,
        "requirements": requirements,
        "install_command": "pip install mobi ebooklib beautifulsoup4 lxml" if not core_requirements else None
    }
