# SSL/TLS Certificates for PostgreSQL

**Security Engineer**: Dr. Kenji Tanaka
**Date**: 2025-10-04
**Purpose**: TLS encryption for PostgreSQL connections (Day 2 Security Hardening)

## Overview

This directory contains SSL/TLS certificates for encrypting PostgreSQL database connections. These certificates prevent credential theft and data exposure in transit.

## Certificate Files

- `server.crt` - PostgreSQL server certificate (public)
- `server.key` - PostgreSQL server private key (NEVER commit to git)

**IMPORTANT**: These files are excluded from version control via `.gitignore` for security reasons.

## Generating Certificates

### Development Environment (Self-Signed)

For development and testing, use self-signed certificates:

```bash
# Navigate to SSL directory
cd /path/to/taifabase/database/config/ssl

# Generate self-signed certificate (valid for 365 days)
openssl req -new -x509 -days 365 -nodes -text \
  -out server.crt \
  -keyout server.key \
  -subj "/CN=taifabase-postgres.local/O=Taifabase/C=US"

# Set proper permissions (CRITICAL)
chmod 600 server.key  # Private key - readable only by owner
chmod 644 server.crt  # Public certificate - readable by all
```

### Production Environment (CA-Signed)

For production deployments, use certificates signed by a trusted Certificate Authority:

```bash
# Generate Certificate Signing Request (CSR)
openssl req -new -nodes -text \
  -out server.csr \
  -keyout server.key \
  -subj "/CN=postgres.yourdomain.com/O=Your Organization/C=US"

# Submit server.csr to your Certificate Authority
# Place the signed certificate as server.crt

# Set proper permissions
chmod 600 server.key
chmod 644 server.crt
```

## Docker Volume Mounting

The certificates are mounted as read-only volumes in `docker-compose.yml`:

```yaml
volumes:
  - ./config/ssl/server.crt:/etc/ssl/certs/server.crt:ro
  - ./config/ssl/server.key:/etc/ssl/private/server.key:ro
```

## PostgreSQL Configuration

TLS is enabled in `postgresql.conf`:

```conf
ssl = on
ssl_cert_file = '/etc/ssl/certs/server.crt'
ssl_key_file = '/etc/ssl/private/server.key'
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'
ssl_prefer_server_ciphers = on
ssl_min_protocol_version = 'TLSv1.2'
```

## Client Connections

### Require SSL for all connections

```bash
# Using psql
psql "postgresql://user:password@host:5433/database?sslmode=require"

# Connection string format
postgresql://user:password@host:5433/database?sslmode=require
```

### SSL Modes

- `disable` - No SSL (NOT RECOMMENDED)
- `allow` - Try SSL, fallback to non-SSL
- `prefer` - Try SSL first, then non-SSL
- `require` - Require SSL (RECOMMENDED for production)
- `verify-ca` - Require SSL and verify CA
- `verify-full` - Require SSL and verify hostname

## Security Considerations

1. **Never commit private keys**: `server.key` must NEVER be committed to version control
2. **Proper permissions**: Private key must have 600 permissions (readable only by owner)
3. **Regular rotation**: Replace certificates before expiration
4. **Production certificates**: Use CA-signed certificates in production environments
5. **Strong ciphers**: Configure only strong cipher suites (TLS 1.2+)

## Troubleshooting

### Certificate permission errors

```bash
# Fix permissions
chmod 600 server.key
chmod 644 server.crt

# Verify ownership (Docker containers may need specific ownership)
ls -la server.*
```

### Connection fails with SSL errors

```bash
# Test SSL connection
openssl s_client -connect localhost:5433 -starttls postgres

# Check PostgreSQL logs
docker logs taifabase_postgres 2>&1 | grep -i ssl
```

### Certificate expiration

```bash
# Check certificate expiration date
openssl x509 -in server.crt -noout -dates
```

## Compliance

TLS encryption is REQUIRED for:
- **GDPR**: Article 32 - Security of Processing
- **SOC2**: CC6.7 - Encryption of Data in Transit
- **PCI DSS**: Requirement 4 - Encrypt transmission of cardholder data

## References

- [PostgreSQL SSL Support Documentation](https://www.postgresql.org/docs/15/ssl-tcp.html)
- [OpenSSL Certificate Generation](https://www.openssl.org/docs/)
- [Docker Secrets Management](https://docs.docker.com/engine/swarm/secrets/)
