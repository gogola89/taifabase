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
-- OPTIMIZED (Day 2): Marked as STABLE to enable caching within query execution
-- This reduces function calls from 3 per row to 1 per query
CREATE OR REPLACE FUNCTION get_current_tenant()
RETURNS UUID AS $$
BEGIN
    RETURN current_setting('app.current_tenant_id', true)::uuid;
EXCEPTION
    WHEN others THEN
        -- Return NULL if no tenant is set
        RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to validate current user can access a tenant
-- OPTIMIZED (Day 2): Marked as STABLE for query-level caching
CREATE OR REPLACE FUNCTION validate_tenant_access(tenant_uuid UUID)
RETURNS boolean AS $$
BEGIN
    -- For Phase 1, we'll implement basic validation
    -- In production, this would check user-tenant relationships
    RETURN EXISTS (SELECT 1 FROM core.tenants WHERE id = tenant_uuid AND status = 'active');
END;
$$ LANGUAGE plpgsql STABLE;

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

-- OPTIMIZATION NOTE (Day 2):
-- The policy below uses multiple function calls that were causing 84x performance degradation.
-- After marking functions as STABLE, PostgreSQL will cache the function result within a query,
-- reducing overhead significantly. We keep all three conditions for defense-in-depth security:
-- 1. tenant_id = get_current_tenant() - Primary isolation
-- 2. get_current_tenant() IS NOT NULL - Prevents null tenant access
-- 3. validate_tenant_access() - Ensures tenant is active
-- With STABLE functions, these 3 conditions only evaluate the function ONCE per query, not per row.

-- Policy 1: Basic Tenant Isolation for regular users (OPTIMIZED Day 2)
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
-- STEP 8: RLS-Optimized Indexes (Day 2 Optimization)
-- ==================================================

-- Composite indexes that place tenant_id FIRST for optimal RLS performance
-- This allows PostgreSQL to efficiently filter by tenant before applying other conditions

-- Index for category-based queries (most common in analytics)
CREATE INDEX IF NOT EXISTS idx_sample_data_tenant_category
ON tenant.sample_data(tenant_id, category);

-- Index for time-based queries (common for recent data retrieval)
CREATE INDEX IF NOT EXISTS idx_sample_data_tenant_created
ON tenant.sample_data(tenant_id, created_at DESC);

-- Index for JSONB metadata queries with tenant filtering
CREATE INDEX IF NOT EXISTS idx_sample_data_tenant_metadata
ON tenant.sample_data(tenant_id, metadata)
WHERE metadata IS NOT NULL;

-- Composite index for full-text search with tenant isolation
CREATE INDEX IF NOT EXISTS idx_sample_data_tenant_value
ON tenant.sample_data(tenant_id, value);

-- ==================================================
-- STEP 9: RLS Template for Future Tenant Tables (Day 2 - US-103)
-- ==================================================

-- This section provides a template for extending RLS to new tenant tables
-- Apply this pattern to ANY new table in the tenant schema

/*
TEMPLATE FOR ADDING RLS TO NEW TENANT TABLES:
----------------------------------------------

1. Enable RLS on the table:
   ALTER TABLE tenant.{table_name} ENABLE ROW LEVEL SECURITY;
   ALTER TABLE tenant.{table_name} FORCE ROW LEVEL SECURITY;

2. Create tenant isolation policy:
   CREATE POLICY tenant_isolation_policy ON tenant.{table_name}
       FOR ALL
       TO tenant_user
       USING (
           tenant_id = get_current_tenant()
           AND get_current_tenant() IS NOT NULL
           AND validate_tenant_access(get_current_tenant())
       );

3. Create admin access policy:
   CREATE POLICY admin_full_access_policy ON tenant.{table_name}
       FOR ALL
       TO admin_user
       USING (true);

4. Create readonly policy:
   CREATE POLICY readonly_access_policy ON tenant.{table_name}
       FOR SELECT
       TO readonly_user
       USING (true);

5. Create RLS-optimized indexes (tenant_id FIRST):
   CREATE INDEX idx_{table_name}_tenant_id ON tenant.{table_name}(tenant_id);
   CREATE INDEX idx_{table_name}_tenant_{common_column}
   ON tenant.{table_name}(tenant_id, {common_column});

6. Test the RLS policies:
   -- Switch to a tenant context
   SELECT switch_to_tenant('acme-corp');

   -- Verify only tenant data is visible
   SELECT COUNT(*) FROM tenant.{table_name};

   -- Check query plan uses indexes
   EXPLAIN ANALYZE SELECT * FROM tenant.{table_name} LIMIT 10;
*/

-- Example: If we add a "projects" table to tenant schema:
-- (Commented out - uncomment and modify when adding new tenant tables)
/*
ALTER TABLE tenant.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant.projects FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_policy ON tenant.projects
    FOR ALL TO tenant_user
    USING (
        tenant_id = get_current_tenant()
        AND get_current_tenant() IS NOT NULL
        AND validate_tenant_access(get_current_tenant())
    );

CREATE POLICY admin_full_access_policy ON tenant.projects
    FOR ALL TO admin_user USING (true);

CREATE POLICY readonly_access_policy ON tenant.projects
    FOR SELECT TO readonly_user USING (true);

CREATE INDEX idx_projects_tenant_id ON tenant.projects(tenant_id);
CREATE INDEX idx_projects_tenant_status ON tenant.projects(tenant_id, status);
CREATE INDEX idx_projects_tenant_created ON tenant.projects(tenant_id, created_at DESC);
*/

-- ==================================================
-- STEP 10: Extend RLS to core.users Table (Day 2 - US-103)
-- ==================================================

-- The core.users table contains tenant_id and should have RLS for defense-in-depth
-- This ensures users can only see/modify users within their own tenant

-- Enable RLS on users table
ALTER TABLE core.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.users FORCE ROW LEVEL SECURITY;

-- Policy 1: Tenant isolation for users table
CREATE POLICY tenant_isolation_policy ON core.users
    FOR ALL
    TO tenant_user
    USING (
        tenant_id = get_current_tenant()
        AND get_current_tenant() IS NOT NULL
        AND validate_tenant_access(get_current_tenant())
    );

-- Policy 2: Admin full access to all users
CREATE POLICY admin_full_access_policy ON core.users
    FOR ALL
    TO admin_user
    USING (true);

-- Policy 3: Readonly access to all users
CREATE POLICY readonly_access_policy ON core.users
    FOR SELECT
    TO readonly_user
    USING (true);

-- Create RLS-optimized composite indexes for users table
CREATE INDEX IF NOT EXISTS idx_users_tenant_email
ON core.users(tenant_id, email);

CREATE INDEX IF NOT EXISTS idx_users_tenant_username
ON core.users(tenant_id, username);

CREATE INDEX IF NOT EXISTS idx_users_tenant_status
ON core.users(tenant_id, status);

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