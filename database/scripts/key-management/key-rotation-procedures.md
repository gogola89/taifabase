# Encryption Key Rotation Procedures

**Document Metadata**
- **Created**: 2025-10-06 (Sprint 2, Day 1)
- **Version**: 1.0
- **Owner**: Raj Patel (DevOps Engineer)
- **Status**: Day 1 Manual Procedures → Day 6-8 Automation (US-901)

---

## Overview

Encryption keys MUST be rotated every 90 days to comply with SOC2 CC6.6 requirements. This document outlines both manual rotation procedures (Day 1-5) and automated rotation approach (US-901, Day 6-8).

**Compliance Requirements**:
- **SOC2 CC6.6**: Encryption keys rotated regularly (90-day maximum)
- **GDPR Article 32**: Appropriate security measures including key management
- **Industry Best Practice**: Key rotation prevents long-term key compromise

---

## Key Rotation Schedule

### Rotation Frequency

| Environment | Rotation Frequency | Automation Status |
|-------------|--------------------|--------------------|
| **Development** | 90 days | Manual (Day 1), Automated (US-901, Day 6-8) |
| **Staging** | 90 days | Automated (US-901, Day 6-8) |
| **Production** | 90 days | Automated (US-901, Day 6-8) + Monitoring |

### Rotation Timeline

```
Day 0 (New Key Generation):
├─ Generate new encryption key in key management system
├─ Store new key with rotation metadata (generation date, expiration)
└─ Old key remains active (grace period begins)

Day 0-1 (Grace Period - 24 hours):
├─ Both old and new keys valid
├─ New encrypted data uses new key
├─ Old encrypted data still decryptable with old key
└─ Re-encryption job starts (background)

Day 1 (Re-encryption):
├─ Background job re-encrypts all data with new key
├─ Validation: Verify all data re-encrypted successfully
├─ Progress monitoring: Track re-encryption status
└─ Rollback plan: Keep old key for emergency rollback

Day 2-30 (Validation Period):
├─ New key primary key for all operations
├─ Old key retained for rollback (30-day retention)
├─ Monitoring: Ensure no errors or data corruption
└─ Audit: Log all key access during transition

Day 30 (Old Key Revocation):
├─ Old key disabled (no longer valid for encryption/decryption)
├─ Old key archived for audit trail (7-year retention)
└─ Monitoring: Confirm no attempts to use old key

Day 90 (Next Rotation):
└─ Cycle repeats
```

### Alert Schedule

| Alert | Trigger | Recipient | Action |
|-------|---------|-----------|--------|
| **Rotation Due Soon** | 7 days before expiration | DevOps team | Plan rotation |
| **Rotation Overdue** | 1 day past expiration | DevOps + Security | Immediate rotation |
| **Rotation Critical** | 7 days past expiration | Executive + Compliance | Emergency rotation + incident report |
| **Re-encryption Failure** | Re-encryption job fails | DevOps + Backend | Investigate and retry |

---

## Manual Key Rotation (Development - Day 1-5)

### Prerequisites

- Access to key management configuration (`database/config/key-management-config.sh`)
- Database admin credentials
- Backup of current encrypted data (in case rollback needed)
- Downtime window (optional, recommended for manual rotation)

### Procedure

#### Step 1: Generate New Encryption Key

```bash
# Generate a new strong encryption key (256-bit)
new_key=$(openssl rand -base64 32)

# Store new key in environment variable
export TAIFABASE_ENCRYPTION_KEY_DEV="$new_key"

# Backup current key (for grace period)
export TAIFABASE_ENCRYPTION_KEY_DEV_PREVIOUS="dev_master_encryption_key_2025_replace_in_production"

# Verify keys different
if [ "$TAIFABASE_ENCRYPTION_KEY_DEV" = "$TAIFABASE_ENCRYPTION_KEY_DEV_PREVIOUS" ]; then
    echo "ERROR: New key same as old key"
    exit 1
fi

echo "✅ New encryption key generated"
```

#### Step 2: Update Key Management Configuration

Update `database/config/key-management-config.sh`:

```bash
# Update master encryption key
export TAIFABASE_ENCRYPTION_KEY_DEV="<new_key_from_step_1>"

# Keep previous key for grace period
export TAIFABASE_ENCRYPTION_KEY_DEV_PREVIOUS="<old_key>"

# Mark rotation timestamp
export TAIFABASE_KEY_LAST_ROTATED="2025-10-06"
```

#### Step 3: Restart PostgreSQL Service

