# syntax=docker/dockerfile:1
# Production Dockerfile for the Golverse (FAFI) Django API.
#
# Code AND dependencies both come from the same clone of the FAFI-api repo
# (GIT_REPO_URL/GIT_BRANCH), so requirements.txt never has to be copied into this
# repo by hand. Build with the project env file so those values reach the build:
#   docker compose --env-file .env.prod -f docker-compose.prod.yml build

# Builder stage: clones the FAFI-api repo (requires Git)
FROM python:3.12-alpine AS builder-repo
ARG GIT_REPO_URL
ARG GIT_BRANCH=main
RUN apk add --no-cache git
WORKDIR /src
# GITHUB_TOKEN is passed as a BuildKit secret (not an ARG) so it never persists
# in the image's layer history or build cache.
RUN --mount=type=secret,id=github_token \
    if [ -z "$GIT_REPO_URL" ]; then \
    echo "ERROR: GIT_REPO_URL is empty. Run compose with --env-file .env.prod." >&2; \
    exit 1; \
    fi; \
    TOKEN=$(cat /run/secrets/github_token 2>/dev/null || true); \
    if [ -n "$TOKEN" ]; then \
    REPO_URL=$(echo $GIT_REPO_URL | sed "s#https://#https://${TOKEN}:x-oauth-basic@#"); \
    else \
    REPO_URL=$GIT_REPO_URL; \
    fi; \
    GIT_TERMINAL_PROMPT=0 git clone -b $GIT_BRANCH $REPO_URL fafi_project; \
    test -f fafi_project/manage.py && test -f fafi_project/requirements.txt

# ------------- PROD ENVIRONMENT -------------
FROM python:3.12-alpine AS prod
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

RUN apk add --no-cache \
    postgresql-libs \
    pango \
    cairo \
    gdk-pixbuf \
    fontconfig \
    ttf-freefont

WORKDIR /app
# Dependencies first (cached while the cloned requirements.txt is unchanged)...
COPY --from=builder-repo /src/fafi_project/requirements.txt /app/requirements.txt
RUN apk add --no-cache --virtual .build-deps \
    gcc \
    musl-dev \
    postgresql-dev \
    linux-headers \
    && pip install --no-cache-dir -r requirements.txt \
    && apk del .build-deps

# ...then the application code from the same clone.
COPY --from=builder-repo /src/fafi_project /app
COPY scripts/entrypoint.prod.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
