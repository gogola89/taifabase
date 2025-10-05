# Load Testing Guide - Taifabase

**Author**: Aisha Kamau - QA Engineer
**Date**: 2025-10-05 (Day 3)
**Version**: 1.0

## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Load Testing Framework](#load-testing-framework)
4. [Test Scenarios](#test-scenarios)
5. [Running Load Tests](#running-load-tests)
6. [Interpreting Results](#interpreting-results)
7. [Performance Targets](#performance-targets)
8. [CI/CD Integration](#cicd-integration)
9. [Troubleshooting](#troubleshooting)

## Introduction

This guide provides comprehensive instructions for executing load tests on the Taifabase database infrastructure. Load testing validates that the system can handle production-level concurrent user loads while maintaining performance and security standards.

### Purpose

- **Performance Validation**: Verify the system can support 1000+ concurrent users
- **Scalability Testing**: Identify bottlenecks and resource constraints
- **Security Validation**: Ensure tenant isolation under load (zero data leakage)
- **RLS Performance**: Validate Row-Level Security overhead stays within acceptable limits
- **PgBouncer Validation**: Test connection pooling under extreme load

### Test Suite Overview

| Test Script | Purpose | Target Load | Duration |
|-------------|---------|-------------|----------|
| `rls-load-test.js` | RLS performance validation | 1000 users | ~15 min |
| `pgbouncer-stress-test.js` | Connection pool stress | 1500 users | ~8 min |
| `rls-multi-tenant-load.js` | Multi-tenant isolation | 1000 users (5 tenants) | ~10 min |

## Prerequisites

### System Requirements

- Docker Compose environment running
- PostgreSQL 15.8 with test data loaded
- PgBouncer configured (transaction pooling mode)
- At least 4GB RAM available
- Network connectivity to database services

### Software Requirements

1. **k6 Load Testing Tool** (v0.47.0 or later)
2. **Python 3.11+** (for result parsing)
3. **jq** (optional, for JSON parsing)

### Installing k6

#### Linux (Ubuntu/Debian)
```bash
wget https://github.com/grafana/k6/releases/download/v0.47.0/k6-v0.47.0-linux-amd64.tar.gz
tar -xzf k6-v0.47.0-linux-amd64.tar.gz
sudo mv k6 /usr/local/bin/
k6 version
```

#### macOS (Homebrew)
```bash
brew install k6
k6 version
```

#### Docker Container (devtools)
```bash
docker exec -it taifabase_devtools sh
wget https://github.com/grafana/k6/releases/download/v0.47.0/k6-v0.47.0-linux-amd64.tar.gz
tar -xzf k6-v0.47.0-linux-amd64.tar.gz
mv k6 /usr/local/bin/
k6 version
```

### Environment Setup

Ensure the following services are running:

```bash
# Check Docker Compose services
docker-compose ps

# Verify PostgreSQL
docker exec -it taifabase_postgres psql -U taifabase_user -d taifabase_dev -c "SELECT version();"

# Verify PgBouncer
docker exec -it taifabase_pgbouncer psql -h localhost -p 5432 -U taifabase_user -d taifabase_dev -c "SHOW POOLS;"
```

## Load Testing Framework

### Framework Architecture

The k6-based load testing framework provides:

- **Custom Metrics**: RLS overhead, tenant isolation, connection wait times
- **Threshold Validation**: Automated pass/fail criteria
- **Result Aggregation**: JSON output for analysis and reporting
- **Detailed Summaries**: Human-readable performance reports

### Test Script Structure

Each test script follows this pattern:

```javascript
// 1. Imports and metrics definition
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const customMetric = new Trend('metric_name');

// 2. Test configuration (stages, thresholds)
export const options = {
  stages: [...],
  thresholds: {...},
};

// 3. Main test scenario
export default function () {
  // Test logic
}

// 4. Setup/teardown (optional)
export function setup() { ... }
export function teardown() { ... }

// 5. Custom summary handler
export function handleSummary(data) { ... }
```

## Test Scenarios

### 1. RLS Load Test (`rls-load-test.js`)

**Purpose**: Validate Row-Level Security performance under 1000 concurrent users

**Load Profile**:
```
0 → 100 users (2 min)
100 → 500 users (3 min)
500 → 1000 users (3 min)
1000 users sustained (5 min)
1000 → 0 users (2 min)
```

**Query Mix**:
- 70% Simple SELECT queries
- 15% COUNT queries (RLS optimization target)
- 10% Aggregate queries (GROUP BY)
- 5% Filtered searches

**Key Metrics**:
- `rls_query_duration`: SELECT query latency
- `rls_count_duration`: COUNT query latency (Day 2 optimization)
- `query_errors`: Error count
- `successful_queries`: Success count

**Thresholds**:
- P95 SELECT latency < 100ms
- P95 COUNT latency < 200ms
- Error rate < 1%

### 2. PgBouncer Stress Test (`pgbouncer-stress-test.js`)

**Purpose**: Validate connection pooling under extreme load (1500 users)

**Load Profile**:
```
0 → 200 users (30s)
200 → 500 users (1 min)
500 → 800 users (1 min)
800 → 1200 users (2 min)
1200 → 1500 users (2 min)
1500 → 500 users (1 min)
500 → 0 users (30s)
```

**Transaction Types**:
- 70% Short transactions (1 query, 5-25ms)
- 25% Medium transactions (3 queries, 30-80ms)
- 5% Long transactions (5 queries, 50-150ms)

**Key Metrics**:
- `pgbouncer_connection_wait_time`: Queue wait time
- `pgbouncer_pool_exhaustion`: Pool exhaustion events
- `pgbouncer_connection_reuse`: Connection reuse rate
- `transaction_throughput`: Transactions per second

**Thresholds**:
- P95 connection wait < 50ms
- Pool exhaustion events < 10
- Connection reuse > 80%
- Throughput > 100 tx/sec

### 3. Multi-Tenant Load Test (`rls-multi-tenant-load.js`)

**Purpose**: Validate tenant isolation and RLS performance across 5 tenants

**Load Profile**:
```
1000 concurrent users distributed across 5 tenants (200 per tenant)
0 → 100 users (1 min)
100 → 500 users (2 min)
500 → 1000 users (3 min)
1000 users sustained (3 min)
1000 → 0 users (1 min)
```

**Test Scenarios**:
- Tenant context switching
- Basic RLS queries per tenant
- Cross-tenant access attempts (security validation)
- Complex aggregations
- Large dataset queries

**Key Metrics**:
- `tenant_switch_time`: Tenant context switch duration
- `rls_overhead_ratio`: RLS performance overhead
- `data_leakage_violations`: Cross-tenant data access (MUST be 0)
- `tenant_isolation_success`: Isolation success rate (MUST be 100%)

**Thresholds**:
- Tenant switching < 50ms
- RLS overhead < 2x (Day 2 baseline: 1.3x)
- Data leakage violations == 0 (CRITICAL)
- Tenant isolation == 100%

## Running Load Tests

### Local Execution

#### Basic Test Run

```bash
# Navigate to test directory
cd database/testing/load-tests

# Run RLS load test
k6 run rls-load-test.js

# Run PgBouncer stress test
k6 run pgbouncer-stress-test.js

# Run multi-tenant load test
k6 run rls-multi-tenant-load.js
```

#### Custom Environment Variables

```bash
# Override database connection
DB_NAME=taifabase_prod \
DB_USER=prod_user \
DB_PASSWORD=prod_password \
PGBOUNCER_URL=http://pgbouncer.prod:5433 \
k6 run rls-load-test.js
```

#### Generate JSON Results

```bash
# RLS load test with JSON output
k6 run --out json=rls-results.json rls-load-test.js

# All tests with results
k6 run --out json=rls-results.json rls-load-test.js
k6 run --out json=pgbouncer-results.json pgbouncer-stress-test.js
k6 run --out json=multi-tenant-results.json rls-multi-tenant-load.js
```

#### Custom Load Levels

Modify the `options.stages` in the test script to adjust load:

```javascript
export const options = {
  stages: [
    { duration: '1m', target: 50 },    // Reduced load
    { duration: '2m', target: 100 },
    { duration: '1m', target: 0 },
  ],
};
```

### Container Execution

```bash
# Execute inside devtools container
docker exec -it taifabase_devtools sh

# Run tests from container
cd /workspace/database/testing/load-tests
k6 run rls-load-test.js
```

### Monitoring During Tests

#### Terminal 1: Run Load Test
```bash
k6 run rls-load-test.js
```

#### Terminal 2: Monitor PostgreSQL
```bash
docker exec -it taifabase_postgres psql -U taifabase_user -d taifabase_dev -c "
  SELECT count(*) as active_connections, state
  FROM pg_stat_activity
  WHERE datname = 'taifabase_dev'
  GROUP BY state;
"
```

#### Terminal 3: Monitor PgBouncer
```bash
docker exec -it taifabase_pgbouncer psql -h localhost -p 5432 -U taifabase_user -d pgbouncer -c "SHOW POOLS;"
```

#### Terminal 4: Grafana Dashboard
```bash
# Open Grafana
open http://localhost:3000

# Navigate to: Dashboards → Taifabase Database Performance
# Watch: Connection count, query latency, error rates
```

## Interpreting Results

### Console Output

k6 provides real-time metrics during test execution:

```
running (10m00.0s), 0000/1000 VUs, 45234 complete and 0 interrupted iterations

     ✓ SELECT query successful
     ✓ SELECT latency acceptable
     ✓ COUNT query successful
     ✓ COUNT latency acceptable

     checks.........................: 99.09% ✓ 179208      ✗ 1636
     data_received..................: 45 MB  75 kB/s
     data_sent......................: 23 MB  38 kB/s
     http_req_duration..............: avg=87.32ms min=12.45ms med=76.23ms max=456.78ms p(90)=124.56ms p(95)=168.45ms
     rls_query_duration.............: avg=78.45ms min=20.34ms med=72.11ms max=234.56ms p(90)=102.34ms p(95)=128.45ms
     rls_count_duration.............: avg=142.67ms min=45.23ms med=134.56ms max=398.23ms p(90)=178.45ms p(95)=201.23ms
     iterations.....................: 45234  75.39/s
     vus............................: 1000   min=100      max=1000
```

### Key Metrics to Watch

| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| P95 SELECT latency | <80ms | 80-100ms | >100ms |
| P95 COUNT latency | <150ms | 150-200ms | >200ms |
| Error rate | <0.5% | 0.5-1% | >1% |
| RLS overhead | <1.5x | 1.5-2x | >2x |
| Data leakage | 0 | 0 | >0 (CRITICAL) |

### JSON Results Analysis

```bash
# Parse JSON results
cat rls-results.json | jq '.metrics.rls_query_duration.values'

# Extract P95 latency
cat rls-results.json | jq '.metrics.rls_query_duration.values["p(95)"]'

# Check thresholds
cat rls-results.json | jq '.thresholds'

# Success rate
cat rls-results.json | jq '.metrics.checks.values.rate * 100'
```

### Threshold Validation

Thresholds automatically determine pass/fail:

```
✓ rls_query_duration (p95<100ms) → PASS
✓ rls_count_duration (p95<200ms) → PASS
✓ query_errors (rate<0.01) → PASS
✗ http_req_duration (p95<500ms) → FAIL (567ms)
```

**Pass**: All thresholds met → Test successful
**Fail**: Any threshold violated → Test failed, review performance

### Security Validation

**Multi-Tenant Load Test - Critical Security Metrics**:

```
Data Leakage Violations: 0 ✓
Tenant Isolation Success: 100.00% ✓
```

**CRITICAL**: Any data leakage (count > 0) is a security failure requiring immediate investigation.

## Performance Targets

### Functional Requirements

| Requirement | Target | Measurement |
|-------------|--------|-------------|
| Concurrent Users | 1000+ | Sustained for 5+ minutes |
| Request Success Rate | >99% | Error rate < 1% |
| Tenant Isolation | 100% | Zero data leakage |

### Performance Requirements

| Metric | Target | Notes |
|--------|--------|-------|
| P95 SELECT Latency | <100ms | Simple queries with RLS |
| P95 COUNT Latency | <200ms | Aggregation with RLS |
| P95 HTTP Duration | <500ms | Overall request time |
| RLS Overhead | <2x | vs queries without RLS |

### Connection Pooling (PgBouncer)

| Metric | Target | Notes |
|--------|--------|-------|
| Connection Wait (P95) | <50ms | Queue wait time |
| Pool Exhaustion | <10 events | During extreme load |
| Connection Reuse | >80% | Pooling efficiency |
| Transaction Throughput | >100 tx/sec | Overall throughput |

### Tenant Isolation (Security)

| Metric | Target | Notes |
|--------|--------|-------|
| Data Leakage Violations | 0 | CRITICAL - must be zero |
| Tenant Isolation Rate | 100% | All cross-tenant queries blocked |
| Tenant Switch Time | <50ms | Context switching overhead |

## CI/CD Integration

### Automated Load Testing

Load tests are integrated into the CI/CD pipeline (`.github/workflows/database-tests.yml`).

#### Triggering Load Tests

**Option 1: Add label to Pull Request**
```bash
gh pr edit <PR_NUMBER> --add-label "load-test"
```

**Option 2: Via GitHub UI**
1. Navigate to Pull Request
2. Add label: `load-test`
3. Load tests execute automatically

**Option 3: Manual Workflow Dispatch**
```bash
gh workflow run database-tests.yml
```

### Workflow Configuration

```yaml
load-testing:
  name: Load Testing (1000+ concurrent users)
  runs-on: ubuntu-latest
  needs: database-rls-tests
  if: contains(github.event.pull_request.labels.*.name, 'load-test')
  timeout-minutes: 30
```

**Key Features**:
- Only runs when `load-test` label present (prevents slow CI on every commit)
- Runs after successful RLS tests (`needs: database-rls-tests`)
- 30-minute timeout for comprehensive testing
- Parallel execution of all 3 test scenarios

### Viewing Results in CI/CD

#### GitHub Actions Summary

1. Navigate to: **Actions** → **Your PR** → **Load Testing**
2. View **Job Summary** for high-level metrics
3. Download **Artifacts** for detailed JSON results

#### Artifacts Available

- `load-test-results/rls-load-results.json`
- `load-test-results/pgbouncer-stress-results.json`
- `load-test-results/multi-tenant-load-results.json`

**Retention**: 30 days

#### Pull Request Comment

Load test results are automatically posted as PR comment:

```markdown
## 📊 Load Testing Results

### ✅ RLS Load Test (1000 concurrent users)
- Total Requests: 45,234
- Success Rate: 99.09%
- Status: PASSED

### ✅ PgBouncer Stress Test (1500 concurrent users)
- Total Transactions: 52,847
- Success Rate: 98.00%
- Status: PASSED

### ✅ Multi-Tenant Load Test
- Data Leakage Violations: 0
- Tenant Isolation: 100.00%
- Status: PASSED
- 🔒 Security: Perfect tenant isolation

---
*Load Testing Framework by Aisha Kamau - QA Engineer (Day 3)*
```

## Troubleshooting

### Common Issues

#### 1. k6 Not Found

**Error**: `k6: command not found`

**Solution**:
```bash
# Install k6
wget https://github.com/grafana/k6/releases/download/v0.47.0/k6-v0.47.0-linux-amd64.tar.gz
tar -xzf k6-v0.47.0-linux-amd64.tar.gz
sudo mv k6 /usr/local/bin/
```

#### 2. Database Connection Refused

**Error**: `connection refused` or `timeout`

**Solution**:
```bash
# Verify services running
docker-compose ps

# Check PgBouncer
docker exec -it taifabase_pgbouncer psql -h localhost -p 5432 -U taifabase_user -d taifabase_dev -c "SELECT 1;"

# Restart if needed
docker-compose restart pgbouncer postgres
```

#### 3. Pool Exhaustion Errors

**Error**: High pool exhaustion count or connection timeouts

**Solution**:
```bash
# Increase PgBouncer pool size
# Edit: database/config/pgbouncer/pgbouncer.ini
default_pool_size = 30  # Increase from 25
reserve_pool_size = 10  # Increase from 5

# Restart PgBouncer
docker-compose restart pgbouncer
```

#### 4. High RLS Overhead

**Issue**: RLS overhead exceeds 2x threshold

**Investigation**:
```sql
-- Check query plans with RLS
EXPLAIN ANALYZE SELECT * FROM tenant.sample_data LIMIT 10;

-- Verify indexes on tenant_id
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE tablename = 'sample_data';
```

**Solution**:
- Optimize indexes on `tenant_id` columns
- Review RLS policy complexity
- Consider materialized views for aggregations

#### 5. Test Scripts Fail Validation

**Error**: `k6 inspect` fails or syntax errors

**Solution**:
```bash
# Validate script syntax
k6 inspect database/testing/load-tests/rls-load-test.js

# Check for missing imports
grep "import" database/testing/load-tests/rls-load-test.js
```

#### 6. CI/CD Load Tests Not Running

**Issue**: Load tests don't execute in GitHub Actions

**Checklist**:
- ✓ PR has `load-test` label
- ✓ Base RLS tests passed (`needs: database-rls-tests`)
- ✓ Workflow file updated (`.github/workflows/database-tests.yml`)

### Performance Debugging

#### High Latency Diagnosis

```bash
# 1. Check database performance
docker exec -it taifabase_postgres psql -U taifabase_user -d taifabase_dev -c "
  SELECT query, mean_exec_time, calls
  FROM pg_stat_statements
  ORDER BY mean_exec_time DESC
  LIMIT 10;
"

# 2. Monitor active connections
docker exec -it taifabase_postgres psql -U taifabase_user -d taifabase_dev -c "
  SELECT state, count(*)
  FROM pg_stat_activity
  GROUP BY state;
"

# 3. Check PgBouncer stats
docker exec -it taifabase_pgbouncer psql -h localhost -p 5432 -U taifabase_user -d pgbouncer -c "
  SHOW STATS;
  SHOW POOLS;
"
```

## Best Practices

### When to Run Load Tests

1. **Before Major Releases**: Validate performance before deployment
2. **After Optimization**: Verify improvements (Day 2 RLS optimization)
3. **Infrastructure Changes**: Test after scaling or configuration updates
4. **Weekly Regression**: Scheduled weekly load test for trending

### Test Data Requirements

- **Minimum 100k records** per tenant for realistic queries
- **5+ tenants** for multi-tenant testing
- **Varied data distributions** (categories, values, dates)
- **Realistic JSONB metadata** for index testing

### Load Test Hygiene

1. **Run on isolated environment** (not production)
2. **Monitor system resources** during tests
3. **Clean up test data** after completion
4. **Archive results** for trend analysis
5. **Document anomalies** and unexpected behavior

### Continuous Improvement

1. **Baseline metrics** from Day 2 (RLS overhead: 1.3x)
2. **Track regression** on every deployment
3. **Alert on threshold violations**
4. **Optimize bottlenecks** iteratively
5. **Update thresholds** as performance improves

---

## Appendix

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_URL` | `http://localhost:5433` | PgBouncer connection URL |
| `DB_NAME` | `taifabase_dev` | Database name |
| `DB_USER` | `taifabase_user` | Database user |
| `DB_PASSWORD` | `taifabase_dev_password` | Database password |

### Related Documentation

- **Day 2 Performance Baseline**: `/database/scripts/performance_baseline.sql`
- **RLS Implementation**: `/database/scripts/03_rls_implementation.sql`
- **CI/CD Pipeline**: `/.github/workflows/database-tests.yml`
- **Test Results**: `/database/testing/load-tests/day-3-load-test-results.md`

### References

- [k6 Documentation](https://k6.io/docs/)
- [PgBouncer Configuration](https://www.pgbouncer.org/config.html)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)
- [Row-Level Security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-05
**Maintained By**: Aisha Kamau - QA Engineer
