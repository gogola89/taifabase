#!/bin/bash
# Fix SSL certificate permissions for PostgreSQL
# This script runs as root before PostgreSQL starts

set -e

echo "Fixing SSL certificate permissions..."

# Create the SSL directories if they don't exist
mkdir -p /etc/ssl/private /etc/ssl/certs

# Copy SSL files to container-managed locations if they exist
if [ -f "/etc/ssl/private/server.key" ]; then
    # Fix ownership and permissions for the private key
    chown postgres:postgres /etc/ssl/private/server.key
    chmod 600 /etc/ssl/private/server.key
    echo "✓ Fixed permissions for server.key"
fi

if [ -f "/etc/ssl/certs/server.crt" ]; then
    # Fix ownership for the certificate
    chown postgres:postgres /etc/ssl/certs/server.crt
    chmod 644 /etc/ssl/certs/server.crt
    echo "✓ Fixed permissions for server.crt"
fi

echo "SSL certificate permissions fixed successfully"
