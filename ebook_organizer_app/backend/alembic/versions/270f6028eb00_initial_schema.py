"""initial_schema

Revision ID: 270f6028eb00
Revises: 
Create Date: 2026-02-28 13:53:52.180422

Baseline migration — the schema already exists via Base.metadata.create_all().
Future migrations will capture incremental changes.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '270f6028eb00'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Baseline – tables already exist.
    pass


def downgrade() -> None:
    # Dropping everything would be destructive — intentionally left empty.
    pass
