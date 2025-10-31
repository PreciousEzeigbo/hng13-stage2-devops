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

# Remove symlinks and create real log files
# This allows the log watcher to tail actual files instead of stdout/stderr
echo "=== Setting up log files ==="
rm -f /var/log/nginx/access.log /var/log/nginx/error.log
touch /var/log/nginx/access.log /var/log/nginx/error.log
chmod 666 /var/log/nginx/access.log /var/log/nginx/error.log
echo "Log files created successfully"

# Validate configuration
echo "=== Testing NGINX configuration ==="
nginx -t

echo "=== Starting NGINX ==="
exec "$@"
