-- Performance Baseline Testing Script
-- This script establishes performance metrics BEFORE RLS implementation
-- Created by: Marcus Rodriguez - Backend Engineer
-- Date: 2025-10-03
-- Purpose: Measure baseline performance for comparison with RLS-enabled queries

-- Reset statistics for clean baseline
SELECT pg_stat_reset();
SELECT pg_stat_statements_reset();

-- Enable timing for all tests
\timing on

-- Test 1: Simple SELECT by tenant_id (most common query pattern)
\echo '=== TEST 1: Simple SELECT by tenant_id ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, name, value, category 
FROM tenant.sample_data 
WHERE tenant_id = '11111111-1111-1111-1111-111111111111'
LIMIT 100;

-- Test 2: COUNT by tenant_id
\echo '=== TEST 2: COUNT by tenant_id ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT COUNT(*) 
FROM tenant.sample_data 
WHERE tenant_id = '11111111-1111-1111-1111-111111111111';

-- Test 3: Aggregation by tenant and category
\echo '=== TEST 3: Aggregation by tenant and category ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT category, COUNT(*), AVG(value), MAX(value)
FROM tenant.sample_data 
WHERE tenant_id = '22222222-2222-2222-2222-222222222222'
GROUP BY category
ORDER BY COUNT(*) DESC;

-- Test 4: JOIN with tenants table
\echo '=== TEST 4: JOIN with tenants table ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT t.name as tenant_name, sd.category, COUNT(sd.id) as record_count
FROM core.tenants t
JOIN tenant.sample_data sd ON t.id = sd.tenant_id
WHERE t.status = 'active'
GROUP BY t.name, sd.category
ORDER BY record_count DESC
LIMIT 20;

-- Test 5: Complex query with JSONB and array operations
\echo '=== TEST 5: Complex query with JSONB and array operations ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, name, metadata->>'test_field_1' as field1, tags
FROM tenant.sample_data 
WHERE tenant_id = '33333333-3333-3333-3333-333333333333'
  AND metadata->>'test_field_2'::numeric > 50
  AND 'finance' = ANY(tags)
LIMIT 50;

-- Test 6: UPDATE operation
\echo '=== TEST 6: UPDATE operation ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
UPDATE tenant.sample_data 
SET value = value * 1.1, updated_at = CURRENT_TIMESTAMP
WHERE tenant_id = '55555555-5555-5555-5555-555555555555'
  AND category = 'finance';

-- Test 7: INSERT operation
\echo '=== TEST 7: INSERT operation ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
INSERT INTO tenant.sample_data (tenant_id, name, description, value, category, tags, metadata)
SELECT 
    '44444444-4444-4444-4444-444444444444',
    'Baseline Test Record ' || generate_series,
    'Test record for baseline performance measurement',
    random() * 1000,
    'testing',
    ARRAY['baseline', 'performance'],
    jsonb_build_object('test', true, 'baseline_run', true, 'timestamp', CURRENT_TIMESTAMP)
FROM generate_series(1, 100);

-- Test 8: DELETE operation
\echo '=== TEST 8: DELETE operation ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
DELETE FROM tenant.sample_data 
WHERE tenant_id = '44444444-4444-4444-4444-444444444444'
  AND category = 'testing';

-- Test 9: Multi-tenant query (anti-pattern for RLS)
\echo '=== TEST 9: Multi-tenant query (current - will need RLS modification) ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT t.name, COUNT(sd.id) as record_count, AVG(sd.value) as avg_value
FROM core.tenants t
LEFT JOIN tenant.sample_data sd ON t.id = sd.tenant_id
GROUP BY t.id, t.name
ORDER BY record_count DESC;

-- Test 10: Large result set simulation
\echo '=== TEST 10: Large result set simulation ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, name, value, created_at
FROM tenant.sample_data 
WHERE tenant_id = '11111111-1111-1111-1111-111111111111'
  AND created_at >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY created_at DESC
LIMIT 1000;

\timing off

-- Collect performance statistics
\echo '=== PERFORMANCE STATISTICS SUMMARY ==='

-- Table statistics
SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables 
WHERE schemaname IN ('core', 'tenant')
ORDER BY schemaname, tablename;

-- Index usage statistics
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_tup_read,
    idx_tup_fetch,
    idx_scan
FROM pg_stat_user_indexes 
WHERE schemaname IN ('core', 'tenant')
ORDER BY idx_scan DESC;

-- Database-wide statistics
SELECT 
    numbackends,
    xact_commit,
    xact_rollback,
    blks_read,
    blks_hit,
    temp_files,
    temp_bytes,
    deadlocks,
    blk_read_time,
    blk_write_time
FROM pg_stat_database 
WHERE datname = 'taifabase_dev';

-- Current database size
SELECT 
    pg_size_pretty(pg_database_size('taifabase_dev')) as database_size,
    pg_size_pretty(pg_total_relation_size('tenant.sample_data')) as sample_data_size,
    pg_size_pretty(pg_total_relation_size('core.tenants')) as tenants_size,
    pg_size_pretty(pg_total_relation_size('core.users')) as users_size;

\echo '=== BASELINE PERFORMANCE TEST COMPLETED ==='
\echo 'Next step: Implement RLS policies and run comparison tests'