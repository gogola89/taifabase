-- RLS Implementation Script - Phase 1
-- Implements basic tenant isolation using Row Level Security
-- Created by: Marcus Rodriguez - Backend Engineer
-- Date: 2025-10-03
-- Purpose: Establish first RLS policy for tenant isolation testing

-- ==================================================
-- STEP 1: Create Session Management Functions
-- ==================================================

-- Function to set current tenant for session
CREATE OR REPLACE FUNCTION set_current_tenant(tenant_uuid UUID)
RETURNS void AS $$
BEGIN
    -- Validate that the tenant exists
    IF NOT EXISTS (SELECT 1 FROM core.tenants WHERE id = tenant_uuid) THEN
        RAISE EXCEPTION 'Invalid tenant ID: %', tenant_uuid;
    END IF;
    
    -- Set the session variable
    PERFORM set_config('app.current_tenant_id', tenant_uuid::text, false);
    
    -- Log the tenant switch for audit purposes
    RAISE NOTICE 'Current tenant set to: %', tenant_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get current tenant from session
CREATE OR REPLACE FUNCTION get_current_tenant()
RETURNS UUID AS $$
BEGIN
    RETURN current_setting('app.current_tenant_id', true)::uuid;
EXCEPTION
    WHEN others THEN
        -- Return NULL if no tenant is set
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Function to validate current user can access a tenant
CREATE OR REPLACE FUNCTION validate_tenant_access(tenant_uuid UUID)
RETURNS boolean AS $$
BEGIN
    -- For Phase 1, we'll implement basic validation
    -- In production, this would check user-tenant relationships
    RETURN EXISTS (SELECT 1 FROM core.tenants WHERE id = tenant_uuid AND status = 'active');
END;
$$ LANGUAGE plpgsql;

-- ==================================================
-- STEP 2: Create Database Roles for RLS
-- ==================================================

-- Drop existing roles if they exist (for development)
DROP ROLE IF EXISTS tenant_user;
DROP ROLE IF EXISTS admin_user;
DROP ROLE IF EXISTS readonly_user;

-- Application-level role for tenant users
CREATE ROLE tenant_user;
GRANT USAGE ON SCHEMA core, tenant, audit TO tenant_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA tenant TO tenant_user;
GRANT SELECT ON ALL TABLES IN SCHEMA core TO tenant_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA core, tenant TO tenant_user;

-- Grant access to session management functions
GRANT EXECUTE ON FUNCTION set_current_tenant(UUID) TO tenant_user;
GRANT EXECUTE ON FUNCTION get_current_tenant() TO tenant_user;
GRANT EXECUTE ON FUNCTION validate_tenant_access(UUID) TO tenant_user;

-- Administrative role for system operations
CREATE ROLE admin_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA core, tenant, audit TO admin_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA core, tenant, audit TO admin_user;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA core, tenant, audit TO admin_user;

-- Read-only role for reporting (can bypass RLS when needed)
CREATE ROLE readonly_user;
GRANT USAGE ON SCHEMA core, tenant, audit TO readonly_user;
GRANT SELECT ON ALL TABLES IN SCHEMA core, tenant, audit TO readonly_user;

-- ==================================================
-- STEP 3: Create Test Users for Different Tenants
-- ==================================================

-- Drop existing test users if they exist
DROP USER IF EXISTS acme_user;
DROP USER IF EXISTS techstart_user;
DROP USER IF EXISTS global_user;
DROP USER IF EXISTS system_admin;

-- Create test users for specific tenants
CREATE USER acme_user WITH PASSWORD 'acme_password';
GRANT tenant_user TO acme_user;

CREATE USER techstart_user WITH PASSWORD 'techstart_password';
GRANT tenant_user TO techstart_user;

CREATE USER global_user WITH PASSWORD 'global_password';
GRANT tenant_user TO global_user;

-- Create system administrator
CREATE USER system_admin WITH PASSWORD 'admin_password';
GRANT admin_user TO system_admin;

-- ==================================================
-- STEP 4: Enable RLS on Target Table
-- ==================================================

-- Enable RLS on the sample_data table
ALTER TABLE tenant.sample_data ENABLE ROW LEVEL SECURITY;

-- Force RLS even for table owner (important for security)
ALTER TABLE tenant.sample_data FORCE ROW LEVEL SECURITY;

