from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class Client(TimestampMixin, Base):
    __tablename__ = "clients"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), unique=True, nullable=True)
    therapist_id: Mapped[int] = mapped_column(ForeignKey("therapists.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)

    # Relationships
    user: Mapped["User | None"] = relationship(back_populates="client_profile", lazy="selectin")  # noqa: F821
    therapist: Mapped["Therapist"] = relationship(back_populates="clients", lazy="selectin")  # noqa: F821
    sessions: Mapped[list["Session"]] = relationship(back_populates="client", lazy="selectin")  # noqa: F821
    treatment_plan: Mapped["TreatmentPlan | None"] = relationship(  # noqa: F821
        back_populates="client", uselist=False, lazy="selectin"
    )
