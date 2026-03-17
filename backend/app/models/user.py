from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(String(50), nullable=False)  # "therapist" | "client"
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    # Relationships
    therapist_profile: Mapped["Therapist"] = relationship(  # noqa: F821
        back_populates="user", uselist=False, lazy="selectin"
    )
    client_profile: Mapped["Client"] = relationship(  # noqa: F821
        back_populates="user", uselist=False, lazy="selectin"
    )