```bash
# Source updated configuration
source database/config/key-management-config.sh

# Restart PostgreSQL to load new environment variables
docker-compose restart postgres

# Verify PostgreSQL healthy
docker-compose ps postgres
# Expected: Status "healthy"
```

#### Step 4: Re-encrypt Existing Data

**Create Re-encryption Script** (`database/scripts/key-management/re-encrypt-data.sql`):

```sql
-- Re-encryption Script
-- Re-encrypts all sensitive data with new encryption key

\echo 'Starting data re-encryption with new key...'

-- Re-encrypt core.users.email_encrypted
UPDATE core.users
SET email_encrypted = encrypt_sensitive_data(
    decrypt_sensitive_data(email_encrypted)  -- Decrypt with old key
)  -- Re-encrypt with new key
WHERE email_encrypted IS NOT NULL;

\echo 'Re-encrypted core.users.email_encrypted'

-- Re-encrypt tenant.api_keys.key_value_encrypted
UPDATE tenant.api_keys
SET key_value_encrypted = encrypt_sensitive_data(
    decrypt_sensitive_data(key_value_encrypted)  -- Decrypt with old key
)  -- Re-encrypt with new key
WHERE key_value_encrypted IS NOT NULL;

\echo 'Re-encrypted tenant.api_keys.key_value_encrypted'

\echo '✅ Data re-encryption complete'
```

**Execute Re-encryption**:

```bash
# Run re-encryption script
docker-compose exec postgres psql -U taifabase_user -d taifabase_dev -f /docker-entrypoint-initdb.d/key-management/re-encrypt-data.sql

# Verify re-encryption
docker-compose exec postgres psql -U taifabase_user -d taifabase_dev -c "
SELECT COUNT(*) AS total_encrypted_emails FROM core.users WHERE email_encrypted IS NOT NULL;
SELECT COUNT(*) AS total_encrypted_keys FROM tenant.api_keys WHERE key_value_encrypted IS NOT NULL;
"
```

#### Step 5: Validation

**Verify decryption works with new key**:

```sql
-- Test decryption with new key
SELECT
    decrypt_sensitive_data(email_encrypted) AS decrypted_email
FROM core.users
WHERE email_encrypted IS NOT NULL
LIMIT 5;

-- Expected: Emails decrypt successfully
-- If decryption fails, rollback to old key immediately
```

**Verify no data corruption**:

```sql
-- Check for null encrypted data (indicates re-encryption failure)
SELECT COUNT(*) FROM core.users WHERE email IS NOT NULL AND email_encrypted IS NULL;
-- Expected: 0 (all data re-encrypted)

SELECT COUNT(*) FROM tenant.api_keys WHERE key_value IS NOT NULL AND key_value_encrypted IS NULL;
-- Expected: 0 (all data re-encrypted)
```

#### Step 6: Rollback Plan (if needed)

**If re-encryption fails**:

```bash
# Revert to old key
export TAIFABASE_ENCRYPTION_KEY_DEV="$TAIFABASE_ENCRYPTION_KEY_DEV_PREVIOUS"

# Update configuration
# Edit database/config/key-management-config.sh
# Restore old key

# Restart PostgreSQL
docker-compose restart postgres

# Verify decryption works
docker-compose exec postgres psql -U taifabase_user -d taifabase_dev -c "
SELECT decrypt_sensitive_data(email_encrypted) FROM core.users LIMIT 1;
"
```

#### Step 7: Disable Old Key (After 30-Day Validation)

```bash
# Remove old key from configuration (after 30-day grace period)
unset TAIFABASE_ENCRYPTION_KEY_DEV_PREVIOUS

# Update key-management-config.sh
# Remove TAIFABASE_ENCRYPTION_KEY_DEV_PREVIOUS line

# Restart PostgreSQL
docker-compose restart postgres
```

---

## Automated Key Rotation (Production - US-901, Day 6-8)

