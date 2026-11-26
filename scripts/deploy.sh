#!/bin/sh
# Deploy the production API: build the exact current commit of GIT_BRANCH,
# restart api + celery, and fail loudly unless every container runs it.
#
#   cd /opt/golverse/api && sh scripts/deploy.sh
#
# Migrations run on api start (RUN_MIGRATIONS=true in the compose file).
set -eu

cd "$(dirname "$0")/.."
ENV_FILE=.env.prod
COMPOSE="docker compose --env-file $ENV_FILE -f docker-compose.prod.yml"
CONTAINERS="fafi_api_prod fafi_celery_worker_prod fafi_celery_beat_prod"

# Read one KEY=value from the env file (last wins, surrounding quotes dropped)
# without sourcing it, so nothing else in it is executed or exported.
env_value() {
    grep -E "^$1=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found in $(pwd)" >&2; exit 1; }
REPO_URL=$(env_value GIT_REPO_URL)
BRANCH=$(env_value GIT_BRANCH)
BRANCH=${BRANCH:-main}
TOKEN=$(env_value GITHUB_TOKEN)
[ -n "$REPO_URL" ] || { echo "ERROR: GIT_REPO_URL is not set in $ENV_FILE" >&2; exit 1; }

# Resolve the branch head. The token goes in an HTTP header through git's env
# config, never in the URL or the command line.
if [ -n "$TOKEN" ]; then
    AUTH=$(printf '%s:x-oauth-basic' "$TOKEN" | base64 | tr -d '\n')
    REVISION=$(GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 \
        GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0="Authorization: Basic $AUTH" \
        git ls-remote "$REPO_URL" "refs/heads/$BRANCH" | cut -f1)
else
    REVISION=$(GIT_TERMINAL_PROMPT=0 git ls-remote "$REPO_URL" "refs/heads/$BRANCH" | cut -f1)
fi
case "$REVISION" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;;
    *) echo "ERROR: could not resolve $BRANCH on $REPO_URL" >&2; exit 1 ;;
esac
echo "==> Deploying $BRANCH @ $REVISION"

export GIT_REVISION="$REVISION"
$COMPOSE build api
$COMPOSE up -d

echo "==> Waiting for containers"
sleep 15
FAILED=0
for c in $CONTAINERS; do
    running=$(docker exec "$c" cat /app/REVISION 2>/dev/null || echo "unavailable")
    if [ "$running" = "$REVISION" ]; then
        echo "  ok    $c  $running"
    else
        echo "  FAIL  $c  $running (expected $REVISION)" >&2
        FAILED=1
    fi
done
[ "$FAILED" -eq 0 ] || { echo "ERROR: some containers are not running $REVISION" >&2; exit 1; }
echo "==> Done: all containers run $REVISION"
