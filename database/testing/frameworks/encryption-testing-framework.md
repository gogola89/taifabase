# Encryption Testing Framework - US-603

**Document Metadata**
- **Created**: 2025-10-06 (Sprint 2, Day 1)
- **Version**: 1.0
- **Owner**: Aisha Kamau (QA Engineer)
- **Status**: Framework Design (Day 1) → Execution (Day 3-4)
- **Related**: Marcus's US-601 (Encryption at Rest), Raj's US-602 (Key Management)

---

## Testing Objectives

1. **Functionality**: Verify encryption/decryption works correctly
2. **Security**: Ensure encrypted data is not readable without key
3. **Performance**: Encryption overhead <5% (CRITICAL requirement from 2:00 PM deep dive)
4. **RLS Compatibility**: Encryption works seamlessly with existing RLS policies (Sprint 1)
5. **Recovery**: Encrypted data recoverable from backups
6. **Compliance**: Meet GDPR Article 32 and SOC2 CC6.7 requirements

---

## Test Categories

### 1. Functional Tests (Day 3 Morning)

**Objective**: Verify encryption/decryption functions work correctly

**Tests**:
1. **Encrypt Plaintext → Verify Ciphertext Not Readable**
   ```sql
   -- Encrypt sensitive data
   SELECT encrypt_sensitive_data('test_email@example.com') AS ciphertext;
   -- Expected: BYTEA (unreadable hex/binary data)
   -- Verification: ciphertext != 'test_email@example.com'
   ```

2. **Decrypt Ciphertext → Verify Plaintext Matches Original**
   ```sql
   -- Decrypt ciphertext
   SELECT decrypt_sensitive_data(
       encrypt_sensitive_data('test_email@example.com')
   ) AS plaintext;
   -- Expected: 'test_email@example.com'
   ```

3. **Round-Trip Testing** (Encrypt → Decrypt → Verify)
   ```sql
   WITH test_data AS (
       SELECT 'sensitive@example.com' AS original
   )
   SELECT
       original,
       encrypt_sensitive_data(original) AS encrypted,
       decrypt_sensitive_data(encrypt_sensitive_data(original)) AS decrypted,
       (original = decrypt_sensitive_data(encrypt_sensitive_data(original))) AS matches
   FROM test_data;
   -- Expected: matches = TRUE
   ```

