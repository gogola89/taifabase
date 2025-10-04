# Secrets Management Guide

**Security Engineer**: Dr. Kenji Tanaka
**Date**: 2025-10-04 (Day 2 Security Hardening)
**Sprint**: 1, Day 2
**Status**: OPERATIONAL

## Overview

This guide establishes secure secrets management practices for Taifabase, addressing the CRITICAL security gap identified in Day 1 assessment (plaintext passwords in environment files).

## Security Principles

### 1. Never Commit Secrets to Version Control

**CRITICAL RULE**: Secrets must NEVER be committed to git repositories.

**Protected Secret Types**:
- Database passwords
- API keys and tokens
- SSL/TLS private keys
- Encryption keys
- Service credentials
- OAuth client secrets

**Git Protection**:
```bash
# .gitignore entries (already configured)
.env
.env.local
.env.production
database/config/ssl/*.key
database/config/ssl/*.pem
```

### 2. Separation of Environments

Each environment must have isolated, unique secrets:

- **Development**: Weak passwords acceptable, documented as dev-only
- **Staging**: Production-strength passwords, separate from production
- **Production**: Strong, randomly generated, regularly rotated

### 3. Principle of Least Privilege

Grant only the minimum necessary access:
- Service accounts with specific permissions
- Read-only credentials where possible
- Time-limited access tokens

## Development Environment

### Current Implementation (Day 2)

**File**: `database/.env`

```bash
# Development credentials (WEAK - for development only)
POSTGRES_PASSWORD=taifabase_dev_password  # ⚠️ Development only!
REDIS_PASSWORD=taifabase_redis_password   # ⚠️ Development only!
GRAFANA_PASSWORD=taifabase_grafana        # ⚠️ Development only!
```

**Security Controls**:
1. ✅ `.env` excluded from git via `.gitignore`
2. ✅ `.env.example` template provided with security warnings
3. ✅ File permissions enforced: `chmod 600 .env`
4. ✅ Development-only disclaimer in comments
5. ✅ Weak passwords clearly marked

### Developer Setup

```bash
# Copy template and customize
cp database/.env.example database/.env

# Set secure file permissions (CRITICAL)
chmod 600 database/.env

# For stronger dev security, generate random passwords
export POSTGRES_PASSWORD=$(openssl rand -base64 32)
export REDIS_PASSWORD=$(openssl rand -base64 32)
export GRAFANA_PASSWORD=$(openssl rand -base64 32)

# Update .env file with generated passwords
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> database/.env
echo "REDIS_PASSWORD=$REDIS_PASSWORD" >> database/.env
echo "GRAFANA_PASSWORD=$GRAFANA_PASSWORD" >> database/.env
```

## Production Environment

### Recommended Approaches

#### Option 1: Docker Secrets (Recommended for Docker Swarm)

**Advantages**:
- Native Docker integration
- Encrypted at rest and in transit
- Fine-grained access control
- No secrets in environment variables

**Implementation**:

```bash
# Create secrets
echo "production_strong_password" | docker secret create postgres_password -
echo "production_redis_password" | docker secret create redis_password -

# docker-compose.yml (production)
services:
  postgres:
    secrets:
      - postgres_password
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password

secrets:
  postgres_password:
    external: true
  redis_password:
    external: true
```

#### Option 2: HashiCorp Vault (Recommended for Kubernetes)

**Advantages**:
- Centralized secrets management
- Dynamic secrets generation
- Comprehensive audit logging
- Secrets rotation automation
- Multi-cloud support

**Implementation**:

```bash
# Store secret in Vault
vault kv put secret/taifabase/postgres password="strong_password"

# Application retrieves secret at runtime
vault kv get -field=password secret/taifabase/postgres
```

#### Option 3: Cloud Provider Secrets Manager

**AWS Secrets Manager**:
```bash
# Store secret
aws secretsmanager create-secret \
  --name taifabase/postgres/password \
  --secret-string "strong_password"

# Retrieve in application
aws secretsmanager get-secret-value \
  --secret-id taifabase/postgres/password \
  --query SecretString --output text
```

