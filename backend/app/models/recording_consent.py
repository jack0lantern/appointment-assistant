from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class RecordingConsent(TimestampMixin, Base):
    __tablename__ = "recording_consents"

    id: Mapped[int] = mapped_column(primary_key=True)
    session_id: Mapped[int] = mapped_column(ForeignKey("sessions.id"), nullable=False)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    consented: Mapped[bool] = mapped_column(Boolean, nullable=False)
    consented_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ip_address: Mapped[str | None] = mapped_column(String(45), nullable=True)

    # Relationships
    session: Mapped["Session"] = relationship(back_populates="recording_consents", lazy="selectin")  # noqa: F821
    user: Mapped["User"] = relationship(lazy="selectin")  # noqa: F821
