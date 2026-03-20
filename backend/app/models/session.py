from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class Session(TimestampMixin, Base):
    __tablename__ = "sessions"

    id: Mapped[int] = mapped_column(primary_key=True)
    therapist_id: Mapped[int] = mapped_column(ForeignKey("therapists.id"), nullable=False)
    client_id: Mapped[int] = mapped_column(ForeignKey("clients.id"), nullable=False)
    session_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    session_number: Mapped[int] = mapped_column(Integer, default=1)
    duration_minutes: Mapped[int] = mapped_column(Integer, default=50)
    status: Mapped[str] = mapped_column(String(50), default="completed")

    # Live session fields
    session_type: Mapped[str] = mapped_column(String(20), default="uploaded")  # 'uploaded' | 'live'
    livekit_room_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    live_session_data: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    # {started_at, ended_at, participants: [{user_id, role, joined_at, left_at}]}

    # Recording fields
    recording_status: Mapped[str | None] = mapped_column(String(20), nullable=True)
    # null | 'pending_consent' | 'recording' | 'stopped' | 'processing' | 'complete' | 'failed'
    recording_storage_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    recording_egress_id: Mapped[str | None] = mapped_column(String(255), nullable=True)

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
    recording_consents: Mapped[list["RecordingConsent"]] = relationship(  # noqa: F821
        back_populates="session", lazy="selectin"
    )
