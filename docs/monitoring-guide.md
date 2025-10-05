# Taifabase Production Monitoring Guide

**Version:** 1.0
**Date:** 2025-10-05
**Author:** Raj Patel (DevOps Engineer)
**Sprint:** Phase 1, Sprint 1, Day 3

## Table of Contents

1. [Overview](#overview)
2. [Monitoring Architecture](#monitoring-architecture)
3. [Grafana Dashboards](#grafana-dashboards)
4. [Prometheus Alerts](#prometheus-alerts)
5. [Performance Baselines](#performance-baselines)
6. [Alert Interpretation Guide](#alert-interpretation-guide)
7. [Troubleshooting Procedures](#troubleshooting-procedures)
8. [Escalation Procedures](#escalation-procedures)
9. [Maintenance and Updates](#maintenance-and-updates)

---

## Overview

This guide provides comprehensive documentation for monitoring the Taifabase database infrastructure. The monitoring stack includes:

- **Grafana** - Visualization and dashboards
- **Prometheus** - Metrics collection and alerting
- **PostgreSQL Exporter** - Database metrics
- **PgBouncer Exporter** - Connection pooling metrics
- **Node Exporter** - System resource metrics (future)

### Key Monitoring Goals

1. **Performance** - Track query execution times, RLS overhead, and throughput
2. **Availability** - Ensure database and PgBouncer uptime
3. **Capacity** - Monitor connections, disk space, and resource usage
4. **Security** - Detect unauthorized access and unusual patterns

---

## Monitoring Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Grafana Dashboard                        │
│  (Visualization & Alerting UI - Port 3000)                  │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          │ Queries Metrics
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Prometheus Server                         │
│  (Metrics Storage & Alert Manager - Port 9090)              │
└───────────┬─────────────┬─────────────┬─────────────────────┘
            │             │             │
            │             │             │ Scrapes Metrics
            ▼             ▼             ▼
    ┌───────────┐ ┌──────────────┐ ┌──────────────┐
    │ Postgres  │ │  PgBouncer   │ │     Node     │
    │ Exporter  │ │   Exporter   │ │   Exporter   │
    │ (9187)    │ │   (9127)     │ │   (9100)     │
    └─────┬─────┘ └──────┬───────┘ └──────┬───────┘
          │              │                 │
          │              │                 │ Monitors
          ▼              ▼                 ▼
    ┌──────────┐  ┌──────────┐     ┌──────────┐
    │PostgreSQL│  │PgBouncer │     │  System  │
    │  (5432)  │  │  (6432)  │     │Resources │
    └──────────┘  └──────────┘     └──────────┘
```

### Components

1. **PostgreSQL (Port 5432)** - Primary database
2. **PgBouncer (Port 6432)** - Connection pooler
3. **Prometheus (Port 9090)** - Metrics collection and storage
4. **Grafana (Port 3000)** - Visualization and dashboards
5. **Exporters** - Metric collection agents

---

## Grafana Dashboards

### Accessing Grafana

1. **URL:** `http://localhost:3000` (development) or `https://grafana.taifabase.com` (production)
2. **Default Credentials:**
   - Username: `admin`
   - Password: `admin` (change on first login)
3. **Navigation:** Dashboards → Browse → Select dashboard

### Dashboard 1: Taifabase Overview

**File:** `database/config/grafana/dashboards/taifabase-overview.json`
**UID:** `taifabase-overview`

#### Sections

1. **Database Performance Overview**
   - Active Connections (gauge) - Real-time connection count
   - Transaction Rate (time series) - Commits and rollbacks per second
   - Database Uptime (stat) - Time since last restart
   - SSL Connections % (gauge) - Percentage of encrypted connections

2. **Query Performance & RLS**
   - Query Execution Time Percentiles (P50, P95, P99)
   - RLS Overhead Factor (gauge) - Target: 1.3x
   - Slow Queries Count - Queries taking >100ms

3. **PgBouncer Connection Pooling**
   - Pool Connections (time series) - Client and server connections
   - Pool Utilization % (gauge) - Server pool usage
   - Transaction Throughput (time series)

4. **Resource Usage**
   - CPU Usage (time series) - Per service
   - Memory Usage (time series) - Per service
   - Disk I/O (time series) - Blocks read/hit

5. **Security Metrics**
   - Failed Auth Attempts (bar chart)
   - Audit Log Volume (stat)
   - Unusual Patterns (time series) - Deadlocks, temp files

#### Key Metrics to Watch

- **Active Connections** - Should stay below 80 (warning), 95 (critical)
- **RLS Overhead Factor** - Should be ≤1.3x (Day 2 achievement)
- **Query P95** - Should be <10ms for most queries
- **Pool Utilization** - Should stay below 80%
- **SSL Connections** - Should be 100% in production

### Dashboard 2: PgBouncer Details

**File:** `database/config/grafana/dashboards/pgbouncer-details.json`
**UID:** `taifabase-pgbouncer-details`

#### Sections

1. **Connection Pool Health**
   - Active Client Connections (stat)
   - Waiting Clients (stat) - Warning if >10
   - Active Server Connections (gauge)
   - Idle Server Connections (stat)

2. **Connection Pool Metrics Over Time**
   - Client Connections (stacked time series)
   - Server Connections Lifecycle (stacked time series)

3. **Transaction Processing**
   - Transaction Throughput (time series)
   - Query Duration (time series) - Average query and transaction time

4. **Wait Times & Performance**
   - Client Wait Time (time series) - Should be <5ms
   - Pool Mode (stat) - Should show "Transaction"
   - Max Client Connections (stat) - Configuration value

5. **Error Rates & Issues**
   - Connection Errors (bar chart)
   - Network Throughput (time series)

#### Key Metrics to Watch

- **Waiting Clients** - Should be 0 under normal load
- **Client Wait Time** - Should be <5ms average
- **Pool Utilization** - Should have headroom (idle connections available)
- **Connection Errors** - Should be 0

---

## Prometheus Alerts

### Alert File Location

`database/config/prometheus/alerts/database-alerts.yml`

### Alert Severity Levels

- **Critical** - Immediate action required, potential service impact
- **Warning** - Should be investigated, may become critical
- **Info** - Informational, no immediate action needed

### Alert Groups

#### 1. Database Performance & Capacity

| Alert Name | Severity | Threshold | Duration | Description |
|------------|----------|-----------|----------|-------------|
| HighDatabaseConnections | Warning | >80 connections | 5m | High connection count |
| CriticalDatabaseConnections | Critical | >95 connections | 2m | Near max connections |
| HighSlowQueryRate | Warning | >10 queries/sec >100ms | 10m | Performance degradation |
| DatabaseDeadlocks | Warning | >0 deadlocks | 1m | Lock contention |
| HighTransactionRollbackRate | Warning | >10% rollback rate | 5m | Application errors |

#### 2. PgBouncer Alerts

| Alert Name | Severity | Threshold | Duration | Description |
|------------|----------|-----------|----------|-------------|
| PgBouncerPoolHighUtilization | Warning | >80% pool usage | 5m | Pool nearing capacity |
| PgBouncerPoolSaturated | Critical | >90% pool usage | 2m | Pool saturated |
| PgBouncerHighClientWaitTime | Warning | >5ms wait time | 3m | Clients waiting |
| PgBouncerClientsWaiting | Warning | >10 waiting | 2m | Queue building up |
| PgBouncerConnectionErrors | Critical | >5 errors/5min | 1m | Connection failures |

#### 3. RLS Performance

| Alert Name | Severity | Threshold | Duration | Description |
|------------|----------|-----------|----------|-------------|
| RLSPerformanceDegraded | Warning | Low index scan rate | 10m | RLS policy inefficiency |
| RLSOverheadHigh | Warning | >2.0x overhead | 15m | Exceeds 1.3x target |

#### 4. Security Alerts

| Alert Name | Severity | Threshold | Duration | Description |
|------------|----------|-----------|----------|-------------|
| UnencryptedConnections | Critical | >0 unencrypted | 1m | SSL not enforced |
| FailedAuthenticationSpike | Warning | >10 failures/5min | 2m | Potential attack |
| UnusualDataAccessPattern | Warning | High temp file rate | 5m | Suspicious activity |

#### 5. Resource Utilization

| Alert Name | Severity | Threshold | Duration | Description |
|------------|----------|-----------|----------|-------------|
| LowDiskSpace | Warning | <20% free | 5m | Disk space running low |
| CriticalDiskSpace | Critical | <10% free | 2m | Immediate action needed |
| HighDatabaseCPU | Warning | >80% CPU | 10m | CPU saturation |
| HighDatabaseMemory | Warning | >90% memory | 5m | Memory pressure |
| LowCacheHitRatio | Warning | <90% cache hit | 10m | Poor cache performance |

#### 6. Availability Alerts

| Alert Name | Severity | Threshold | Duration | Description |
|------------|----------|-----------|----------|-------------|
| DatabaseDown | Critical | Exporter unreachable | 1m | PostgreSQL down |
| PgBouncerDown | Critical | Exporter unreachable | 1m | PgBouncer down |
| ReplicationLag | Warning | >10 seconds lag | 5m | Replica behind primary |

---

## Performance Baselines

### Baseline File Location

`database/performance-baselines/day-3-baseline.json`

### Established Baselines (Day 3)

| Metric | Baseline | Target | Status |
|--------|----------|--------|--------|
| Simple SELECT | 1.4ms | <2ms | ✅ Pass |
| COUNT with RLS | 3.7ms | <5ms | ✅ Pass |
| JOIN Query | 8.2ms | <10ms | ✅ Pass |
| Aggregation | 5.8ms | <10ms | ✅ Pass |
| Connection Time | 45ms | <50ms | ✅ Pass |
| PgBouncer Overhead | 2ms | <5ms | ✅ Pass |
| SSL Handshake | 12ms | <20ms | ✅ Pass |
| **RLS Overhead Factor** | **1.3x** | **1.3x** | **✅ Achieved (Day 2)** |

### Day 2 Achievement

- **Before Optimization:** 84x RLS overhead
- **After Optimization:** 1.3x RLS overhead
- **Improvement:** 98.5% reduction in overhead

### Regression Threshold

**Alert if performance degrades >10% from baseline values**

### Running Baseline Tests

```bash
# Navigate to scripts directory
cd database/testing/scripts

# Run baseline establishment script
./establish_performance_baseline.sh

# Output will be written to: database/performance-baselines/day-3-baseline.json
```

### Baseline Test Methodology

- **Iterations per test:** 10-20 runs
- **Warmup queries:** 5 queries before measurement
- **Tenant ID used:** `11111111-1111-1111-1111-111111111111`
- **Measurement:** Average of all iterations

---

## Alert Interpretation Guide

### How to Respond to Alerts

#### HighDatabaseConnections (Warning)

**Symptoms:**
- Active connections > 80
- Dashboard shows increasing connection trend

**Immediate Actions:**
1. Check Grafana dashboard for connection breakdown
2. Review active queries: `SELECT * FROM pg_stat_activity;`
3. Identify long-running queries
4. Check for connection leaks in application code

**Resolution:**
- Kill idle connections if necessary
- Optimize connection pooling settings
- Review application connection management
- Consider scaling if legitimate load increase

#### PgBouncerPoolSaturated (Critical)

**Symptoms:**
- Pool utilization > 90%
- Clients waiting for connections
- Increased query latency

**Immediate Actions:**
1. Increase `default_pool_size` in `pgbouncer.ini`
2. Restart PgBouncer: `docker-compose restart pgbouncer`
3. Review slow queries blocking connections
4. Check PostgreSQL max_connections setting

**Resolution:**
- Optimize query performance
- Increase pool size permanently
- Review connection distribution across pools
- Consider read replicas for read-heavy workloads

#### UnencryptedConnections (Critical)

**Symptoms:**
- Connections without SSL/TLS detected
- Security compliance violation

**Immediate Actions:**
1. Identify source of unencrypted connections
2. Review connection strings in application code
3. Check PostgreSQL SSL configuration
4. Block non-SSL connections if possible

**Resolution:**
- Enforce SSL in `postgresql.conf`: `ssl = on`
- Set `sslmode=require` in all connection strings
- Configure firewall to block non-SSL ports
- Update application deployment configurations

#### RLSOverheadHigh (Warning)

**Symptoms:**
- RLS overhead factor > 2.0x (target: 1.3x)
- Query performance degraded

**Immediate Actions:**
1. Review RLS policy efficiency
2. Check for missing indexes on tenant_id
3. Analyze query plans with EXPLAIN
4. Compare with Day 2 optimization achievements

**Resolution:**
- Add composite indexes if needed
- Simplify RLS policies
- Review session variable usage
- Consider policy design improvements

#### LowDiskSpace (Warning/Critical)

**Symptoms:**
- Disk space < 20% (warning) or < 10% (critical)
- Potential database write failures

**Immediate Actions:**
1. Check disk usage: `df -h`
2. Identify large files: `du -sh /var/lib/postgresql/data/*`
3. Review WAL file accumulation
4. Clean up old backups

**Resolution:**
- Expand disk volume
- Adjust WAL archiving settings
- Implement backup rotation policy
- Monitor disk growth trends

---

## Troubleshooting Procedures

### Procedure 1: High Query Latency

**Diagnosis:**
1. Check Grafana: Query Execution Time panel
2. Review slow queries in PostgreSQL:
   ```sql
   SELECT query, mean_exec_time, calls
   FROM pg_stat_statements
   WHERE mean_exec_time > 100
   ORDER BY mean_exec_time DESC
   LIMIT 10;
   ```
3. Check for lock contention:
   ```sql
   SELECT * FROM pg_locks WHERE NOT granted;
   ```

**Resolution:**
- Optimize queries with missing indexes
- Review query plans with EXPLAIN ANALYZE
- Kill blocking queries if necessary
- Consider query caching

### Procedure 2: Connection Pool Exhaustion

**Diagnosis:**
1. Check PgBouncer stats:
   ```sql
   SHOW POOLS;
   SHOW CLIENTS;
   SHOW SERVERS;
   ```
2. Review waiting clients in Grafana
3. Check PostgreSQL connection count:
   ```sql
   SELECT count(*) FROM pg_stat_activity;
   ```

**Resolution:**
- Increase PgBouncer pool size
- Optimize query performance
- Fix connection leaks in application
- Review connection timeout settings

### Procedure 3: SSL/TLS Configuration Issues

**Diagnosis:**
1. Check PostgreSQL SSL status:
   ```sql
   SELECT * FROM pg_stat_ssl;
   ```
2. Review `postgresql.conf`: `ssl = on`
3. Verify certificate files exist and are readable
4. Check PgBouncer SSL configuration

**Resolution:**
- Enable SSL in PostgreSQL configuration
- Ensure SSL certificates are valid
- Update connection strings to require SSL
- Restart services after configuration changes

### Procedure 4: RLS Performance Degradation

**Diagnosis:**
1. Compare current performance to baseline
2. Run performance baseline script
3. Review RLS policies:
   ```sql
   SELECT * FROM pg_policies WHERE tablename = 'products';
   ```
4. Check index usage:
   ```sql
   SELECT * FROM pg_stat_user_indexes WHERE relname = 'products';
   ```

**Resolution:**
- Verify composite indexes exist
- Review Day 2 optimization achievements
- Simplify RLS policies if possible
- Update statistics: `ANALYZE products;`

---

## Escalation Procedures

### Severity Levels and Response Times

| Severity | Response Time | Escalation Path | Examples |
|----------|--------------|-----------------|----------|
| Critical | Immediate (5min) | On-call → Manager → CTO | Database down, data loss risk |
| Warning | 30 minutes | Team lead → On-call | High connections, performance degradation |
| Info | Next business day | Log and review | Routine metrics, trends |

### Escalation Path

1. **Level 1: DevOps Engineer (On-call)**
   - Initial response and diagnosis
   - Standard troubleshooting procedures
   - Access to all monitoring tools

2. **Level 2: Database Administrator / Backend Engineer**
   - Complex query optimization
   - Database configuration changes
   - RLS policy modifications

3. **Level 3: Team Lead / Engineering Manager**
   - Resource allocation decisions
   - Architecture changes
   - Incident coordination

4. **Level 4: CTO / Security Engineer**
   - Security incidents
   - Major outages
   - Compliance violations

### Communication Channels

- **Slack:** `#taifabase-alerts` (automated alerts)
- **PagerDuty:** Critical alerts and on-call rotation
- **Email:** Weekly summary reports
- **Incident Log:** Document all critical incidents

### Post-Incident Procedures

1. **Immediate:** Resolve the incident and restore service
2. **Short-term (24h):** Document incident timeline and actions taken
3. **Medium-term (1 week):** Conduct post-mortem meeting
4. **Long-term:** Implement preventive measures and update runbooks

---

## Maintenance and Updates

### Regular Maintenance Tasks

#### Daily
- Review Grafana dashboards for anomalies
- Check alert status in Prometheus
- Verify backup completion

#### Weekly
- Review performance trends
- Run baseline performance tests
- Update alert thresholds if needed
- Review slow query logs

#### Monthly
- Update dashboard configurations
- Review and optimize alert rules
- Conduct capacity planning review
- Update monitoring documentation

### Updating Dashboards

1. Edit JSON file in `database/config/grafana/dashboards/`
2. Test changes in Grafana UI
3. Export updated JSON from Grafana
4. Commit changes to git repository
5. Deploy via docker-compose restart

### Updating Alerts

1. Edit `database/config/prometheus/alerts/database-alerts.yml`
2. Validate syntax: `promtool check rules database-alerts.yml`
3. Update Prometheus configuration
4. Reload Prometheus: `docker-compose exec prometheus kill -HUP 1`
5. Verify alerts in Prometheus UI

### Baseline Updates

Run baseline tests after:
- Major performance optimizations
- Database version upgrades
- Configuration changes
- Hardware/infrastructure changes

Store historical baselines for trend analysis.

---

## Appendix

### Useful Commands

#### PostgreSQL
```sql
-- Active connections
SELECT count(*) FROM pg_stat_activity;

-- Current queries
SELECT pid, usename, query, state FROM pg_stat_activity WHERE state != 'idle';

-- Kill a query
SELECT pg_terminate_backend(pid);

-- RLS policies
SELECT * FROM pg_policies;

-- Index usage
SELECT * FROM pg_stat_user_indexes;
```

#### PgBouncer
```sql
-- Pool status
SHOW POOLS;

-- Client connections
SHOW CLIENTS;

-- Server connections
SHOW SERVERS;

-- Statistics
SHOW STATS;

-- Configuration
SHOW CONFIG;
```

#### Docker
```bash
# View logs
docker-compose logs -f postgres
docker-compose logs -f pgbouncer
docker-compose logs -f prometheus
docker-compose logs -f grafana

# Restart services
docker-compose restart pgbouncer
docker-compose restart prometheus

# Check service health
docker-compose ps
```

### Metric Reference

#### PostgreSQL Exporter Metrics
- `pg_stat_database_numbackends` - Active connections
- `pg_stat_database_xact_commit` - Transaction commits
- `pg_stat_database_xact_rollback` - Transaction rollbacks
- `pg_stat_database_blks_read` - Disk blocks read
- `pg_stat_database_blks_hit` - Cache hits
- `pg_stat_statements_mean_exec_time` - Average query time

#### PgBouncer Exporter Metrics
- `pgbouncer_pools_client_active` - Active client connections
- `pgbouncer_pools_client_waiting` - Waiting clients
- `pgbouncer_pools_server_active` - Active server connections
- `pgbouncer_pools_server_idle` - Idle server connections
- `pgbouncer_stats_avg_wait_time` - Average client wait time
- `pgbouncer_stats_queries_total` - Total queries processed

### Resources

- **Grafana Documentation:** https://grafana.com/docs/
- **Prometheus Documentation:** https://prometheus.io/docs/
- **PostgreSQL Monitoring:** https://www.postgresql.org/docs/current/monitoring.html
- **PgBouncer Documentation:** https://www.pgbouncer.org/usage.html

---

**Document History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-05 | Raj Patel | Initial monitoring guide for Day 3 |

**Feedback:**
For questions or updates to this guide, contact the DevOps team or submit a pull request to the documentation repository.