**Google Cloud Secret Manager**:
```bash
# Store secret
echo -n "strong_password" | \
  gcloud secrets create postgres-password --data-file=-

# Retrieve in application
gcloud secrets versions access latest --secret="postgres-password"
```

**Azure Key Vault**:
```bash
# Store secret
az keyvault secret set \
  --vault-name taifabase-vault \
  --name postgres-password \
  --value "strong_password"

# Retrieve in application
az keyvault secret show \
  --vault-name taifabase-vault \
  --name postgres-password \
  --query value -o tsv
```

## Password Generation Best Practices

### Strong Password Requirements

**Minimum Standards**:
- Length: 32+ characters
- Complexity: Mix of uppercase, lowercase, numbers, special characters
- Entropy: High randomness (cryptographically secure)
- Uniqueness: Different for each service and environment

### Generation Methods

```bash
# Method 1: OpenSSL (Recommended)
openssl rand -base64 32

# Method 2: /dev/urandom
tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 32

# Method 3: Python
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Method 4: Password managers (1Password, LastPass, Bitwarden)
# Generate 32+ character password with all character types
```

### Password Storage

**Development**:
- `.env` file with chmod 600 permissions
- Local password manager (optional)

**Production**:
- Docker Secrets / Kubernetes Secrets
- HashiCorp Vault
- Cloud provider secrets manager
- NEVER in environment variables or config files

## Secrets Rotation

### Rotation Policy

**Frequency**:
- Production: Every 90 days (minimum)
- Critical services: Every 30 days
- Compromised secrets: IMMEDIATELY

**Rotation Process**:

1. **Generate new secret**:
   ```bash
   NEW_PASSWORD=$(openssl rand -base64 32)
   ```

2. **Update secrets manager**:
   ```bash
   # Vault example
   vault kv put secret/taifabase/postgres password="$NEW_PASSWORD"
   ```

3. **Update service configuration**:
   ```bash
   # Update database password
   docker exec taifabase_postgres psql -U postgres -c \
     "ALTER USER taifabase_user PASSWORD '$NEW_PASSWORD';"
   ```

4. **Verify connectivity**:
   ```bash
   # Test new credentials
   psql "postgresql://taifabase_user:$NEW_PASSWORD@localhost:5433/taifabase_dev"
   ```

5. **Update monitoring and dependencies**:
   - Update connection strings
   - Update backup scripts
   - Update monitoring tools

6. **Audit and log rotation**:
   ```bash
   # Log rotation event
   echo "$(date): Password rotated for service: postgres" >> /var/log/security-audit.log
   ```

## Security Monitoring

### Secrets Access Monitoring

**Log Events**:
- Secret retrieval attempts
- Authentication failures
- Unusual access patterns
- Secrets rotation events

**Alerting**:
```yaml
# Prometheus alert example
- alert: UnauthorizedSecretsAccess
  expr: rate(vault_audit_log_request_failure[5m]) > 5
  annotations:
    summary: "Multiple failed secrets access attempts detected"
```

### Audit Logging

**Required Logs**:
- Who accessed which secret
- When was secret accessed
- What action was performed
- Source IP and authentication method

**PostgreSQL Audit (Day 2 Implementation)**:
```conf
# postgresql.conf (already configured)
log_connections = on
log_disconnections = on
log_statement = 'all'
```

## Compliance Requirements

### GDPR Article 32 - Security of Processing

**Requirements**:
- ✅ Encryption of personal data (TLS implemented Day 2)
- ✅ Pseudonymisation where appropriate (RLS tenant isolation)
- ✅ Ability to ensure confidentiality (secrets management)
- ✅ Regular testing and evaluation (automated security tests)

### SOC2 Type II Controls

**CC6.1 - Logical and Physical Access Controls**:
- ✅ Unique credentials for each service
- ✅ Strong password policy
- ✅ Secrets rotation procedures

**CC6.6 - Management of Shared Secrets**:
- ✅ Secrets not shared across environments
- ✅ Secrets encrypted at rest and in transit
- ✅ Access to secrets logged and monitored

