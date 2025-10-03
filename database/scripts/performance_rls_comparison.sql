-- Performance Comparison Testing with RLS Enabled
-- This script measures performance impact of RLS implementation
-- Created by: Marcus Rodriguez - Backend Engineer
-- Date: 2025-10-03
-- Purpose: Compare RLS-enabled performance against baseline metrics

-- Reset statistics for clean comparison
SELECT pg_stat_reset();

-- Set up tenant context for testing
SELECT switch_to_tenant('acme-corp');

-- Enable timing for all tests
\timing on

-- Test 1: Simple SELECT by tenant_id (SAME QUERY AS BASELINE)
\echo '=== RLS TEST 1: Simple SELECT by tenant_id ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, name, value, category 
FROM tenant.sample_data 
WHERE tenant_id = '11111111-1111-1111-1111-111111111111'
LIMIT 100;

-- Test 1b: Simple SELECT without explicit tenant_id (RLS will add it)
\echo '=== RLS TEST 1b: Simple SELECT relying on RLS ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, name, value, category 
FROM tenant.sample_data 
LIMIT 100;

-- Test 2: COUNT by tenant_id
\echo '=== RLS TEST 2: COUNT by tenant_id ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT COUNT(*) 
FROM tenant.sample_data 
WHERE tenant_id = '11111111-1111-1111-1111-111111111111';

-- Test 2b: COUNT relying on RLS
\echo '=== RLS TEST 2b: COUNT relying on RLS ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT COUNT(*) 
FROM tenant.sample_data;

-- Test 3: Aggregation by category
\echo '=== RLS TEST 3: Aggregation by category ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT category, COUNT(*), AVG(value), MAX(value)
FROM tenant.sample_data 
WHERE tenant_id = '11111111-1111-1111-1111-111111111111'
GROUP BY category
ORDER BY COUNT(*) DESC;

-- Test 3b: Aggregation relying on RLS
\echo '=== RLS TEST 3b: Aggregation relying on RLS ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT category, COUNT(*), AVG(value), MAX(value)
FROM tenant.sample_data 
GROUP BY category
ORDER BY COUNT(*) DESC;

-- Test 4: Complex query with JSONB and array operations
\echo '=== RLS TEST 4: Complex query with JSONB and arrays ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, name, metadata->>'test_field_1' as field1, tags
FROM tenant.sample_data 
WHERE metadata->>'test_field_2'::numeric > 50
  AND 'finance' = ANY(tags)
LIMIT 50;

-- Test 5: UPDATE operation
\echo '=== RLS TEST 5: UPDATE operation ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
UPDATE tenant.sample_data 
SET value = value * 1.1, updated_at = CURRENT_TIMESTAMP
WHERE category = 'finance'
  AND id IN (
    SELECT id FROM tenant.sample_data 
    WHERE category = 'finance' 
    LIMIT 10
  );

-- Test 6: INSERT operation
\echo '=== RLS TEST 6: INSERT operation ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
INSERT INTO tenant.sample_data (tenant_id, name, description, value, category, tags, metadata)
SELECT 
    get_current_tenant(),
    'RLS Test Record ' || generate_series,
    'Test record for RLS performance measurement',
    random() * 1000,
    'rls_testing',
    ARRAY['rls', 'performance'],
    jsonb_build_object('test', true, 'rls_run', true, 'timestamp', CURRENT_TIMESTAMP)
FROM generate_series(1, 100);

-- Test 7: DELETE operation
\echo '=== RLS TEST 7: DELETE operation ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
DELETE FROM tenant.sample_data 
WHERE category = 'rls_testing';

-- Test 8: Large result set simulation
\echo '=== RLS TEST 8: Large result set simulation ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, name, value, created_at
FROM tenant.sample_data 
WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY created_at DESC
LIMIT 1000;

\timing off

-- Test cross-tenant access prevention
\echo '=== RLS SECURITY TEST: Cross-tenant access ==='
SELECT switch_to_tenant('techstart-inc');
SELECT COUNT(*) as techstart_records FROM tenant.sample_data;

SELECT switch_to_tenant('acme-corp');
SELECT COUNT(*) as acme_records FROM tenant.sample_data;

-- Admin access test
\echo '=== ADMIN ACCESS TEST ==='

\timing off

-- Collect performance statistics for RLS-enabled queries
\echo '=== RLS PERFORMANCE STATISTICS SUMMARY ==='

-- Table statistics after RLS testing
SELECT 
    schemaname,
    relname as tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples
FROM pg_stat_user_tables 
WHERE schemaname IN ('core', 'tenant')
ORDER BY schemaname, relname;

-- Index usage statistics after RLS
SELECT 
    schemaname,
    relname as tablename,
    indexrelname as indexname,
    idx_tup_read,
    idx_tup_fetch,
    idx_scan
FROM pg_stat_user_indexes 
WHERE schemaname IN ('core', 'tenant')
ORDER BY idx_scan DESC;

-- Current database size after RLS operations
SELECT 
    pg_size_pretty(pg_database_size('taifabase_dev')) as database_size,
    pg_size_pretty(pg_total_relation_size('tenant.sample_data')) as sample_data_size;

\echo '=== RLS PERFORMANCE TESTING COMPLETED ==='
\echo 'Compare these results with baseline metrics to measure RLS impact'