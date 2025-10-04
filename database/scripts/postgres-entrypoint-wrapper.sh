#!/bin/bash
# Custom PostgreSQL entrypoint wrapper
# Fixes SSL permissions before starting PostgreSQL

set -e

# Fix SSL certificate permissions (must run as root)
if [ -f "/etc/ssl/private/server.key" ] || [ -f "/etc/ssl/certs/server.crt" ]; then
    echo "Fixing SSL certificate permissions..."

    if [ -f "/etc/ssl/private/server.key" ]; then
        chown postgres:postgres /etc/ssl/private/server.key
        chmod 600 /etc/ssl/private/server.key
        echo "✓ Fixed permissions for server.key"
    fi

    if [ -f "/etc/ssl/certs/server.crt" ]; then
        chown postgres:postgres /etc/ssl/certs/server.crt
        chmod 644 /etc/ssl/certs/server.crt
        echo "✓ Fixed permissions for server.crt"
    fi

    echo "SSL certificate permissions fixed successfully"
fi

# Execute the original PostgreSQL entrypoint
exec docker-entrypoint.sh "$@"
