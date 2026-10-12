# syntax=docker/dockerfile:1
# Dockerfile for FAFI Django Microservices

# Builder stage for QA and Prod (requires Git)
FROM python:3.12-alpine AS builder-repo
# Add build arguments for github repo cloning
ARG GIT_REPO_URL
ARG GIT_BRANCH=main
RUN apk add --no-cache git
WORKDIR /src
# GITHUB_TOKEN is passed as a BuildKit secret (not an ARG) so it never persists
# in the image's layer history or build cache.
RUN --mount=type=secret,id=github_token \
    if [ -n "$GIT_REPO_URL" ]; then \
    TOKEN=$(cat /run/secrets/github_token 2>/dev/null || true); \
    if [ -n "$TOKEN" ]; then \
    REPO_URL=$(echo $GIT_REPO_URL | sed "s#https://#https://${TOKEN}:x-oauth-basic@#"); \
    GIT_TERMINAL_PROMPT=0 git clone -b $GIT_BRANCH $REPO_URL fafi_project; \
    else \
    GIT_TERMINAL_PROMPT=0 git clone -b $GIT_BRANCH $GIT_REPO_URL fafi_project; \
    fi \
    else \
    mkdir fafi_project; \
    fi

# Base stage
FROM python:3.12-alpine AS base
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

RUN apk add --no-cache \
    postgresql-libs \
    pango \
    cairo \
    gdk-pixbuf \
    fontconfig \
    ttf-freefont \
    && apk add --no-cache --virtual .build-deps \
    gcc \
    musl-dev \
    postgresql-dev \
    linux-headers

WORKDIR /app
# We'll copy requirements directly as we use them in base
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt \
    && apk del .build-deps

# ------------- DEV ENVIRONMENT -------------
# Uses volume mounts, so we don't copy the code here.
FROM base AS dev
# Ensure script is executable
COPY scripts/entrypoint.dev.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# ------------- LOCAL ENVIRONMENT -------------
FROM base AS local
# Ensure script is executable
COPY scripts/entrypoint.local.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# ------------- QA ENVIRONMENT -------------
# Clones code from the builder-repo stage
FROM base AS qa
# The github repo (pipehdez/FAFI-api) is cloned into /src/fafi_project with manage.py at its root.
COPY --from=builder-repo /src/fafi_project /app
COPY scripts/entrypoint.qa.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# ------------- PROD ENVIRONMENT -------------
FROM base AS prod
COPY --from=builder-repo /src/fafi_project /app
COPY scripts/entrypoint.prod.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
