# Encryption Performance Testing Plan

**Document Metadata**
- **Created**: 2025-10-06 (Sprint 2, Day 1)
- **Owner**: Aisha Kamau (QA Engineer)
- **Execution**: Day 3 Afternoon (1:00-5:00 PM)
- **Target**: <5% encryption overhead (CRITICAL requirement from 2:00 PM encryption deep dive)

---

## Objective

Validate that encryption at rest (Marcus's US-601) introduces <5% performance overhead compared to Sprint 1 baselines (no encryption).

**Critical Requirement**: <5% overhead (hard requirement from encryption architecture deep dive)
**Acceptable**: <10% (with strong security justification)
**Unacceptable**: >10% (triggers TDE evaluation on Day 4)

---

## Testing Methodology

### Step 1: Baseline Measurement (Sprint 1 - No Encryption)

**Query Types**:
1. Simple SELECT (single row by primary key)
2. SELECT with RLS filtering (tenant-scoped query)
3. Aggregation (COUNT, no encrypted columns)

**Execution**:
- Run each query 100 times
- Record average execution time
- Document in baseline report

---

### Step 2: Encrypted Measurement (Sprint 2 - With Encryption)

**Query Types**:
1. Simple SELECT with decryption
2. SELECT with RLS filtering + decryption
3. Aggregation with decryption

**Execution**:
- Run each query 100 times
- Record average execution time
- Calculate overhead vs baseline

---

### Step 3: Overhead Calculation

```
Overhead (%) = (Encrypted Time - Baseline Time) / Baseline Time * 100%

Example:
Baseline: 0.5ms
Encrypted: 0.52ms
Overhead: (0.52 - 0.5) / 0.5 * 100% = 4%  ✅ PASS
```

---

## Test Queries

### Query 1: Simple SELECT

**Baseline** (No Encryption):
```sql
EXPLAIN ANALYZE
SELECT email FROM core.users WHERE user_id = 'test-uuid-1';
```

**Encrypted** (With Decryption):
```sql
EXPLAIN ANALYZE
SELECT decrypt_sensitive_data(email_encrypted) AS email
FROM core.users
WHERE user_id = 'test-uuid-1';
```

**Target**: <0.525ms (5% overhead on 0.5ms baseline)

---

### Query 2: SELECT with RLS Filtering

**Baseline** (No Encryption):
```sql
EXPLAIN ANALYZE
SELECT * FROM tenant.sample_data
WHERE tenant_id = 'alpha-uuid' LIMIT 100;
```

**Encrypted** (No Decryption - not accessing encrypted columns):
```sql
EXPLAIN ANALYZE
SELECT * FROM tenant.sample_data
WHERE tenant_id = 'alpha-uuid' LIMIT 100;
```

**Target**: ~2ms (no overhead, not decrypting)

---

### Query 3: Aggregation

**Baseline** (No Encryption):
```sql
EXPLAIN ANALYZE
SELECT COUNT(*) FROM core.users WHERE created_at > '2025-01-01';
```

**Encrypted** (No Decryption):
```sql
EXPLAIN ANALYZE
SELECT COUNT(*) FROM core.users WHERE created_at > '2025-01-01';
```

**Target**: ~1ms (no overhead, not decrypting)

---

## Load Testing (1000+ Concurrent Users)

**Tool**: k6
**Duration**: 5 minutes
**Virtual Users**: 1000

**Test Script**: `database/testing/load-tests/encryption-load-test.js`

**Success Criteria**:
- Average response time: <100ms
- P95 response time: <150ms
- Error rate: 0%
- Database CPU: <80%
- Database Memory: <80%

---

## Performance Targets

| Metric | Target | Acceptable | Unacceptable | Action |
|--------|--------|------------|--------------|--------|
| **Encryption Overhead** | <5% | <10% | >10% | Evaluate TDE (Day 4) |
| **Simple SELECT** | <0.525ms | <0.55ms | >0.55ms | Query optimization |
| **Load Test P95** | <100ms | <150ms | >150ms | Infrastructure scaling |
| **DB CPU** | <70% | <80% | >80% | Resource optimization |

---

## Day 3 Afternoon Schedule

**1:00-2:00 PM**: Baseline Measurements
- Execute baseline queries (100 iterations each)
- Record average times
- Document Sprint 1 performance

**2:00-3:30 PM**: Encrypted Performance Testing
- Execute encrypted queries (100 iterations each)
- Record average times
- Calculate overhead percentages
- **CRITICAL**: If overhead >5%, escalate to Marcus/IC immediately

**3:30-4:30 PM**: Load Testing
- Run k6 load test (1000 users, 5 minutes)
- Monitor database metrics (CPU, memory, connections)
- Record response times (avg, P95, P99)

**4:30-5:00 PM**: Performance Report
- Calculate final overhead percentages
- Create performance report (`database/testing/reports/encryption-performance-report.md`)
- Make Go/No-Go recommendation

---

## Escalation Plan

### If Overhead >5% but <10%:
1. Document overhead percentage
2. Consult with Marcus on optimization opportunities
3. Review query plans (EXPLAIN ANALYZE)
4. Check for missing indexes
5. Make recommendation (proceed vs optimize)

### If Overhead >10%:
1. **IMMEDIATE ESCALATION** to IC and Marcus
2. Document performance issue
3. Evaluate alternatives:
   - Query optimization (indexes, query rewrite)
   - Caching strategies (decrypt once, cache in app)
   - Transparent Data Encryption (TDE) evaluation (Day 4)
4. Make recommendation on Day 4 action plan

---

## Performance Report Template

**File**: `database/testing/reports/encryption-performance-report.md`

```markdown
# Encryption Performance Test Report

**Date**: 2025-10-08 (Day 3)
**Tester**: Aisha Kamau (QA Engineer)
**Target**: <5% overhead

## Test Results

| Query Type | Baseline (ms) | Encrypted (ms) | Overhead (%) | Status |
|------------|---------------|----------------|--------------|--------|
| Simple SELECT | ___ | ___ | ___ | ✅ PASS / ❌ FAIL |
| SELECT + RLS | ___ | ___ | ___ | ✅ PASS / ❌ FAIL |
| Aggregation | ___ | ___ | ___ | ✅ PASS / ❌ FAIL |

## Load Testing Results

- Virtual Users: 1000
- Duration: 5 minutes
- Average Response Time: ___ ms
- P95 Response Time: ___ ms
- P99 Response Time: ___ ms
- Error Rate: ___%
- Database CPU: ___%
- Database Memory: ___%

## Recommendation

[✅ APPROVE / ⚠️ OPTIMIZE / ❌ REDESIGN]

Justification: ___
```

---

**Document Status**: Plan Complete (Day 1)
**Execution**: Day 3 Afternoon
**Report Due**: Day 3 End of Day
