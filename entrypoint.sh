#!/bin/sh
set -e

# Validate required environment variables
if [ -z "$ALLOWED_DOMAINS" ]; then
    echo "ERROR: ALLOWED_DOMAINS environment variable is required"
    exit 1
fi

if [ -z "$UPSTREAM_HOST" ]; then
    echo "ERROR: UPSTREAM_HOST environment variable is required"
    exit 1
fi

# Set defaults
export UPSTREAM_PORT="${UPSTREAM_PORT:-80}"
export ALLOWED_HEADERS="${ALLOWED_HEADERS:-}"
export ALLOWED_METHODS="${ALLOWED_METHODS:-}"

# Render nginx config from template
gomplate -f /etc/nginx/templates/default.conf.template -o /etc/nginx/conf.d/default.conf

echo "CORS proxy configured:"
echo "  Allowed domains: $ALLOWED_DOMAINS"
echo "  Upstream: $UPSTREAM_HOST:$UPSTREAM_PORT"

exec nginx -g 'daemon off;'
