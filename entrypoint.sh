#!/bin/sh
set -e

# Substitute environment variables in the Nginx template
envsubst '$PORT' < /etc/nginx/templates/nginx.conf.template > /etc/nginx/conf.d/default.conf

# Execute the original Nginx command
exec "$@"