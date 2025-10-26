#!/bin/sh
set -e

echo "=== NGINX Configuration Generation ==="

# Set defaults
export ACTIVE_POOL=${ACTIVE_POOL:-blue}
export PORT=${PORT:-3000}

echo "ACTIVE_POOL: $ACTIVE_POOL"
echo "PORT: $PORT"

# Generate nginx.conf from template
envsubst '${ACTIVE_POOL},${PORT}' < /etc/nginx/templates/nginx.conf.template > /etc/nginx/nginx.conf

echo "=== Generated nginx.conf ==="
cat /etc/nginx/nginx.conf

# Validate configuration
echo "=== Testing NGINX configuration ==="
nginx -t

echo "=== Starting NGINX ==="
exec "$@"