-- ==================================================
-- STEP 5: Create RLS Policies
-- ==================================================

-- Policy 1: Basic Tenant Isolation for regular users
CREATE POLICY tenant_isolation_policy ON tenant.sample_data
    FOR ALL
    TO tenant_user
    USING (
        tenant_id = get_current_tenant()
        AND get_current_tenant() IS NOT NULL
        AND validate_tenant_access(get_current_tenant())
    );

-- Policy 2: Administrative access (full access for admins)
CREATE POLICY admin_full_access_policy ON tenant.sample_data
    FOR ALL
    TO admin_user
    USING (true);

-- Policy 3: Read-only access for reporting
CREATE POLICY readonly_access_policy ON tenant.sample_data
    FOR SELECT
    TO readonly_user
    USING (true);

-- ==================================================
-- STEP 6: Create Helper Functions for Testing
-- ==================================================

-- Function to safely switch tenant context for a user
CREATE OR REPLACE FUNCTION switch_to_tenant(tenant_slug text)
RETURNS text AS $$
DECLARE
    tenant_uuid UUID;
    tenant_name text;
BEGIN
    -- Look up tenant by slug
    SELECT id, name INTO tenant_uuid, tenant_name
    FROM core.tenants 
    WHERE slug = tenant_slug AND status = 'active';
    
    IF tenant_uuid IS NULL THEN
        RETURN 'ERROR: Tenant not found or inactive: ' || tenant_slug;
    END IF;
    
    -- Set the current tenant
    PERFORM set_current_tenant(tenant_uuid);
    
    RETURN 'SUCCESS: Switched to tenant: ' || tenant_name || ' (' || tenant_uuid || ')';
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission to tenant users
GRANT EXECUTE ON FUNCTION switch_to_tenant(text) TO tenant_user;

-- Function to show current context
CREATE OR REPLACE FUNCTION show_current_context()
RETURNS table(
    current_user_name text,
    current_tenant_id UUID,
    tenant_name text,
    accessible_records bigint
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        current_user::text,
        get_current_tenant(),
        t.name,
        COALESCE(
            (SELECT COUNT(*) FROM tenant.sample_data WHERE tenant_id = get_current_tenant()),
            0::bigint
        ) as accessible_records
    FROM core.tenants t 
    WHERE t.id = get_current_tenant();
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission to all roles
GRANT EXECUTE ON FUNCTION show_current_context() TO tenant_user, admin_user, readonly_user;

-- ==================================================
-- STEP 7: Verification and Testing Setup
-- ==================================================

-- Create a view to help with testing
CREATE OR REPLACE VIEW tenant.rls_test_view AS
SELECT 
    'Current User: ' || current_user as context_info,
    'Current Tenant: ' || COALESCE(get_current_tenant()::text, 'NONE SET') as tenant_context,
    COUNT(*) as visible_records,
    array_agg(DISTINCT tenant_id) as visible_tenant_ids
FROM tenant.sample_data;

-- Grant access to the test view
GRANT SELECT ON tenant.rls_test_view TO tenant_user, admin_user, readonly_user;

-- ==================================================
-- VERIFICATION QUERIES
-- ==================================================

-- Show RLS policies created
\echo '=== RLS POLICIES CREATED ==='
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies 
WHERE tablename = 'sample_data'
ORDER BY policyname;

-- Show roles created
\echo '=== ROLES CREATED ==='
SELECT rolname, rolcanlogin 
FROM pg_roles 
WHERE rolname IN ('tenant_user', 'admin_user', 'readonly_user', 'acme_user', 'techstart_user', 'global_user', 'system_admin')
ORDER BY rolname;

-- Show current table status
\echo '=== TABLE RLS STATUS ==='
SELECT 
    schemaname,
    tablename,
    rowsecurity,
    forcerowsecurity
FROM pg_tables 
WHERE tablename = 'sample_data';

\echo '=== RLS IMPLEMENTATION COMPLETED ==='
\echo 'Next steps:'
\echo '1. Test with different users: \c taifabase_dev acme_user'
\echo '2. Set tenant context: SELECT switch_to_tenant(''acme-corp'');'
\echo '3. Test queries: SELECT * FROM tenant.sample_data LIMIT 5;'
\echo '4. Check context: SELECT * FROM show_current_context();'
\echo '5. Run performance comparison tests'