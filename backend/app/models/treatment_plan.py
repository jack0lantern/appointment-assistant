from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class TreatmentPlan(TimestampMixin, Base):
    __tablename__ = "treatment_plans"

    id: Mapped[int] = mapped_column(primary_key=True)
    client_id: Mapped[int] = mapped_column(ForeignKey("clients.id"), unique=True, nullable=False)
    therapist_id: Mapped[int] = mapped_column(ForeignKey("therapists.id"), nullable=False)
    current_version_id: Mapped[int | None] = mapped_column(
        ForeignKey("treatment_plan_versions.id", use_alter=True),
        nullable=True,
    )
    status: Mapped[str] = mapped_column(String(50), default="draft")

    # Relationships
    client: Mapped["Client"] = relationship(back_populates="treatment_plan", lazy="selectin")  # noqa: F821
    therapist: Mapped["Therapist"] = relationship(lazy="selectin")  # noqa: F821
    versions: Mapped[list["TreatmentPlanVersion"]] = relationship(  # noqa: F821
        back_populates="treatment_plan",
        foreign_keys="TreatmentPlanVersion.treatment_plan_id",
        lazy="selectin",
    )
    current_version: Mapped["TreatmentPlanVersion | None"] = relationship(  # noqa: F821
        foreign_keys=[current_version_id],
        lazy="selectin",
        post_update=True,
    )
