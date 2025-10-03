-- RLS Test Configuration Script
-- Author: Aisha Kamau - Senior QA Engineer
-- Date: 2025-10-03
-- Purpose: Set up test-specific tenants, users, and configurations for RLS testing
-- Integration: Works with Marcus Rodriguez's RLS implementation

-- ==================================================
-- STEP 1: Create Test-Specific Tenants
-- ==================================================

\echo '=== Creating Test Tenants for RLS Validation ==='

-- Insert test tenants with predictable UUIDs for testing
INSERT INTO core.tenants (id, name, slug, status, created_at, updated_at) VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Test Tenant Alpha', 'test-alpha', 'active', NOW(), NOW()),
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Test Tenant Beta', 'test-beta', 'active', NOW(), NOW()),
('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Test Tenant Gamma', 'test-gamma', 'active', NOW(), NOW()),
('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Test Tenant Delta', 'test-delta', 'active', NOW(), NOW()),
('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Test Tenant Epsilon', 'test-epsilon', 'active', NOW(), NOW())
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    slug = EXCLUDED.slug,
    status = EXCLUDED.status,
    updated_at = NOW();

-- ==================================================
-- STEP 2: Create Test Users for Each Tenant
-- ==================================================

\echo '=== Creating Test Users for RLS Validation ==='

-- Drop existing test users if they exist (for idempotent execution)
DROP USER IF EXISTS test_alpha_user;
DROP USER IF EXISTS test_beta_user;
DROP USER IF EXISTS test_gamma_user;
DROP USER IF EXISTS test_delta_user;
DROP USER IF EXISTS test_epsilon_user;
DROP USER IF EXISTS test_admin_user;
DROP USER IF EXISTS test_readonly_user;

-- Create test users for specific tenants
CREATE USER test_alpha_user WITH PASSWORD 'alpha_pass';
CREATE USER test_beta_user WITH PASSWORD 'beta_pass';
CREATE USER test_gamma_user WITH PASSWORD 'gamma_pass';
CREATE USER test_delta_user WITH PASSWORD 'delta_pass';
CREATE USER test_epsilon_user WITH PASSWORD 'epsilon_pass';

-- Grant tenant_user role to test users
GRANT tenant_user TO test_alpha_user, test_beta_user, test_gamma_user, test_delta_user, test_epsilon_user;

-- Create test admin user with full access
CREATE USER test_admin_user WITH PASSWORD 'admin_pass';
GRANT admin_user TO test_admin_user;

-- Create test read-only user
CREATE USER test_readonly_user WITH PASSWORD 'readonly_pass';
GRANT readonly_user TO test_readonly_user;

-- ==================================================
-- STEP 3: Create Test-Specific Helper Functions
-- ==================================================

\echo '=== Creating RLS Test Helper Functions ==='

-- Function to reset all test user sessions
CREATE OR REPLACE FUNCTION reset_test_user_sessions()
RETURNS TEXT AS $$
BEGIN
    -- This function helps ensure clean state between tests
    -- In a real implementation, you might terminate active sessions
    -- For now, we'll just clear any session variables
    
    PERFORM set_config('app.current_tenant_id', '', false);
    
    RETURN 'Test user sessions reset';
END;
$$ LANGUAGE plpgsql;

