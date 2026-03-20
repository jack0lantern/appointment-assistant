from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class Transcript(TimestampMixin, Base):
    __tablename__ = "transcripts"

    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(ForeignKey("sessions.id"), unique=True, nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    source_type: Mapped[str] = mapped_column(String(50), default="uploaded")
    # 'uploaded' | 'recording'
    word_count: Mapped[int] = mapped_column(Integer, default=0)

    # Diarized transcript data (from recording transcription)
    utterances: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    # [{speaker, speaker_raw, text, start_time, end_time, confidence}]
    speaker_map: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    # {"speaker_0": "therapist", "speaker_1": "client"}

    # Relationships
    session: Mapped["Session"] = relationship(back_populates="transcript", lazy="selectin")  # noqa: F821
