# Encryption at Rest Strategy

**Document Metadata**
- **Created**: 2025-10-06 (Sprint 2, Day 1)
- **Version**: 1.0
- **Owner**: Marcus Rodriguez (Backend Engineer)
- **Reviewed By**: Dr. Kenji Tanaka (Security Engineer) - Approved 2:00 PM encryption deep dive
- **Status**: Day 1 Foundation → Day 2 Implementation → Day 3 Testing

---

## Executive Summary

This document outlines the encryption at rest implementation strategy for Taifabase, addressing **Priority 2** compliance gaps:
- **GDPR Article 32**: Encryption of personal data (Current: 85%, Target: 95%)
- **SOC2 CC6.7**: Encryption of sensitive data at rest (Current: 85%, Target: 95%)

**Approach**: PostgreSQL pgcrypto extension with selective column-level encryption
**Timeline**: Day 1 foundation, Day 2 implementation, Day 3 testing
**Performance Target**: <5% overhead (hard requirement)

---

## Encryption Approach

### Technology Selection: PostgreSQL pgcrypto

**Decision**: Use PostgreSQL pgcrypto extension for encryption at rest (approved by Kenji - 2:00 PM deep dive)

**Rationale**:

✅ **Advantages**:
1. **Native PostgreSQL Extension**: No external dependencies, built-in support
2. **Selective Encryption**: Encrypt only sensitive columns (performance optimization)
3. **AES-256 Encryption**: Industry standard, GDPR/SOC2 compliant
4. **Flexible Key Management**: Can integrate with external key systems (Raj's US-602)
5. **RLS Compatible**: Works seamlessly with existing RLS policies (Sprint 1)
6. **Proven Technology**: Widely used in production, battle-tested

⚠️ **Considerations**:
1. **Performance Overhead**: Encryption/decryption on queries (mitigation: <5% target, testing Day 3)
2. **Key Management Complexity**: Keys must be stored securely (Raj's US-602)
3. **Query Complexity**: Encrypted columns require explicit `decrypt_sensitive_data()` calls
4. **Data Migration**: Existing data needs re-encryption (Day 2 migration scripts)

**Alternative Considered**: Transparent Data Encryption (TDE)
- ❌ Encrypts entire database (less granular control)
- ❌ Harder to audit specific data access
- ❌ May not meet compliance requirements for column-level encryption
- ✅ Lower performance overhead
- **Fallback Plan**: If pgcrypto overhead >10% on Day 3, evaluate TDE

---

## Sensitive Columns for Encryption

### Priority 1 (Day 2) - MUST Encrypt

These columns contain highly sensitive data (PII, credentials) and MUST be encrypted for GDPR/SOC2 compliance:

| Table | Column | Data Type | Reason | Compliance |
|-------|--------|-----------|--------|------------|
| `core.users` | `email` | VARCHAR(255) | PII - email addresses | GDPR Article 4(1) |
| `tenant.api_keys` | `key_value` | VARCHAR(512) | Security credentials (API keys, tokens) | SOC2 CC6.1 |
| `core.users` | `password_hash` | VARCHAR(255) | Authentication secrets (if stored) | SOC2 CC6.1 |

**Implementation Plan (Day 2)**:
1. Add new encrypted columns (e.g., `email_encrypted BYTEA`)
2. Migrate existing data using `encrypt_sensitive_data()` function
3. Deprecate old plaintext columns (or drop after validation)
4. Update application queries to use `decrypt_sensitive_data()`

### Priority 2 (Day 3, if time) - SHOULD Encrypt

Additional PII fields that should be encrypted if time permits:

| Table | Column | Data Type | Reason |
|-------|--------|-----------|--------|
| `core.users` | `phone_number` | VARCHAR(20) | PII - phone numbers (if exists) |
| `tenant.sample_data` | `sensitive_field` | TEXT | Any PII fields discovered during implementation |

**Note**: Prioritize Priority 1 columns first. Only implement Priority 2 if Day 2 goes smoothly and Day 3 testing validates performance.

### NOT Encrypted - Don't Need Encryption

These columns do NOT need encryption (not sensitive or needed for queries):

| Column Type | Reason |
|-------------|--------|
| `tenant_id` | Needed for RLS filtering, not sensitive |
| `created_at`, `updated_at` | Metadata, not sensitive |
| Aggregate counts, statistics | Not PII, already anonymized |
| User IDs (UUIDs) | Random identifiers, not personally identifiable |

---

## Performance Targets

### Hard Requirements

**<5% Overhead** (CRITICAL)
- Encryption/decryption operations must add <5% to query execution time
- Baseline: Sprint 1 RLS performance (1.3x overhead for RLS)
- Target: RLS + Encryption <1.4x overhead total
- **Measurement**: Aisha's US-603 testing (Day 3)

**Acceptable**
- <10% overhead with strong security justification
- Requires discussion with Kenji and PM before proceeding

**Unacceptable**
- >10% overhead triggers TDE evaluation (Day 4)
- May require architecture redesign or scope reduction

### Performance Testing Approach (Day 3 - Aisha)

**Baseline Queries** (no encryption):
```sql
-- Simple SELECT
SELECT email FROM core.users WHERE user_id = 'test-uuid';
-- Sprint 1 baseline: ~0.5ms

-- With RLS filtering
SELECT * FROM tenant.sample_data WHERE tenant_id = 'alpha-uuid' LIMIT 100;
-- Sprint 1 baseline: ~2ms (1.3x overhead from RLS)
```

**Encrypted Queries**:
```sql
-- Simple SELECT with decryption
SELECT decrypt_sensitive_data(email_encrypted) FROM core.users WHERE user_id = 'test-uuid';
-- Target: <0.525ms (<5% overhead = 0.5ms * 1.05)

-- With RLS filtering (no decryption needed if not selecting encrypted columns)
SELECT * FROM tenant.sample_data WHERE tenant_id = 'alpha-uuid' LIMIT 100;
-- Target: <2.1ms (no change if not decrypting)
```

**Load Testing** (1000+ concurrent users):
- Reuse Sprint 1 k6 load testing framework
- Validate performance under load with encrypted queries
- Ensure no regression from Sprint 1 baselines

---

## Encryption Architecture

### Function Design

**Three Core Functions**:

1. **`get_encryption_key(key_id UUID)`**
   - Retrieves encryption key from key management system (Raj's US-602)
   - Day 1: Placeholder (hardcoded dev key)
   - Day 2: Environment variable integration (Raj delivers 11:00 AM)
   - Phase 6: HashiCorp Vault integration (production)

2. **`encrypt_sensitive_data(plaintext TEXT, key_id UUID)`**
   - Encrypts plaintext using AES-256 (via pgp_sym_encrypt)
   - Input validation (null check, length limit - Kenji's recommendation)
   - Audit logging placeholder (implement Day 2)
   - Returns BYTEA (ciphertext)

3. **`decrypt_sensitive_data(ciphertext BYTEA, key_id UUID)`**
   - Decrypts ciphertext back to plaintext
   - Error handling for wrong key or corrupted data
   - Audit logging placeholder (implement Day 2)
   - Returns TEXT (plaintext)

### Security Enhancements (Kenji's Recommendations - 2:00 PM Deep Dive)

✅ **Input Validation**:
- Null/empty plaintext rejection
- Length limit (10,000 chars) for DOS protection
- Implemented in Day 1 functions

✅ **Audit Logging** (Day 2 implementation):
```sql
-- Log encryption/decryption operations
INSERT INTO audit.encryption_log (
    operation,     -- 'encrypt' or 'decrypt'
    key_id,        -- Which key was used
    user_id,       -- Who performed the operation
    timestamp,     -- When it happened
    data_length    -- Size of data (for encrypt only)
) VALUES (...);
```

✅ **Key Access Control** (Raj's responsibility - US-602):
- `get_encryption_key()` must validate user permissions
- Not all users should access all keys
- Consider per-tenant keys for multi-tenant isolation (Phase 6)

✅ **Error Handling**:
- Decryption failures logged and raise exceptions
- Prevents silent data corruption

---

## Integration Points

### Day 2: Key Management Integration (Raj - US-602)

**Raj's Deliverable** (11:00 AM Day 2):
- Replace `get_encryption_key()` placeholder with environment variable integration
- Provide key storage configuration (development: env vars, production: Vault plan)
- Key access logging

**Marcus's Integration** (Day 2 afternoon):
- Update `get_encryption_key()` function with Raj's implementation
- Test encryption/decryption with real key management
- Remove hardcoded placeholder

### Day 2: Priority 1 Column Encryption

**Implementation Steps**:

1. **Add Encrypted Columns**:
```sql
-- Add new encrypted columns to existing tables
ALTER TABLE core.users ADD COLUMN email_encrypted BYTEA;
ALTER TABLE tenant.api_keys ADD COLUMN key_value_encrypted BYTEA;
```

2. **Data Migration Script**:
```sql
-- Migrate existing data to encrypted columns
UPDATE core.users
SET email_encrypted = encrypt_sensitive_data(email)
WHERE email IS NOT NULL AND email_encrypted IS NULL;

UPDATE tenant.api_keys
SET key_value_encrypted = encrypt_sensitive_data(key_value)
WHERE key_value IS NOT NULL AND key_value_encrypted IS NULL;
```

3. **Validation**:
```sql
-- Verify all data migrated
SELECT COUNT(*) FROM core.users WHERE email IS NOT NULL AND email_encrypted IS NULL;
-- Expected: 0 (all data encrypted)

-- Verify decryption works
SELECT
    email AS original,
    decrypt_sensitive_data(email_encrypted) AS decrypted,
    (email = decrypt_sensitive_data(email_encrypted)) AS matches
FROM core.users
LIMIT 10;
-- Expected: matches = TRUE for all rows
```

4. **Deprecate Plaintext Columns** (after validation):
```sql
-- Rename plaintext columns to indicate deprecated
ALTER TABLE core.users RENAME COLUMN email TO email_deprecated;

-- Or drop after validation period (Phase 6)
-- ALTER TABLE core.users DROP COLUMN email_deprecated;
```

### Day 3: Testing (Aisha - US-603)

**Aisha's Deliverable**:
- Functional testing (encrypt/decrypt round-trip)
- Security testing (encrypted data not readable, unauthorized access fails)
- Performance testing (<5% overhead validation)
- Load testing (1000+ concurrent users)
- Integration testing (RLS + Encryption)

**Marcus's Support**:
- Provide test data setup scripts (Day 2 afternoon)
- Assist with performance optimization if overhead >5%
- Troubleshoot any encryption issues

---

## Compliance Validation

### GDPR Article 32 - "Appropriate Technical Measures"

**Requirements**:
- ✅ Encryption of personal data (Article 32.1.a)
- ✅ Pseudonymization (tenant isolation via RLS - Sprint 1)
- ✅ Ability to restore availability (backup system - Sprint 1)
- 🔄 Regular testing of security measures (US-603 - Day 3)

**Compliance Score**: 85% → **95%** (after Day 3 validation)

### SOC2 CC6.7 - "Encryption"

**Requirements**:
- ✅ Sensitive data encrypted at rest
- ✅ Encryption keys managed separately (Raj's US-602)
- 🔄 Key rotation procedures (US-901, Day 6-8)
- 🔄 Access controls for decryption (audit logging - Day 2)

**Compliance Score**: 85% → **95%** (after Day 2-3 implementation)

---

## Risk Mitigation

### Risk 1: Encryption Performance Overhead >5%

**Probability**: Medium (30%)
**Impact**: High (may require architecture change)

**Mitigation**:
- Early performance testing (Day 3, Aisha)
- Query optimization (use indexes on non-encrypted columns)
- Caching strategies (decrypt once per session, cache result)
- Fallback: TDE evaluation (Day 4 if needed)

### Risk 2: Key Management Integration Complexity

**Probability**: Low (20%)
**Impact**: Medium (delays encryption testing)

**Mitigation**:
- Clear interface definition (Day 1, Marcus + Raj lunch sync) ✅
- Placeholder approach allows parallel work ✅
- Daily sync to identify issues early

### Risk 3: Data Migration Issues

**Probability**: Low (15%)
**Impact**: Medium (delays Day 3 testing)

**Mitigation**:
- Incremental migration (one table at a time)
- Validation after each migration
- Rollback plan (keep plaintext columns until validation complete)

---

## Implementation Timeline

### Day 1 (Today - 3:15-5:30 PM) ✅

- [x] Enable pgcrypto extension
- [x] Create encryption/decryption functions with security enhancements
- [x] Placeholder key management (`get_encryption_key()` hardcoded)
- [x] Document encryption strategy
- [x] DRAFT PR created

### Day 2 (Tomorrow)

- [ ] 11:00 AM: Raj delivers `get_encryption_key()` with environment variable integration
- [ ] Afternoon: Marcus integrates Raj's key management
- [ ] Afternoon: Encrypt Priority 1 columns (core.users.email, tenant.api_keys.key_value)
- [ ] Afternoon: Create data migration scripts
- [ ] Afternoon: Provide test data scripts to Aisha
- [ ] Evening: Implement audit logging (encryption_log table)

### Day 3

- [ ] Morning: Aisha executes functional and security tests
- [ ] Afternoon: Aisha executes performance testing
- [ ] Evening: Performance report (overhead calculation)
- [ ] Evening: Go/No-Go decision on encryption approach
- [ ] Evening: Finalize PR (ready for merge)

### Day 4 (if needed)

- [ ] Performance optimization (if overhead >5%)
- [ ] TDE evaluation (if overhead >10%)
- [ ] Final validation and PR merge

---

## Success Criteria

### Day 1 Success Criteria ✅

- [x] pgcrypto extension operational
- [x] Encryption functions created with security enhancements
- [x] Input validation implemented (null, empty, length checks)
- [x] Audit logging placeholders added
- [x] Encryption strategy documented
- [x] DRAFT PR created

### Day 2 Success Criteria

- [ ] Key management integrated (Raj → Marcus)
- [ ] Priority 1 columns encrypted (core.users.email, tenant.api_keys.key_value)
- [ ] Data migration scripts tested
- [ ] Audit logging implemented
- [ ] Test data scripts provided to Aisha

### Day 3 Success Criteria

- [ ] All functional tests passing
- [ ] All security tests passing
- [ ] Performance overhead <5% (or <10% with justification)
- [ ] Load testing: 1000+ concurrent users supported
- [ ] RLS + Encryption integration validated
- [ ] Performance report delivered

### Final Success Criteria (PR Merge)

- [ ] GDPR Article 32 compliance: 85% → 95%
- [ ] SOC2 CC6.7 compliance: 85% → 95%
- [ ] Priority 1 sensitive data encrypted
- [ ] Performance overhead acceptable (<5%)
- [ ] All tests passing (functional, security, performance, integration)
- [ ] Code reviewed and approved (Kenji security review, PM approval)
- [ ] CI/CD pipeline green

---

## References

- **Meeting Notes**: `meetings/sprint-2-day-1-encryption-architecture-deep-dive.md`
- **Work Instructions**: `communications/sprint-2-day-1-work-instructions.md`
- **pgcrypto Documentation**: https://www.postgresql.org/docs/current/pgcrypto.html
- **GDPR Article 32**: https://gdpr-info.eu/art-32-gdpr/
- **SOC2 CC6.7**: Encryption controls for data at rest

---

**Document Status**: Day 1 Complete, Day 2 Ready
**Next Update**: End of Day 2 (after key management integration and Priority 1 encryption)
**Questions/Issues**: Contact Marcus Rodriguez (Backend Engineer) or escalate to Sarah Chen (PM)
