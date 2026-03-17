from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class TreatmentPlanVersion(TimestampMixin, Base):
    __tablename__ = "treatment_plan_versions"

    id: Mapped[int] = mapped_column(primary_key=True)
    treatment_plan_id: Mapped[int] = mapped_column(
        ForeignKey("treatment_plans.id"), nullable=False
    )
    version_number: Mapped[int] = mapped_column(Integer, nullable=False)
    session_id: Mapped[int | None] = mapped_column(ForeignKey("sessions.id"), nullable=True)
    therapist_content: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    client_content: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    change_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    source: Mapped[str] = mapped_column(String(50), default="ai_generated")
    ai_metadata: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    # Relationships
    treatment_plan: Mapped["TreatmentPlan"] = relationship(  # noqa: F821
        back_populates="versions",
        foreign_keys=[treatment_plan_id],
        lazy="selectin",
    )
    session: Mapped["Session | None"] = relationship(lazy="selectin")  # noqa: F821
    safety_flags: Mapped[list["SafetyFlag"]] = relationship(  # noqa: F821
        back_populates="treatment_plan_version", lazy="selectin"
    )
    homework_items: Mapped[list["HomeworkItem"]] = relationship(  # noqa: F821
        back_populates="treatment_plan_version", lazy="selectin"
    )
