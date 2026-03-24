# Stage 1: Build frontend
FROM node:20-alpine AS frontend
WORKDIR /app
COPY frontend/package*.json ./
RUN npm ci --legacy-peer-deps
COPY frontend/ ./
RUN npm run build

# Stage 2: Rails backend + serve frontend
FROM ruby:3.3-alpine AS backend

# Build dependencies for native gems and Rails (psych needs yaml-dev for libyaml)
RUN apk add --no-cache \
    build-base \
    libxml2-dev \
    libxslt-dev \
    postgresql-dev \
    tzdata \
    yaml-dev

WORKDIR /app

# Install gems
COPY backend_rails/Gemfile backend_rails/Gemfile.lock ./
RUN bundle config set --local deployment 'true' \
    && bundle config set --local without 'development test' \
    && bundle install -j4

# Copy Rails app
COPY backend_rails/ ./

# Copy built frontend into public/
COPY --from=frontend /app/dist ./public

ENV PORT=8000
ENV RAILS_ENV=production
EXPOSE 8000

CMD ["sh", "-c", "bundle exec rails db:migrate && exec bundle exec puma -C config/puma.rb -p ${PORT:-8000}"]
