from sqlalchemy import ForeignKey, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class Therapist(TimestampMixin, Base):
    __tablename__ = "therapists"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True, nullable=False)
    license_type: Mapped[str] = mapped_column(String(50), nullable=False)
    specialties: Mapped[dict] = mapped_column(JSONB, default=list)
    preferences: Mapped[dict] = mapped_column(JSONB, default=dict)

    # Relationships
    user: Mapped["User"] = relationship(back_populates="therapist_profile", lazy="selectin")  # noqa: F821
    clients: Mapped[list["Client"]] = relationship(back_populates="therapist", lazy="selectin")  # noqa: F821
    sessions: Mapped[list["Session"]] = relationship(back_populates="therapist", lazy="selectin")  # noqa: F821
