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
    DATABASE_PUBLIC_URL: str | None = None
    """Public URL for external connections (e.g. Railway TCP proxy). Use with USE_PUBLIC_DATABASE=1 to seed prod from local."""
    USE_PUBLIC_DATABASE: bool = False
    """When True, use DATABASE_PUBLIC_URL instead of DATABASE_URL. Required for `railway run` from local (private URL doesn't resolve)."""
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
        url = (
            self.DATABASE_PUBLIC_URL
            if self.USE_PUBLIC_DATABASE and self.DATABASE_PUBLIC_URL
            else self.DATABASE_URL
        )
        url = _ensure_asyncpg_url(url)
        # Railway public URL requires SSL; asyncpg uses ssl param
        if self.USE_PUBLIC_DATABASE and "ssl=" not in url and "sslmode=" not in url:
            sep = "&" if "?" in url else "?"
            url = f"{url}{sep}ssl=require"
        return url

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]


settings = Settings()