4. **Key Rotation Testing** (Re-encrypt with New Key)
   - Encrypt data with old key
   - Rotate key (Raj's US-602 procedure)
   - Re-encrypt data with new key
   - Verify decryption with new key works
   - Verify old key no longer decrypts (after grace period)

5. **Error Handling**
   - Invalid key (wrong key ID)
   - Corrupted ciphertext
   - Null plaintext
   - Empty plaintext
   - Oversized plaintext (>10,000 chars - DOS protection test)

**Success Criteria**:
- All round-trip tests return original plaintext
- Encrypted data unreadable in ciphertext
- Error handling works as expected (exceptions raised)
- Input validation prevents invalid operations

---

### 2. Security Tests (Day 3 Morning, with Kenji)

**Objective**: Ensure encrypted data is secure and not exposed

**Tests**:
1. **Encrypted Data Not Readable in Database Files**
   ```bash
   # Check PostgreSQL data directory
   strings /var/lib/postgresql/data/base/*/[table_oid] | grep "test_email@example.com"
   # Expected: No plaintext found (email encrypted in database files)
   ```

2. **Encrypted Data Not in Logs**
   ```bash
   # Check PostgreSQL logs
   grep "test_email@example.com" /var/log/postgresql/*.log
   # Expected: No plaintext in logs (only ciphertext if logged)
   ```

3. **Unauthorized Decryption Attempt Fails**
   ```sql
   -- Attempt decryption without proper key access
   -- (Requires role without decrypt permission)
   SET ROLE unprivileged_user;
   SELECT decrypt_sensitive_data(email_encrypted) FROM core.users LIMIT 1;
   -- Expected: Permission denied or decryption error
   ```

4. **Key Retrieval Authorization Checks**
   ```sql
   -- Test key access control (Raj's US-602)
   SET ROLE unauthorized_user;
   SELECT get_encryption_key();
   -- Expected: Access denied (key access restricted)
   ```

5. **Audit Logging of Encryption/Decryption Operations**
   ```sql
   -- Encrypt data
   SELECT encrypt_sensitive_data('audit_test@example.com');

   -- Check audit log
   SELECT * FROM audit.encryption_log
   WHERE operation = 'encrypt'
   AND user_id = current_user
   ORDER BY timestamp DESC LIMIT 1;
   -- Expected: Log entry exists with timestamp, user, operation
   ```

**Success Criteria** (Kenji's priorities from 2:00 PM deep dive):
- Encrypted data not readable in database files ✅ CRITICAL
- Unauthorized decryption fails ✅ CRITICAL
- Audit logging captures all encryption operations
- Key access restricted to authorized roles

---

### 3. Performance Tests (Day 3 Afternoon) - **CRITICAL**

**Objective**: Validate encryption overhead <5% (hard requirement from 2:00 PM deep dive)

#### 3.1 Baseline Performance (Sprint 1, No Encryption)

**Simple SELECT**:
```sql
EXPLAIN ANALYZE
SELECT email FROM core.users WHERE user_id = 'test-uuid-1';
-- Sprint 1 baseline: ~0.5ms
```

**With RLS Filtering**:
```sql
EXPLAIN ANALYZE
SELECT * FROM tenant.sample_data WHERE tenant_id = 'alpha-uuid' LIMIT 100;
-- Sprint 1 baseline: ~2ms (1.3x overhead from RLS)
```

**Aggregation**:
```sql
EXPLAIN ANALYZE
SELECT COUNT(*) FROM core.users WHERE created_at > '2025-01-01';
-- Sprint 1 baseline: ~1ms
```

#### 3.2 Encrypted Performance (Sprint 2, With Encryption)

**Simple SELECT with Decryption**:
```sql
EXPLAIN ANALYZE
SELECT decrypt_sensitive_data(email_encrypted) AS email
FROM core.users
WHERE user_id = 'test-uuid-1';
-- Target: <0.525ms (<5% overhead = 0.5ms * 1.05)
```

**With RLS Filtering (No Decryption)**:
```sql
EXPLAIN ANALYZE
SELECT * FROM tenant.sample_data WHERE tenant_id = 'alpha-uuid' LIMIT 100;
-- Target: <2.1ms (no change if not decrypting encrypted columns)
```

**Aggregation (No Decryption)**:
```sql
EXPLAIN ANALYZE
SELECT COUNT(*) FROM core.users WHERE created_at > '2025-01-01';
-- Target: ~1ms (no change, not accessing encrypted columns)
```

**Aggregation with Decryption**:
```sql
EXPLAIN ANALYZE
SELECT COUNT(DISTINCT decrypt_sensitive_data(email_encrypted))
FROM core.users;
-- Target: Measure overhead, optimize if needed
```

#### 3.3 Performance Overhead Calculation

```
Overhead (%) = (Encrypted Time - Baseline Time) / Baseline Time * 100%

Example:
Baseline: 0.5ms
Encrypted: 0.52ms
Overhead: (0.52 - 0.5) / 0.5 * 100% = 4%  ✅ PASS (<5%)

Baseline: 0.5ms
Encrypted: 0.6ms
Overhead: (0.6 - 0.5) / 0.5 * 100% = 20%  ❌ FAIL (>5%, investigate)
```

#### 3.4 Load Testing (1000+ Concurrent Users)

**Objective**: Validate performance under load with encrypted queries

**Tools**: k6 (reuse Sprint 1 framework)

**Test Scenario**:
```javascript
// k6 load test script (database/testing/load-tests/encryption-load-test.js)
import { check } from 'k6';
import sql from 'k6/x/sql';

export let options = {
    vus: 1000,  // 1000 virtual users
    duration: '5m',  // 5 minutes
};

export default function () {
    const db = sql.open('postgres', 'postgresql://user:pass@localhost:5433/taifabase_dev');

    // Query with decryption
    const result = sql.query(db, `
        SELECT decrypt_sensitive_data(email_encrypted) AS email
        FROM core.users
        WHERE user_id = 'test-uuid-${__VU}'
    `);

    check(result, {
        'query successful': (r) => r.length > 0,
        'decryption successful': (r) => r[0].email != null,
    });

    db.close();
}
```

**Success Criteria**:
- 1000+ concurrent users supported
- Average response time <100ms (p95)
- No errors or timeouts
- Database CPU <80%, memory <80%

#### 3.5 Performance Targets Summary

| Metric | Target | Acceptable | Unacceptable |
|--------|--------|------------|--------------|
| **Encryption Overhead** | <5% | <10% (with justification) | >10% (TDE evaluation required) |
| **Simple Query (Decrypt)** | <0.525ms | <0.55ms | >0.55ms |
| **Load Testing (1000 users)** | P95 <100ms | P95 <150ms | P95 >150ms |
| **Database CPU** | <70% | <80% | >80% |

**Fallback Plan** (if overhead >10%):
- Investigate query optimization (indexes on non-encrypted columns)
- Caching strategies (decrypt once per session, cache in application)
- Evaluate Transparent Data Encryption (TDE) as alternative (Day 4)

---

### 4. Integration Tests (Day 3 Evening)

**Objective**: Validate encryption works with existing systems

**Tests**:
1. **RLS + Encryption: Tenant Isolation with Encrypted Data**
   ```sql
   -- Switch to tenant A
   SELECT switch_to_tenant('acme-corp');

   -- Query encrypted data
   SELECT decrypt_sensitive_data(email_encrypted) FROM core.users;
   -- Expected: Only tenant A users returned (RLS enforced)

   -- Switch to tenant B
   SELECT switch_to_tenant('techstart-inc');

   -- Query encrypted data
   SELECT decrypt_sensitive_data(email_encrypted) FROM core.users;
   -- Expected: Only tenant B users returned (RLS enforced)

   -- Verify no cross-tenant leakage
   -- Expected: Tenant A cannot see tenant B's encrypted data
   ```

2. **Audit Logging: Encryption Events Logged**
   ```sql
   -- Perform encryption operation
   SELECT encrypt_sensitive_data('audit_integration_test@example.com');

   -- Check audit log integration
   SELECT * FROM audit.encryption_log
   WHERE operation = 'encrypt'
   ORDER BY timestamp DESC LIMIT 1;
   -- Expected: Log entry with timestamp, user, operation, data length
   ```

3. **Backup/Recovery: Encrypted Data Recoverable**
   ```bash
   # Create backup
   pg_dump -U taifabase_user taifabase_dev > backup.sql

   # Restore to test database
   createdb taifabase_test
   psql -U taifabase_user taifabase_test < backup.sql

   # Verify encrypted data recovered
   psql -U taifabase_user taifabase_test -c "
       SELECT decrypt_sensitive_data(email_encrypted) FROM core.users LIMIT 1;
   "
   # Expected: Decryption successful, data matches original
   ```

4. **PgBouncer: Connection Pooling with Encryption**
   ```sql
   -- Connect via PgBouncer (port 5433)
   \c postgresql://localhost:5433/taifabase_dev

   -- Execute encrypted query
   SELECT decrypt_sensitive_data(email_encrypted) FROM core.users LIMIT 5;
   -- Expected: Works correctly through connection pooling
   ```

**Success Criteria**:
- RLS + Encryption: Tenant isolation maintained
- Audit logging: All encryption operations logged
- Backup/Recovery: Encrypted data fully recoverable
- PgBouncer: No issues with connection pooling

---

### 5. Compliance Tests (Day 4)

**Objective**: Validate GDPR Article 32 and SOC2 CC6.7 compliance

**Tests**:
1. **Encryption at Rest Verification** (GDPR Article 32)
   - Verify sensitive data encrypted in database files (strings command, no plaintext found)
   - Verify encryption strength (AES-256 via pgcrypto)
   - Document encryption implementation

2. **Key Management Validation** (SOC2 CC6.7)
   - Verify keys stored securely (Raj's US-602 implementation)
   - Verify key access logged (audit.key_access_log)
   - Verify key rotation procedures documented (90-day rotation plan)

3. **Encryption Strength Validation**
   ```sql
   -- Verify pgcrypto uses AES-256
   SELECT * FROM pg_extension WHERE extname = 'pgcrypto';
   -- Expected: pgcrypto version with AES-256 support
   ```

4. **Compliance Checklist Verification**
   - [ ] GDPR Article 32: Encryption of personal data ✅
   - [ ] GDPR Article 32: Pseudonymization (RLS - Sprint 1) ✅
   - [ ] GDPR Article 32: Regular testing of security measures (US-603 - this framework) ✅
   - [ ] SOC2 CC6.7: Sensitive data encrypted at rest ✅
   - [ ] SOC2 CC6.7: Encryption keys managed separately (Raj - US-602) ✅
   - [ ] SOC2 CC6.7: Key rotation procedures (Raj - US-602) ✅

**Success Criteria**:
- All compliance requirements met
- Documentation complete
- Audit trail established

---

## Performance Testing Approach (Detailed - Day 3)

### Step 1: Prepare Test Environment

```bash
# Ensure database in clean state
docker-compose restart postgres

# Load test data (Marcus's test data scripts - Day 2)
psql -U taifabase_user -d taifabase_dev -f /workspace/database/testing/scripts/test-data-setup.sql
```

### Step 2: Measure Baseline (No Encryption)

```sql
-- Execute baseline queries 100 times, record avg execution time
\timing on

-- Simple SELECT (100 iterations)
DO $$
DECLARE
    i INTEGER;
BEGIN
    FOR i IN 1..100 LOOP
        PERFORM email FROM core.users WHERE user_id = 'test-uuid-1';
    END LOOP;
END $$;

-- Record average time: ___ ms
```

### Step 3: Measure Encrypted Performance

```sql
-- Execute encrypted queries 100 iterations, record avg execution time
\timing on

-- Simple SELECT with decryption (100 iterations)
DO $$
DECLARE
    i INTEGER;
BEGIN
    FOR i IN 1..100 LOOP
        PERFORM decrypt_sensitive_data(email_encrypted) FROM core.users WHERE user_id = 'test-uuid-1';
    END LOOP;
END $$;

-- Record average time: ___ ms
```

### Step 4: Calculate Overhead

```
Baseline: ___ ms
Encrypted: ___ ms
Overhead: (___ - ___) / ___ * 100% = ___%

Result: ✅ PASS (<5%) or ❌ FAIL (>5%)
```

### Step 5: Load Testing

```bash
# Run k6 load test (1000 concurrent users, 5 minutes)
cd database/testing/load-tests
k6 run encryption-load-test.js

# Review results
# - Average response time
# - P95 response time
# - Error rate
# - Database CPU/memory usage
```

### Step 6: Document Results

Create performance report: `database/testing/reports/encryption-performance-report.md`

---

## Testing Tools

| Tool | Purpose | Usage |
|------|---------|-------|
| **PostgreSQL EXPLAIN ANALYZE** | Query performance measurement | Analyze query execution plans, identify bottlenecks |
| **\timing** | Query timing | Measure query execution time in psql |
| **pgBench** | Load testing | Simulate high concurrent user load |
| **k6** | Concurrent user simulation | Reuse Sprint 1 framework, test 1000+ users |
| **Custom SQL scripts** | Encryption verification | Test encryption/decryption functionality |
| **strings command** | Security testing | Verify plaintext not in database files |

---

## Day 3 Test Execution Plan

### Morning (9:00 AM - 12:00 PM): Functional & Security Tests

**9:00-10:00 AM**: Functional Testing
- Execute all functional tests (encrypt/decrypt, round-trip, error handling)
- Document results

**10:00-11:00 AM**: Security Testing (with Kenji)
- Encrypted data not readable in files
- Unauthorized decryption fails
- Audit logging verification
- Document security test results

**11:00 AM-12:00 PM**: Integration Testing Prep
- Set up test data (Marcus's scripts)
- Verify RLS policies active
- Prepare backup/recovery test

---

### Afternoon (1:00 PM - 5:00 PM): Performance Testing

**1:00-2:00 PM**: Baseline Measurements
- Run Sprint 1 baseline queries (no encryption)
- Record average execution times
- Document baseline performance

**2:00-3:30 PM**: Encrypted Performance Testing
- Run encrypted queries (with decryption)
- Record average execution times
- Calculate overhead percentage
- **CRITICAL DECISION POINT**: If overhead >5%, escalate to Marcus/IC

**3:30-4:30 PM**: Load Testing
- Execute k6 load tests (1000+ concurrent users)
- Monitor database CPU/memory
- Record response times (average, P95)

**4:30-5:00 PM**: Performance Report
- Calculate overhead for all query types
- Create performance report
- Make Go/No-Go recommendation

---

### Evening (5:00 PM - 6:00 PM): Integration Testing

**5:00-5:30 PM**: Integration Tests
- RLS + Encryption compatibility
- Audit logging integration
- PgBouncer compatibility

**5:30-6:00 PM**: Wrap-Up
- Complete test documentation
- Update DRAFT PR with test results
- Prepare for Day 4 (compliance testing, CI/CD integration)

---

## Day 4 Test Execution Plan

### Morning (9:00 AM - 12:00 PM): Compliance Testing & CI/CD Integration

**9:00-10:00 AM**: Compliance Validation
- GDPR Article 32 verification
- SOC2 CC6.7 verification
- Compliance checklist completion

**10:00 AM-12:00 PM**: CI/CD Integration
- Add encryption tests to CI/CD pipeline
- Automate functional tests
- Automate security tests (subset)

---

### Afternoon (1:00 PM - 5:00 PM): Final Validation & PR Finalization

**1:00-2:00 PM**: Backup/Recovery Testing
- Full backup and restore test
- Verify encrypted data recoverable

**2:00-4:00 PM**: Final Test Report
- Consolidate all test results
- Performance report finalization
- Compliance validation documentation

**4:00-5:00 PM**: PR Finalization
- Update Marcus's PR with test results
- Code review with Kenji (security validation)
- Ready for merge (if all tests pass)

---

## Success Criteria (Overall)

### Functional Testing ✅
- [ ] All round-trip tests pass (encrypt → decrypt → verify)
- [ ] Encrypted data unreadable in ciphertext
- [ ] Error handling works correctly
- [ ] Input validation prevents invalid operations

### Security Testing ✅
- [ ] Encrypted data not readable in database files
- [ ] Unauthorized decryption fails
- [ ] Audit logging captures all encryption operations
- [ ] Key access restricted to authorized roles

### Performance Testing ✅ (CRITICAL)
- [ ] Encryption overhead <5% (hard requirement)
- [ ] Load testing supports 1000+ concurrent users
- [ ] No regression from Sprint 1 baselines
- [ ] Database resource usage acceptable (<80% CPU/memory)

### Integration Testing ✅
- [ ] RLS + Encryption compatible (tenant isolation maintained)
- [ ] Audit logging integrated
- [ ] Backup/recovery successful (encrypted data recoverable)
- [ ] PgBouncer compatibility confirmed

### Compliance Testing ✅
- [ ] GDPR Article 32 requirements met
- [ ] SOC2 CC6.7 requirements met
- [ ] Encryption strength validated (AES-256)
- [ ] Documentation complete

---

## Risk Mitigation

### Risk 1: Performance Overhead >5%

**Probability**: Medium (30% - from PM risk assessment)
**Mitigation**:
- Early testing Day 3 (detect issues quickly)
- Query optimization (indexes on non-encrypted columns)
- Caching strategies (decrypt once, cache in app layer)
- Fallback: TDE evaluation (Day 4 if needed)

### Risk 2: Integration Issues with RLS

**Probability**: Low (15%)
**Mitigation**:
- Test RLS + Encryption early (Day 3 morning)
- Marcus available for troubleshooting
- Sprint 1 RLS implementation well-tested (baseline confidence)

---

## References

- **Encryption Strategy**: `docs/encryption-strategy.md` (Marcus)
- **Encryption Functions**: `database/scripts/06_encryption_functions.sql` (Marcus)
- **Key Management**: `database/config/key-management-config.sh` (Raj)
- **Encryption Deep Dive**: `meetings/sprint-2-day-1-encryption-architecture-deep-dive.md`
- **User Story**: US-603 (Encryption Testing, 5 story points, Day 3-4)

---

**Document Status**: Framework Design Complete (Day 1)
**Next Update**: Day 3 (after test execution)
**Questions**: Contact Aisha Kamau (QA Engineer) or escalate to Sarah Chen (PM)
