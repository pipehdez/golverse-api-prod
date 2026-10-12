#!/bin/sh

set -e

# Wait for database
echo "Waiting for PostgreSQL..."
while ! nc -z $POSTGRES_HOST $POSTGRES_PORT; do
  sleep 0.1
done
echo "PostgreSQL started"

# Run migrations and collect static if requested
if [ "$RUN_MIGRATIONS" = "true" ]; then
  echo "Apply database migrations"
  python manage.py migrate

  # Setup MinIO bucket and policy
  echo "Setting up MinIO..."
  python scripts/setup_minio.py

  # Collect static files
  echo "Collect static files"
  python manage.py collectstatic --noinput
fi

exec "$@"
