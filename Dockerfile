# Stage 1: Build frontend
FROM node:20-alpine AS frontend
WORKDIR /app
COPY frontend/package*.json ./
RUN npm ci --legacy-peer-deps
COPY frontend/ ./
RUN npm run build

# Stage 2: Backend + serve frontend
FROM python:3.11-slim
WORKDIR /app

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/ .
COPY --from=frontend /app/dist ./static

ENV PORT=8000
EXPOSE 8000

CMD ["sh", "-c", "timeout 30 alembic upgrade head 2>&1 || echo 'WARN: migration failed or timed out'; exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
