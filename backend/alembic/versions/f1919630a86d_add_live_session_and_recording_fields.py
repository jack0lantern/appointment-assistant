"""add_live_session_and_recording_fields

Revision ID: f1919630a86d
Revises: b7e2c9a1d4f3
Create Date: 2026-03-19 17:56:01.561274

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'f1919630a86d'
down_revision: Union[str, Sequence[str], None] = 'b7e2c9a1d4f3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add live session, recording, and diarization fields."""
    # Recording consents table
    op.create_table('recording_consents',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('session_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('consented', sa.Boolean(), nullable=False),
        sa.Column('consented_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('ip_address', sa.String(length=45), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['session_id'], ['sessions.id']),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id')
    )

    # Sessions: live session + recording fields
    op.add_column('sessions', sa.Column('session_type', sa.String(length=20), server_default='uploaded', nullable=False))
    op.add_column('sessions', sa.Column('livekit_room_name', sa.String(length=255), nullable=True))
    op.add_column('sessions', sa.Column('live_session_data', postgresql.JSONB(astext_type=sa.Text()), nullable=True))
    op.add_column('sessions', sa.Column('recording_status', sa.String(length=20), nullable=True))
    op.add_column('sessions', sa.Column('recording_storage_path', sa.Text(), nullable=True))
    op.add_column('sessions', sa.Column('recording_egress_id', sa.String(length=255), nullable=True))

    # Transcripts: diarization fields
    op.add_column('transcripts', sa.Column('utterances', postgresql.JSONB(astext_type=sa.Text()), nullable=True))
    op.add_column('transcripts', sa.Column('speaker_map', postgresql.JSONB(astext_type=sa.Text()), nullable=True))


def downgrade() -> None:
    """Remove live session, recording, and diarization fields."""
    op.drop_column('transcripts', 'speaker_map')
    op.drop_column('transcripts', 'utterances')
    op.drop_column('sessions', 'recording_egress_id')
    op.drop_column('sessions', 'recording_storage_path')
    op.drop_column('sessions', 'recording_status')
    op.drop_column('sessions', 'live_session_data')
    op.drop_column('sessions', 'livekit_room_name')
    op.drop_column('sessions', 'session_type')
    op.drop_table('recording_consents')
