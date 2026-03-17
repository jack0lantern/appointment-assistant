from contextlib import asynccontextmanager

from pathlib import Path

from dotenv import load_dotenv

# Load .env from backend/ exclusively
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


app = FastAPI(title="Tava Health", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "Accept",
        "Origin",
        "X-Requested-With",
    ],
)


# ── Register routers ────────────────────────────────────────────────────────
from app.routes.auth import router as auth_router
from app.routes.clients import router as clients_router
from app.routes.sessions import router as sessions_router
from app.routes.treatment_plans import router as treatment_plans_router
from app.routes.safety import router as safety_router
from app.routes.homework import router as homework_router
from app.routes.client_routes import router as client_routes_router
from app.routes.generate import router as generate_router
from app.routes.test_analyze import router as test_analyze_router

app.include_router(auth_router)
app.include_router(clients_router)
app.include_router(sessions_router)
app.include_router(treatment_plans_router)
app.include_router(safety_router)
app.include_router(homework_router)
app.include_router(client_routes_router)
app.include_router(generate_router)
app.include_router(test_analyze_router)


@app.get("/health")
async def health():
    return {"status": "ok"}
