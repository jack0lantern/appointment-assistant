from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class Session(TimestampMixin, Base):
    __tablename__ = "sessions"

    id: Mapped[int] = mapped_column(primary_key=True)
    therapist_id: Mapped[int] = mapped_column(ForeignKey("therapists.id"), nullable=False)
    client_id: Mapped[int] = mapped_column(ForeignKey("clients.id"), nullable=False)
    session_date: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    session_number: Mapped[int] = mapped_column(Integer, default=1)
    duration_minutes: Mapped[int] = mapped_column(Integer, default=50)
    status: Mapped[str] = mapped_column(String(50), default="completed")

    # Relationships
    therapist: Mapped["Therapist"] = relationship(back_populates="sessions", lazy="selectin")  # noqa: F821
    client: Mapped["Client"] = relationship(back_populates="sessions", lazy="selectin")  # noqa: F821
    transcript: Mapped["Transcript | None"] = relationship(  # noqa: F821
        back_populates="session", uselist=False, lazy="selectin"
    )
    summary: Mapped["SessionSummary | None"] = relationship(  # noqa: F821
        back_populates="session", uselist=False, lazy="selectin"
    )
    safety_flags: Mapped[list["SafetyFlag"]] = relationship(  # noqa: F821
        back_populates="session", lazy="selectin"
    )
