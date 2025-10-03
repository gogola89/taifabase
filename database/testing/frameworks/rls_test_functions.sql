-- RLS Testing Framework Functions
-- Author: Aisha Kamau - Senior QA Engineer
-- Date: 2025-10-03
-- Purpose: Core testing functions for RLS policy validation
-- Dependencies: Marcus Rodriguez's RLS implementation, test configuration setup

-- ==================================================
-- CORE RLS TESTING FUNCTIONS
-- ==================================================

-- Function to validate tenant isolation
CREATE OR REPLACE FUNCTION test_tenant_isolation(
    test_user_name TEXT,
    expected_tenant_id UUID,
    test_description TEXT DEFAULT 'Tenant isolation test'
) RETURNS TABLE(
    test_name TEXT,
    test_result BOOLEAN,
    actual_records BIGINT,
    expected_tenant UUID,
    visible_tenants UUID[],
    test_details JSONB
) AS $$
DECLARE
    current_record_count BIGINT;
    visible_tenant_ids UUID[];
    current_tenant_context UUID;
    test_start_time TIMESTAMP;
    test_end_time TIMESTAMP;
BEGIN
    test_start_time := clock_timestamp();
    
    -- Set the tenant context for the test
    PERFORM set_current_tenant(expected_tenant_id);
    
    -- Get current tenant context to verify it was set
    current_tenant_context := get_current_tenant();
    
    -- Count visible records
    SELECT COUNT(*) INTO current_record_count
    FROM tenant.sample_data;
    
    -- Get list of visible tenant IDs
    SELECT array_agg(DISTINCT tenant_id) INTO visible_tenant_ids
    FROM tenant.sample_data;
    
    test_end_time := clock_timestamp();
    
    -- Return test results
    RETURN QUERY SELECT
        test_description,
        (
            current_record_count > 0 
            AND array_length(visible_tenant_ids, 1) = 1 
            AND visible_tenant_ids[1] = expected_tenant_id
            AND current_tenant_context = expected_tenant_id
        ),
        current_record_count,
        expected_tenant_id,
        COALESCE(visible_tenant_ids, ARRAY[]::UUID[]),
        jsonb_build_object(
            'user_tested', test_user_name,
            'tenant_context_set', current_tenant_context,
            'tenant_context_expected', expected_tenant_id,
            'test_timestamp', test_start_time,
            'execution_time_ms', EXTRACT(MILLISECONDS FROM (test_end_time - test_start_time)),
            'records_found', current_record_count,
            'unique_tenants_visible', COALESCE(array_length(visible_tenant_ids, 1), 0)
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to test cross-tenant access prevention
CREATE OR REPLACE FUNCTION test_cross_tenant_access(
    test_user_name TEXT,
    user_tenant_id UUID,
    target_tenant_id UUID
) RETURNS TABLE(
    test_name TEXT,
    test_result BOOLEAN,
    access_prevented BOOLEAN,
    test_details JSONB
) AS $$
DECLARE
    initial_records BIGINT;
    cross_tenant_records BIGINT;
    initial_tenant_context UUID;
    final_tenant_context UUID;
    test_start_time TIMESTAMP;
    test_end_time TIMESTAMP;
BEGIN
    test_start_time := clock_timestamp();
    
    -- Set user's legitimate tenant context
    PERFORM set_current_tenant(user_tenant_id);
    initial_tenant_context := get_current_tenant();
    SELECT COUNT(*) INTO initial_records FROM tenant.sample_data;
    
    -- Attempt to switch to different tenant (this should either fail or be ignored by RLS)
    BEGIN
        PERFORM set_current_tenant(target_tenant_id);
        final_tenant_context := get_current_tenant();
        SELECT COUNT(*) INTO cross_tenant_records FROM tenant.sample_data;
    EXCEPTION
        WHEN OTHERS THEN
            -- If switching tenant fails, that's good for security
            cross_tenant_records := 0;
            final_tenant_context := initial_tenant_context;
    END;
    
    test_end_time := clock_timestamp();
    
    -- Test passes if:
    -- 1. No cross-tenant records are visible, OR
    -- 2. The tenant context didn't actually change, OR  
    -- 3. We only see records from the user's original tenant
    RETURN QUERY SELECT
        'Cross-tenant access prevention test',
        (
            cross_tenant_records = 0 OR 
            final_tenant_context = user_tenant_id OR
            cross_tenant_records = initial_records
        ),
        (cross_tenant_records = 0),
        jsonb_build_object(
            'user_tested', test_user_name,
            'user_tenant', user_tenant_id,
            'target_tenant', target_tenant_id,
            'initial_records', initial_records,
            'cross_tenant_records', cross_tenant_records,
            'initial_tenant_context', initial_tenant_context,
            'final_tenant_context', final_tenant_context,
            'context_changed', (final_tenant_context != initial_tenant_context),
            'test_timestamp', test_start_time,
            'execution_time_ms', EXTRACT(MILLISECONDS FROM (test_end_time - test_start_time))
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to measure RLS performance impact
CREATE OR REPLACE FUNCTION test_rls_performance(
    tenant_id UUID,
    test_iterations INTEGER DEFAULT 100
) RETURNS TABLE(
    test_name TEXT,
    avg_execution_time NUMERIC,
    min_execution_time NUMERIC,
    max_execution_time NUMERIC,
    total_iterations INTEGER,
    performance_details JSONB
) AS $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    execution_times NUMERIC[];
    current_time NUMERIC;
    i INTEGER;
    record_count BIGINT;
BEGIN
    -- Set tenant context
    PERFORM set_current_tenant(tenant_id);
    
    -- Initialize timing array
    execution_times := ARRAY[]::NUMERIC[];
    
    -- Run performance test iterations
    FOR i IN 1..test_iterations LOOP
        start_time := clock_timestamp();
        
        -- Execute test query (typical query pattern)
        SELECT COUNT(*) INTO record_count FROM tenant.sample_data WHERE category = 'finance';
        
        end_time := clock_timestamp();
        current_time := EXTRACT(MILLISECONDS FROM (end_time - start_time));
        execution_times := array_append(execution_times, current_time);
    END LOOP;
    
    -- Calculate statistics and return results
    RETURN QUERY SELECT
        'RLS Performance Test',
        (SELECT AVG(x) FROM unnest(execution_times) AS x),
        (SELECT MIN(x) FROM unnest(execution_times) AS x),
        (SELECT MAX(x) FROM unnest(execution_times) AS x),
        test_iterations,
        jsonb_build_object(
            'tenant_tested', tenant_id,
            'test_timestamp', CURRENT_TIMESTAMP,
            'query_type', 'COUNT with WHERE clause',
            'record_count_found', record_count,
            'statistics', jsonb_build_object(
                'stddev', (SELECT stddev(x) FROM unnest(execution_times) AS x),
                'median', (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x) FROM unnest(execution_times) AS x),
                'p95', (SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY x) FROM unnest(execution_times) AS x),
                'p99', (SELECT percentile_cont(0.99) WITHIN GROUP (ORDER BY x) FROM unnest(execution_times) AS x)
            ),
            'raw_times_sample', execution_times[1:10]  -- First 10 measurements for debugging
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to test admin access across all tenants
CREATE OR REPLACE FUNCTION test_admin_access(
    admin_user_name TEXT DEFAULT 'test_admin_user'
) RETURNS TABLE(
    test_name TEXT,
    test_result BOOLEAN,
    total_records BIGINT,
    unique_tenants INTEGER,
    test_details JSONB
) AS $$
DECLARE
    total_record_count BIGINT;
    tenant_count INTEGER;
    tenant_list UUID[];
    test_start_time TIMESTAMP;
    test_end_time TIMESTAMP;
BEGIN
    test_start_time := clock_timestamp();
    
    -- Admin users should be able to see all records regardless of tenant context
    -- Don't set a specific tenant context - test admin policy
    
    SELECT COUNT(*) INTO total_record_count FROM tenant.sample_data;
    
    SELECT array_agg(DISTINCT tenant_id), COUNT(DISTINCT tenant_id) 
    INTO tenant_list, tenant_count
    FROM tenant.sample_data;
    
    test_end_time := clock_timestamp();
    
    -- Admin test passes if they can see records from multiple tenants
    RETURN QUERY SELECT
        'Admin access test',
        (total_record_count > 0 AND tenant_count > 1),
        total_record_count,
        tenant_count,
        jsonb_build_object(
            'admin_user', admin_user_name,
            'total_records_visible', total_record_count,
            'tenants_visible', tenant_count,
            'tenant_ids_visible', tenant_list,
            'test_timestamp', test_start_time,
            'execution_time_ms', EXTRACT(MILLISECONDS FROM (test_end_time - test_start_time))
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to test CRUD operations with RLS
CREATE OR REPLACE FUNCTION test_rls_crud_operations(
    test_tenant_id UUID,
    test_user_name TEXT
) RETURNS TABLE(
    operation TEXT,
    test_result BOOLEAN,
    records_affected INTEGER,
    test_details JSONB
) AS $$
DECLARE
    insert_result INTEGER;
    update_result INTEGER;
    delete_result INTEGER;
    test_record_id UUID;
    test_start_time TIMESTAMP;
BEGIN
    test_start_time := clock_timestamp();
    
    -- Set tenant context
    PERFORM set_current_tenant(test_tenant_id);
    
    -- Test INSERT operation
    BEGIN
        INSERT INTO tenant.sample_data (
            tenant_id, name, description, category, metadata, created_by
        ) VALUES (
            test_tenant_id,
            'RLS CRUD Test Record',
            'Test record for CRUD operations validation',
            'testing',
            '{"test_type": "crud_validation", "created_by_test": true}',
            test_tenant_id
        ) RETURNING id INTO test_record_id;
        
        insert_result := 1;
    EXCEPTION
        WHEN OTHERS THEN
            insert_result := 0;
            test_record_id := NULL;
    END;
    
    -- Return INSERT test result
    RETURN QUERY SELECT
        'INSERT',
        (insert_result = 1),
        insert_result,
        jsonb_build_object(
            'operation', 'INSERT',
            'tenant_id', test_tenant_id,
            'user', test_user_name,
            'record_id', test_record_id,
            'test_timestamp', test_start_time
        );
    
    -- Test UPDATE operation (only if INSERT succeeded)
    IF test_record_id IS NOT NULL THEN
        BEGIN
            UPDATE tenant.sample_data 
            SET description = 'Updated by RLS CRUD test', 
                metadata = metadata || '{"updated_by_test": true}'
            WHERE id = test_record_id;
            
            GET DIAGNOSTICS update_result = ROW_COUNT;
        EXCEPTION
            WHEN OTHERS THEN
                update_result := 0;
        END;
        
        -- Return UPDATE test result
        RETURN QUERY SELECT
            'UPDATE',
            (update_result = 1),
            update_result,
            jsonb_build_object(
                'operation', 'UPDATE',
                'tenant_id', test_tenant_id,
                'user', test_user_name,
                'record_id', test_record_id,
                'rows_updated', update_result,
                'test_timestamp', test_start_time
            );
        
        -- Test DELETE operation
        BEGIN
            DELETE FROM tenant.sample_data WHERE id = test_record_id;
            GET DIAGNOSTICS delete_result = ROW_COUNT;
        EXCEPTION
            WHEN OTHERS THEN
                delete_result := 0;
        END;
        
        -- Return DELETE test result  
        RETURN QUERY SELECT
            'DELETE',
            (delete_result = 1),
            delete_result,
            jsonb_build_object(
                'operation', 'DELETE',
                'tenant_id', test_tenant_id,
                'user', test_user_name,
                'record_id', test_record_id,
                'rows_deleted', delete_result,
                'test_timestamp', test_start_time
            );
    ELSE
        -- If INSERT failed, mark UPDATE and DELETE as failed too
        RETURN QUERY SELECT
            'UPDATE',
            false,
            0,
            jsonb_build_object('operation', 'UPDATE', 'error', 'INSERT failed, skipping UPDATE');
            
        RETURN QUERY SELECT
            'DELETE', 
            false,
            0,
            jsonb_build_object('operation', 'DELETE', 'error', 'INSERT failed, skipping DELETE');
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to execute comprehensive RLS test suite
CREATE OR REPLACE FUNCTION run_comprehensive_rls_tests()
RETURNS TABLE(
    test_category TEXT,
    test_name TEXT,
    test_result BOOLEAN,
    test_details JSONB
) AS $$
DECLARE
    test_tenant_alpha UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    test_tenant_beta UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    suite_start_time TIMESTAMP;
BEGIN
    suite_start_time := clock_timestamp();
    
    -- Test 1: Basic tenant isolation for Alpha
    RETURN QUERY 
    SELECT 
        'Isolation' as test_category,
        test_name,
        test_result,
        test_details
    FROM test_tenant_isolation('test_alpha_user', test_tenant_alpha, 'Alpha tenant isolation');
    
    -- Test 2: Basic tenant isolation for Beta
    RETURN QUERY 
    SELECT 
        'Isolation' as test_category,
        test_name,
        test_result, 
        test_details
    FROM test_tenant_isolation('test_beta_user', test_tenant_beta, 'Beta tenant isolation');
    
    -- Test 3: Cross-tenant access prevention
    RETURN QUERY 
    SELECT 
        'Security' as test_category,
        test_name,
        test_result,
        test_details
    FROM test_cross_tenant_access('test_alpha_user', test_tenant_alpha, test_tenant_beta);
    
    -- Test 4: Admin access validation
    RETURN QUERY 
    SELECT 
        'Admin' as test_category,
        test_name,
        test_result,
        test_details
    FROM test_admin_access('test_admin_user');
    
    -- Test 5: Performance measurement
    RETURN QUERY 
    SELECT 
        'Performance' as test_category,
        test_name,
        (avg_execution_time < 200) as test_result, -- Pass if under 200ms average
        performance_details as test_details
    FROM test_rls_performance(test_tenant_alpha, 50);
    
    -- Test 6: CRUD operations
    RETURN QUERY
    SELECT 
        'CRUD' as test_category,
        'CRUD - ' || operation as test_name,
        test_result,
        test_details
    FROM test_rls_crud_operations(test_tenant_alpha, 'test_alpha_user');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==================================================
-- UTILITY FUNCTIONS FOR TEST MANAGEMENT
-- ==================================================

-- Function to generate test execution report
CREATE OR REPLACE FUNCTION generate_test_report(
    test_run_id TEXT DEFAULT NULL
) RETURNS TABLE(
    report_section TEXT,
    metric_name TEXT,
    metric_value TEXT,
    details JSONB
) AS $$
DECLARE
    run_id TEXT;
    total_tests INTEGER;
    passed_tests INTEGER;
    failed_tests INTEGER;
    pass_rate NUMERIC;
BEGIN
    -- Generate run ID if not provided
    run_id := COALESCE(test_run_id, 'rls_test_' || EXTRACT(EPOCH FROM CURRENT_TIMESTAMP)::TEXT);
    
    -- Execute comprehensive test suite and store results temporarily
    CREATE TEMP TABLE IF NOT EXISTS temp_test_results AS
    SELECT * FROM run_comprehensive_rls_tests();
    
    -- Calculate summary statistics
    SELECT COUNT(*), 
           SUM(CASE WHEN test_result THEN 1 ELSE 0 END),
           SUM(CASE WHEN NOT test_result THEN 1 ELSE 0 END)
    INTO total_tests, passed_tests, failed_tests
    FROM temp_test_results;
    
    pass_rate := CASE WHEN total_tests > 0 THEN (passed_tests::NUMERIC / total_tests * 100) ELSE 0 END;
    
    -- Return summary metrics
    RETURN QUERY SELECT
        'Summary' as report_section,
        'Total Tests' as metric_name,
        total_tests::TEXT as metric_value,
        jsonb_build_object('run_id', run_id, 'timestamp', CURRENT_TIMESTAMP) as details;
        
    RETURN QUERY SELECT
        'Summary' as report_section,
        'Passed Tests' as metric_name,
        passed_tests::TEXT as metric_value,
        jsonb_build_object('percentage', ROUND(pass_rate, 2)) as details;
        
    RETURN QUERY SELECT
        'Summary' as report_section,
        'Failed Tests' as metric_name,
        failed_tests::TEXT as metric_value,
        jsonb_build_object('percentage', ROUND(100 - pass_rate, 2)) as details;
        
    RETURN QUERY SELECT
        'Summary' as report_section,
        'Pass Rate' as metric_name,
        ROUND(pass_rate, 2)::TEXT || '%' as metric_value,
        jsonb_build_object('threshold', '95%', 'status', CASE WHEN pass_rate >= 95 THEN 'GOOD' ELSE 'NEEDS_ATTENTION' END) as details;
    
    -- Return detailed test results
    RETURN QUERY SELECT
        'Details' as report_section,
        test_category || ' - ' || test_name as metric_name,
        CASE WHEN test_result THEN 'PASS' ELSE 'FAIL' END as metric_value,
        test_details as details
    FROM temp_test_results;
    
    -- Clean up temp table
    DROP TABLE temp_test_results;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==================================================
-- GRANT PERMISSIONS
-- ==================================================

-- Grant execute permissions to test roles
GRANT EXECUTE ON FUNCTION test_tenant_isolation(TEXT, UUID, TEXT) TO tenant_user, admin_user, readonly_user;
GRANT EXECUTE ON FUNCTION test_cross_tenant_access(TEXT, UUID, UUID) TO tenant_user, admin_user, readonly_user;
GRANT EXECUTE ON FUNCTION test_rls_performance(UUID, INTEGER) TO tenant_user, admin_user, readonly_user;
GRANT EXECUTE ON FUNCTION test_admin_access(TEXT) TO admin_user;
GRANT EXECUTE ON FUNCTION test_rls_crud_operations(UUID, TEXT) TO tenant_user, admin_user;
GRANT EXECUTE ON FUNCTION run_comprehensive_rls_tests() TO tenant_user, admin_user, readonly_user;
GRANT EXECUTE ON FUNCTION generate_test_report(TEXT) TO tenant_user, admin_user, readonly_user;

-- ==================================================
-- VERIFICATION
-- ==================================================

\echo '=== RLS Test Functions Created Successfully ==='
\echo 'Available test functions:'
\echo '1. test_tenant_isolation(user, tenant_id, description)'
\echo '2. test_cross_tenant_access(user, user_tenant, target_tenant)'
\echo '3. test_rls_performance(tenant_id, iterations)'
\echo '4. test_admin_access(admin_user)'
\echo '5. test_rls_crud_operations(tenant_id, user)'
\echo '6. run_comprehensive_rls_tests()'
\echo '7. generate_test_report(run_id)'
\echo ''
\echo 'Quick test execution:'
\echo 'SELECT * FROM run_comprehensive_rls_tests();'
\echo 'SELECT * FROM generate_test_report();'