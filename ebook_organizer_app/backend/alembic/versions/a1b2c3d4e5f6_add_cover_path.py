"""add cover_path column to ebooks

Revision ID: a1b2c3d4e5f6
Revises: 270f6028eb00
Create Date: 2026-03-29

Adds cover_path column to store the path to the WebP cover thumbnail.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = '270f6028eb00'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('ebooks', sa.Column('cover_path', sa.String(500), nullable=True))


def downgrade() -> None:
    op.drop_column('ebooks', 'cover_path')
