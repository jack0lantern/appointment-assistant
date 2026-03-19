from pydantic_settings import BaseSettings


def _ensure_asyncpg_url(url: str) -> str:
    """Convert postgresql:// to postgresql+asyncpg:// for SQLAlchemy async (Railway, etc.)."""
    if url.startswith("postgresql://") and "+asyncpg" not in url:
        return url.replace("postgresql://", "postgresql+asyncpg://", 1)
    if url.startswith("postgres://") and "+asyncpg" not in url:
        return url.replace("postgres://", "postgresql+asyncpg://", 1)
    return url


class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5433/tava"
    ANTHROPIC_API_KEY: str = ""
    JWT_SECRET: str = "dev-secret-key"
    CORS_ORIGINS: str = (
        "http://localhost:5173,http://127.0.0.1:5173,"
        "http://localhost:5174,http://127.0.0.1:5174"
    )

    model_config = {"env_file": ".env", "extra": "ignore"}

    @property
    def database_url(self) -> str:
        """DATABASE_URL with postgresql:// converted to postgresql+asyncpg:// for async SQLAlchemy."""
        return _ensure_asyncpg_url(self.DATABASE_URL)

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]


settings = Settings()