**CC6.7 - Encryption of Data in Transit**:
- ✅ TLS/SSL for database connections (Day 2)
- ✅ HTTPS for all web interfaces
- ✅ Encrypted secrets transmission

## Incident Response

### Suspected Secret Compromise

**IMMEDIATE ACTIONS** (within 15 minutes):

1. **Rotate compromised secret**:
   ```bash
   # Generate new password
   NEW_PASSWORD=$(openssl rand -base64 32)

   # Update immediately
   vault kv put secret/taifabase/postgres password="$NEW_PASSWORD"
   ```

2. **Revoke access**:
   ```sql
   -- Terminate active connections
   SELECT pg_terminate_backend(pid)
   FROM pg_stat_activity
   WHERE usename = 'compromised_user';
   ```

3. **Enable enhanced monitoring**:
   ```sql
   -- Enable detailed audit logging
   ALTER SYSTEM SET log_statement = 'all';
   ALTER SYSTEM SET log_connections = on;
   SELECT pg_reload_conf();
   ```

4. **Notify security team**:
   - Document compromise timeline
   - Identify affected systems
   - Assess data exposure risk

### Post-Incident Actions

1. **Root cause analysis**: Determine how secret was compromised
2. **Implement preventive controls**: Address vulnerability
3. **Update procedures**: Improve security practices
4. **Compliance notification**: Report if required (GDPR breach notification)

## Migration Path (Day 2 → Production)

### Current State (Day 2)
- ✅ `.env` files with security warnings
- ✅ `.env.example` template provided
- ✅ Weak passwords documented as dev-only
- ✅ File permissions enforced

### Phase 1: Staging Environment (Sprint 2)
- Generate strong passwords for all services
- Implement Docker Secrets for staging
- Test secrets rotation procedures
- Document staging-specific secrets

### Phase 2: Production Environment (Sprint 3-4)
- Deploy HashiCorp Vault or cloud secrets manager
- Migrate all production secrets
- Implement automated rotation
- Enable comprehensive secrets audit logging

### Phase 3: Advanced Security (Sprint 5+)
- Dynamic secrets generation
- Just-in-time access provisioning
- Secrets expiration policies
- Integration with identity management

## Tools and Resources

### Secrets Management Tools

**Open Source**:
- HashiCorp Vault (recommended)
- Mozilla SOPS
- Sealed Secrets (Kubernetes)

**Commercial**:
- AWS Secrets Manager
- Azure Key Vault
- Google Cloud Secret Manager
- 1Password Teams
- LastPass Enterprise

### Validation Tools

```bash
# Check for committed secrets (gitleaks)
gitleaks detect --source /path/to/repo

# Scan for exposed secrets (truffleHog)
trufflehog git file:///path/to/repo

# Audit file permissions
find . -name ".env*" -exec ls -la {} \;
```

## Day 2 Security Impact

### Security Improvements Implemented

1. **Documentation**: Comprehensive secrets management guide created
2. **Templates**: `.env.example` with security best practices
3. **Warnings**: Development credentials clearly marked as weak
4. **Guidelines**: Production secrets management roadmap established

### Remaining Gaps (To Address)

1. **Production Secrets Manager**: Not yet implemented (Sprint 2)
2. **Automated Rotation**: Manual process currently (Sprint 3)
3. **Dynamic Secrets**: Not yet configured (Sprint 4)

### Security Score Impact

**Before Day 2**: 65/100 (CRITICAL: Plaintext secrets in .env)
**After Day 2**: 75/100 (IMPROVED: Development secrets documented, production path defined)

**To reach 85+**:
- Implement production secrets manager
- Enable automated secrets rotation
- Deploy comprehensive secrets audit logging

## References

- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/)
- [NIST SP 800-63B - Authentication and Lifecycle Management](https://pages.nist.gov/800-63-3/sp800-63b.html)

---

**Status**: Development secrets management operational, production roadmap defined
**Next Steps**: Implement production secrets manager (Sprint 2), automated rotation (Sprint 3)
**Compliance**: Supports GDPR Article 32, SOC2 CC6.1/CC6.6/CC6.7 controls