-- Function to validate test environment setup
CREATE OR REPLACE FUNCTION validate_test_environment()
RETURNS TABLE(
    component TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Check test tenants exist
    RETURN QUERY
    SELECT 
        'Test Tenants' as component,
        CASE 
            WHEN COUNT(*) = 5 THEN 'OK'
            ELSE 'FAILED'
        END as status,
        'Found ' || COUNT(*) || ' test tenants (expected 5)' as details
    FROM core.tenants 
    WHERE slug LIKE 'test-%';
    
    -- Check test users exist
    RETURN QUERY
    SELECT 
        'Test Users' as component,
        CASE 
            WHEN COUNT(*) >= 7 THEN 'OK'
            ELSE 'FAILED'
        END as status,
        'Found ' || COUNT(*) || ' test users (expected 7+)' as details
    FROM pg_roles 
    WHERE rolname LIKE 'test_%';
    
    -- Check RLS policies exist
    RETURN QUERY
    SELECT 
        'RLS Policies' as component,
        CASE 
            WHEN COUNT(*) >= 3 THEN 'OK'
            ELSE 'FAILED'
        END as status,
        'Found ' || COUNT(*) || ' RLS policies on sample_data (expected 3+)' as details
    FROM pg_policies 
    WHERE tablename = 'sample_data';
    
    -- Check sample_data table has RLS enabled
    RETURN QUERY
    SELECT 
        'RLS Status' as component,
        CASE 
            WHEN bool_and(rowsecurity AND forcerowsecurity) THEN 'OK'
            ELSE 'FAILED'
        END as status,
        'RLS enabled: ' || bool_and(rowsecurity) || ', Forced: ' || bool_and(forcerowsecurity) as details
    FROM pg_tables 
    WHERE tablename = 'sample_data';
END;
$$ LANGUAGE plpgsql;

-- Grant execute permissions for test helper functions
GRANT EXECUTE ON FUNCTION reset_test_user_sessions() TO tenant_user, admin_user, readonly_user;
GRANT EXECUTE ON FUNCTION validate_test_environment() TO tenant_user, admin_user, readonly_user;

-- ==================================================
-- STEP 4: Create Test Data Management Functions
-- ==================================================

\echo '=== Creating Test Data Management Functions ==='

-- Function to clean up test data
CREATE OR REPLACE FUNCTION cleanup_test_data()
RETURNS TEXT AS $$
DECLARE
    deleted_records INTEGER;
BEGIN
    -- Delete test data from sample_data table
    DELETE FROM tenant.sample_data 
    WHERE tenant_id IN (
        SELECT id FROM core.tenants WHERE slug LIKE 'test-%'
    );
    
    GET DIAGNOSTICS deleted_records = ROW_COUNT;
    
    RETURN 'Cleaned up ' || deleted_records || ' test records';
END;
$$ LANGUAGE plpgsql;

-- Function to generate lightweight test data
CREATE OR REPLACE FUNCTION generate_lightweight_test_data(
    target_tenant_slug TEXT DEFAULT 'test-alpha',
    record_count INTEGER DEFAULT 100
) RETURNS TEXT AS $$
DECLARE
    target_tenant_id UUID;
    created_records INTEGER := 0;
    i INTEGER;
BEGIN
    -- Get tenant ID from slug
    SELECT id INTO target_tenant_id
    FROM core.tenants 
    WHERE slug = target_tenant_slug AND status = 'active';
    
    IF target_tenant_id IS NULL THEN
        RETURN 'ERROR: Tenant not found: ' || target_tenant_slug;
    END IF;
    
    -- Generate test data
    FOR i IN 1..record_count LOOP
        INSERT INTO tenant.sample_data (
            tenant_id,
            name,
            description,
            category,
            metadata,
            created_by
        ) VALUES (
            target_tenant_id,
            'RLS Test Record ' || i,
            'Test data for RLS validation - ' || target_tenant_slug || ' - Record ' || i,
            CASE (i % 6)
                WHEN 0 THEN 'finance'
                WHEN 1 THEN 'marketing'
                WHEN 2 THEN 'operations'
                WHEN 3 THEN 'technology'
                WHEN 4 THEN 'human_resources'
                ELSE 'general'
            END,
            jsonb_build_object(
                'test_record', true,
                'tenant_slug', target_tenant_slug,
                'record_number', i,
                'test_category', 'rls_validation',
                'generated_at', CURRENT_TIMESTAMP
            ),
            target_tenant_id
        );
        created_records := created_records + 1;
    END LOOP;
    
    RETURN 'Generated ' || created_records || ' test records for ' || target_tenant_slug;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permissions for data management functions
GRANT EXECUTE ON FUNCTION cleanup_test_data() TO admin_user;
GRANT EXECUTE ON FUNCTION generate_lightweight_test_data(TEXT, INTEGER) TO admin_user;

-- ==================================================
-- STEP 5: Create Test Execution Configuration
-- ==================================================

\echo '=== Creating Test Execution Configuration ==='

-- Create a configuration table for test parameters
CREATE TABLE IF NOT EXISTS testing.test_config (
    config_key TEXT PRIMARY KEY,
    config_value JSONB NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default test configuration
INSERT INTO testing.test_config (config_key, config_value, description) VALUES
('tenant_isolation_thresholds', 
 '{"max_cross_tenant_records": 0, "min_own_tenant_records": 1}',
 'Thresholds for tenant isolation validation'),
('performance_thresholds', 
 '{"max_query_time_ms": 200, "max_overhead_percent": 20}',
 'Performance acceptance criteria'),
('test_data_volumes', 
 '{"small": 100, "medium": 1000, "large": 10000}',
 'Standard test data volumes for different test scenarios'),
('test_tenant_mapping', 
 '{"alpha": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "beta": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "gamma": "cccccccc-cccc-cccc-cccc-cccccccccccc", "delta": "dddddddd-dddd-dddd-dddd-dddddddddddd", "epsilon": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"}',
 'Mapping of test tenant names to UUIDs')
ON CONFLICT (config_key) DO UPDATE SET
    config_value = EXCLUDED.config_value,
    updated_at = CURRENT_TIMESTAMP;

-- Grant read access to test configuration
GRANT SELECT ON testing.test_config TO tenant_user, admin_user, readonly_user;

-- ==================================================
-- STEP 6: Verification and Validation
-- ==================================================

\echo '=== Validating Test Environment Setup ==='

-- Show created test tenants
SELECT 'Test Tenants Created:' as info;
SELECT id, name, slug, status 
FROM core.tenants 
WHERE slug LIKE 'test-%' 
ORDER BY slug;

-- Show created test users
SELECT 'Test Users Created:' as info;
SELECT rolname, rolcanlogin 
FROM pg_roles 
WHERE rolname LIKE 'test_%' 
ORDER BY rolname;

-- Validate environment setup
SELECT 'Environment Validation:' as info;
SELECT * FROM validate_test_environment();

-- Show test configuration
SELECT 'Test Configuration:' as info;
SELECT config_key, config_value, description 
FROM testing.test_config 
ORDER BY config_key;

\echo '=== RLS Test Configuration Complete ==='
\echo 'Next steps:'
\echo '1. Generate test data: SELECT generate_lightweight_test_data(''test-alpha'', 100);'
\echo '2. Run validation: SELECT * FROM validate_test_environment();'
\echo '3. Execute RLS tests using the testing framework'
\echo '4. Clean up when done: SELECT cleanup_test_data();'