from sqlalchemy import ForeignKey, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class SessionSummary(TimestampMixin, Base):
    __tablename__ = "session_summaries"

    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(ForeignKey("sessions.id"), unique=True, nullable=False)
    therapist_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    client_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    key_themes: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    # Relationships
    session: Mapped["Session"] = relationship(back_populates="summary", lazy="selectin")  # noqa: F821