### Automation Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Key Rotation Scheduler                      │
│  (Cron job / Kubernetes CronJob)                        │
│  Frequency: Every 90 days                               │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│         Key Rotation Orchestration Script               │
│  1. Generate new key in Vault                           │
│  2. Update key metadata (generation date, expiration)   │
│  3. Trigger re-encryption job                           │
│  4. Monitor re-encryption progress                      │
│  5. Validate re-encryption success                      │
│  6. Disable old key after validation                    │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│  Vault   │  │ Database │  │ Audit    │
│  (Key    │  │ (Re-     │  │ Logging  │
│  Storage)│  │ encrypt) │  │          │
└──────────┘  └──────────┘  └──────────┘
```

### Implementation Steps (US-901, Day 6-8)

**Day 6**: Key rotation script development
- Create `database/scripts/key-management/auto-rotate-keys.sh`
- Integrate with HashiCorp Vault API (or AWS Secrets Manager)
- Re-encryption job with progress tracking

**Day 7**: Testing and validation
- Test rotation in development environment
- Verify re-encryption works correctly
- Rollback testing

**Day 8**: Production deployment
- Deploy to staging environment
- Schedule production key rotation (90-day cycle)
- Set up monitoring and alerts

### Automated Rotation Script (Skeleton - Day 6 Implementation)

**File**: `database/scripts/key-management/auto-rotate-keys.sh`

```bash
#!/bin/bash
# Automated Key Rotation Script
# Implements automated key rotation for production environments
# US-901 (Secrets Rotation Automation)

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail

# Configuration
VAULT_ADDR="${TAIFABASE_VAULT_ADDR}"
VAULT_TOKEN="${TAIFABASE_VAULT_TOKEN}"
DB_HOST="${POSTGRES_HOST:-localhost}"
DB_PORT="${PGBOUNCER_PORT:-5433}"
DB_NAME="${POSTGRES_DB:-taifabase_dev}"
DB_USER="${POSTGRES_USER:-taifabase_user}"

LOG_FILE="/var/log/taifabase/key-rotation-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Step 1: Generate new key in Vault
generate_new_key() {
    log "Generating new encryption key in Vault..."

    # Call Vault API to generate new key
    new_key=$(vault kv put secret/taifabase/encryption-keys \
        master_key=$(openssl rand -base64 32) \
        generated_at=$(date -Iseconds) \
        expires_at=$(date -d '+90 days' -Iseconds))

    log "✅ New key generated in Vault"
}

# Step 2: Re-encrypt data
re_encrypt_data() {
    log "Starting data re-encryption..."

    # Execute re-encryption SQL script
    PGPASSWORD="${POSTGRES_PASSWORD}" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -f database/scripts/key-management/re-encrypt-data.sql \
        2>&1 | tee -a "$LOG_FILE"

    log "✅ Data re-encryption complete"
}

# Step 3: Validate re-encryption
validate_re_encryption() {
    log "Validating re-encryption..."

    # Check for null encrypted data
    null_count=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -t -c "SELECT COUNT(*) FROM core.users WHERE email IS NOT NULL AND email_encrypted IS NULL;")

    if [ "$null_count" -gt 0 ]; then
        log "❌ Validation failed: $null_count records not re-encrypted"
        exit 1
    fi

    log "✅ Validation passed: All records re-encrypted"
}

# Step 4: Disable old key
disable_old_key() {
    log "Disabling old encryption key..."

    # Mark old key as disabled in Vault
    vault kv patch secret/taifabase/encryption-keys/previous \
        enabled=false \
        disabled_at=$(date -Iseconds)

    log "✅ Old key disabled"
}

# Main execution
main() {
    log "==================================="
    log "Starting Automated Key Rotation"
    log "==================================="

    generate_new_key
    re_encrypt_data
    validate_re_encryption
    disable_old_key

    log "==================================="
    log "Key Rotation Complete"
    log "==================================="
}

# Run main function
main
```

---

## Production Key Management (HashiCorp Vault - Phase 6)

### Vault Setup

**Step 1: Deploy Vault Cluster** (HA configuration):

```bash
# Deploy Vault using Helm chart
helm install vault hashicorp/vault \
    --set server.ha.enabled=true \
    --set server.ha.replicas=3 \
    --set server.dataStorage.size=10Gi

# Initialize Vault
kubectl exec -it vault-0 -- vault operator init

# Unseal Vault (requires 3 of 5 unseal keys)
kubectl exec -it vault-0 -- vault operator unseal <key1>
kubectl exec -it vault-0 -- vault operator unseal <key2>
kubectl exec -it vault-0 -- vault operator unseal <key3>
```

**Step 2: Configure PostgreSQL Secrets Engine**:

```bash
# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Create encryption key storage path
vault kv put secret/taifabase/encryption-keys \
    master_key="<generated_key>" \
    generated_at=$(date -Iseconds) \
    expires_at=$(date -d '+90 days' -Iseconds)

