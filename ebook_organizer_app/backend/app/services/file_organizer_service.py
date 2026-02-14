"""
File Organizer Service

Provides ebook file reorganization capabilities:
- Compute target paths based on Category/SubGenre/Author folder structure
- Generate a preview of planned file moves/copies
- Execute move/copy operations with DB path updates
"""

import os
import shutil
from typing import List, Dict, Optional
from dataclasses import dataclass, field
from sqlalchemy.orm import Session

from app.models.database import Ebook
from app.services.metadata_classifier import is_valid_author, clean_author_name


UNKNOWN_AUTHOR = "Unknown Author"
UNCLASSIFIED_FOLDER = "Unclassified"


@dataclass
class PlannedMove:
    """A single planned file move/copy operation."""
    ebook_id: int
    source_path: str
    target_path: str
    title: str
    author: str
    category: str
    sub_genre: str


@dataclass
class ReorganizePlan:
    """Full reorganization plan (preview)."""
    destination: str
    operation: str
    total_files: int = 0
    classified_files: int = 0
    unclassified_files: int = 0
    collisions: int = 0
    planned_moves: List[PlannedMove] = None

    def __post_init__(self):
        if self.planned_moves is None:
            self.planned_moves = []


@dataclass
class ReorganizeResult:
    """Result of reorganization execution."""
    total_processed: int = 0
    succeeded: int = 0
    skipped: int = 0
    failed: int = 0
    errors: List[str] = None
    path_mappings: Dict[str, str] = None

    def __post_init__(self):
        if self.errors is None:
            self.errors = []
        if self.path_mappings is None:
            self.path_mappings = {}


def _sanitize_folder_name(name: str) -> str:
    """Remove characters that are invalid in folder/file names on Windows."""
    sanitized = name
    for char in ['\\', '/', ':', '*', '?', '"', '<', '>', '|']:
        sanitized = sanitized.replace(char, '_')
    sanitized = ' '.join(sanitized.split())
    return sanitized.strip() or "Unknown"


def _resolve_collision(target_path: str) -> str:
    """If target_path already exists, append numeric suffix before extension."""
    if not os.path.exists(target_path):
        return target_path

    base, ext = os.path.splitext(target_path)
    counter = 1
    while os.path.exists(f"{base} ({counter}){ext}"):
        counter += 1
    return f"{base} ({counter}){ext}"


def _get_author_folder(ebook: Ebook) -> str:
    """Determine author folder name. Returns UNKNOWN_AUTHOR if invalid."""
    author = ebook.author
    if author:
        cleaned = clean_author_name(author)
        if cleaned and is_valid_author(cleaned):
            return _sanitize_folder_name(cleaned)
    return UNKNOWN_AUTHOR


def _is_classified(ebook: Ebook) -> bool:
    """Check if ebook has both category and sub_genre set."""
    return bool(
        ebook.category and ebook.category.strip()
        and ebook.sub_genre and ebook.sub_genre.strip()
    )


def compute_target_path(
    ebook: Ebook,
    destination: str,
    is_classified: bool,
) -> str:
    """
    Build the target file path for a single ebook.

    Classified:   destination/Category/SubGenre/Author/filename.ext
    Unclassified: destination/Unclassified/filename.ext
    """
    filename = os.path.basename(ebook.cloud_file_path)

    if is_classified:
        category = _sanitize_folder_name(ebook.category)
        sub_genre = _sanitize_folder_name(ebook.sub_genre)
        author_folder = _get_author_folder(ebook)
        return os.path.join(destination, category, sub_genre, author_folder, filename)
    else:
        return os.path.join(destination, UNCLASSIFIED_FOLDER, filename)


def generate_reorganize_plan(
    db: Session,
    destination: str,
    source_path: Optional[str] = None,
    include_unclassified: bool = False,
    operation: str = "move",
) -> ReorganizePlan:
    """
    Generate a preview plan without executing any file operations.

    Args:
        db: Database session
        destination: Target root folder
        source_path: Optional source path prefix filter
        include_unclassified: Whether to include unclassified books
        operation: "move" or "copy"

    Returns:
        ReorganizePlan with list of PlannedMove objects
    """
    plan = ReorganizePlan(destination=destination, operation=operation)

    query = db.query(Ebook)
    if source_path:
        query = query.filter(Ebook.cloud_file_path.like(f"{source_path}%"))

    ebooks = query.all()
    collisions = 0

    for ebook in ebooks:
        if not ebook.cloud_file_path:
            continue

        classified = _is_classified(ebook)

        if not classified and not include_unclassified:
            continue

        target = compute_target_path(ebook, destination, classified)
        resolved = _resolve_collision(target)
        if resolved != target:
            collisions += 1

        author_display = _get_author_folder(ebook)

        move = PlannedMove(
            ebook_id=ebook.id,
            source_path=ebook.cloud_file_path,
            target_path=resolved,
            title=ebook.title or os.path.basename(ebook.cloud_file_path),
            author=author_display,
            category=ebook.category or "",
            sub_genre=ebook.sub_genre or "",
        )
        plan.planned_moves.append(move)

        if classified:
            plan.classified_files += 1
        else:
            plan.unclassified_files += 1

    plan.total_files = len(plan.planned_moves)
    plan.collisions = collisions
    return plan


def execute_reorganization(
    db: Session,
    destination: str,
    source_path: Optional[str] = None,
    include_unclassified: bool = False,
    operation: str = "move",
) -> ReorganizeResult:
    """
    Execute file move/copy and update database paths.

    Args:
        db: Database session
        destination: Target root folder
        source_path: Optional source path prefix filter
        include_unclassified: Whether to include unclassified books
        operation: "move" or "copy"

    Returns:
        ReorganizeResult with counts and path mappings for frontend sync
    """
    if operation not in ("move", "copy"):
        raise ValueError(f"Invalid operation: {operation}. Must be 'move' or 'copy'.")

    result = ReorganizeResult()

    query = db.query(Ebook)
    if source_path:
        query = query.filter(Ebook.cloud_file_path.like(f"{source_path}%"))

    ebooks = query.all()

    for ebook in ebooks:
        try:
            if not ebook.cloud_file_path:
                result.skipped += 1
                continue

            classified = _is_classified(ebook)
            if not classified and not include_unclassified:
                result.skipped += 1
                continue

            source = ebook.cloud_file_path

            if not os.path.isfile(source):
                result.skipped += 1
                result.errors.append(f"Source not found: {source}")
                continue

            target = compute_target_path(ebook, destination, classified)
            target = _resolve_collision(target)

            os.makedirs(os.path.dirname(target), exist_ok=True)

            if operation == "move":
                shutil.move(source, target)
            else:
                shutil.copy2(source, target)

            old_path = ebook.cloud_file_path

            # Update DB paths only for move operations
            if operation == "move":
                ebook.cloud_file_path = target
                ebook.cloud_file_id = target

            result.path_mappings[old_path] = target
            result.succeeded += 1
            result.total_processed += 1

        except Exception as e:
            result.failed += 1
            result.total_processed += 1
            result.errors.append(f"{ebook.title}: {str(e)}")

    if result.succeeded > 0:
        db.commit()

    return result
