from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class HomeworkItem(TimestampMixin, Base):
    __tablename__ = "homework_items"

    id: Mapped[int] = mapped_column(primary_key=True)
    treatment_plan_version_id: Mapped[int] = mapped_column(
        ForeignKey("treatment_plan_versions.id"), nullable=False
    )
    client_id: Mapped[int] = mapped_column(ForeignKey("clients.id"), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    # Relationships
    treatment_plan_version: Mapped["TreatmentPlanVersion"] = relationship(  # noqa: F821
        back_populates="homework_items", lazy="selectin"
    )
    client: Mapped["Client"] = relationship(lazy="selectin")  # noqa: F821
