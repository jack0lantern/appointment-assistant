"""add safety_flags.category

Revision ID: b7e2c9a1d4f3
Revises: f4f59f159c41
Create Date: 2026-03-19

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "b7e2c9a1d4f3"
down_revision: Union[str, Sequence[str], None] = "f4f59f159c41"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "safety_flags",
        sa.Column(
            "category",
            sa.String(length=50),
            nullable=False,
            server_default="safety_risk",
        ),
    )
    op.alter_column("safety_flags", "category", server_default=None)


def downgrade() -> None:
    op.drop_column("safety_flags", "category")
