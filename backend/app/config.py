from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5433/tava"
    ANTHROPIC_API_KEY: str = ""
    JWT_SECRET: str = "dev-secret-key"

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