# Create read policy for PostgreSQL
vault policy write taifabase-encryption - <<EOF
path "secret/data/taifabase/encryption-keys" {
  capabilities = ["read"]
}
EOF
```

**Step 3: Integrate PostgreSQL with Vault**:

Update `get_encryption_key()` function to retrieve key from Vault:

```sql
CREATE OR REPLACE FUNCTION get_encryption_key(
    key_id UUID DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    vault_addr TEXT := current_setting('taifabase.vault_addr');
    vault_token TEXT := current_setting('taifabase.vault_token');
    encryption_key TEXT;
BEGIN
    -- Call Vault API to retrieve encryption key
    -- (Requires HTTP extension or external script)

    -- For Phase 6: Implement Vault API integration
    -- For Sprint 2: Document approach, implement in Phase 6

    RAISE EXCEPTION 'Production Vault integration pending (Phase 6)';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## Monitoring and Alerts

### Key Rotation Monitoring

**Metrics to Track**:
- Key age (days since last rotation)
- Key expiration date
- Re-encryption progress (percentage complete)
- Re-encryption errors

**Prometheus Metrics** (US-901 implementation):

```prometheus
# Key age metric
taifabase_encryption_key_age_days{key_type="master"} 45

# Days until expiration
taifabase_encryption_key_expires_in_days{key_type="master"} 45

# Re-encryption progress
taifabase_re_encryption_progress_percent 75.5

# Re-encryption errors
taifabase_re_encryption_errors_total 0
```

**Grafana Dashboards**:
- Key rotation timeline (last rotation, next rotation)
- Re-encryption progress gauge
- Error rate chart
- Audit log table

---

## Audit Logging

### Key Access Audit

Every key retrieval MUST be logged for security audit:

```sql
CREATE TABLE IF NOT EXISTS audit.key_access_log (
    id BIGSERIAL PRIMARY KEY,
    key_id UUID,
    operation VARCHAR(50),  -- 'retrieve', 'rotate', 'disable'
    user_id VARCHAR(255),
    timestamp TIMESTAMPTZ DEFAULT now(),
    source_ip INET,
    success BOOLEAN
);

-- Log key access
INSERT INTO audit.key_access_log (key_id, operation, user_id, success)
VALUES (NULL, 'retrieve', current_user, true);
```

### Key Rotation Audit

Every key rotation MUST be logged for compliance:

```sql
CREATE TABLE IF NOT EXISTS audit.key_rotation_log (
    id BIGSERIAL PRIMARY KEY,
    old_key_id UUID,
    new_key_id UUID,
    rotation_type VARCHAR(50),  -- 'manual', 'automated'
    rotation_timestamp TIMESTAMPTZ DEFAULT now(),
    rotation_status VARCHAR(50),  -- 'success', 'failed', 'rollback'
    records_re_encrypted INTEGER,
    rotation_duration_seconds INTEGER,
    performed_by VARCHAR(255)
);

-- Log key rotation
INSERT INTO audit.key_rotation_log (
    old_key_id, new_key_id, rotation_type, rotation_status,
    records_re_encrypted, performed_by
) VALUES (
    '<old_key_id>', '<new_key_id>', 'manual', 'success',
    10000, current_user
);
```

---

## Compliance Checklist

### SOC2 CC6.6 Requirements

- [ ] Encryption keys rotated every 90 days (maximum)
- [ ] Key rotation documented and tested
- [ ] Key rotation automated (production)
- [ ] Audit trail of all key operations
- [ ] Old keys retained for rollback (30 days)
- [ ] Old keys archived for audit (7 years)
- [ ] Key rotation monitoring and alerts
- [ ] Key rotation tested in development/staging

### GDPR Article 32 Requirements

- [ ] Appropriate technical measures (key management)
- [ ] Regular testing of security measures (key rotation testing)
- [ ] Ability to restore availability (rollback plan)
- [ ] Audit logging of key access (transparency)

---

## References

- **Key Management Config**: `database/config/key-management-config.sh`
- **Work Instructions**: `communications/sprint-2-day-1-work-instructions.md`
- **User Story**: US-901 (Secrets Rotation Automation, Day 6-8)
- **SOC2 CC6.6**: Key management controls
- **HashiCorp Vault Docs**: https://www.vaultproject.io/docs

---

**Document Status**: Day 1 Manual Procedures Complete, Day 6-8 Automation Pending
**Next Update**: Day 6 (after US-901 automation implementation)
**Questions**: Contact Raj Patel (DevOps Engineer) or escalate to Sarah Chen (PM)
