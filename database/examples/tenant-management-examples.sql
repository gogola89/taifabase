-- Tenant Management API - Usage Examples
-- Demonstrates practical usage of all tenant management functions
-- Created by: Marcus Rodriguez - Backend Engineer
-- Date: 2025-10-05
-- Purpose: Provide copy-paste examples for common tenant operations

\echo '=========================================='
\echo 'TENANT MANAGEMENT API - USAGE EXAMPLES'
\echo '=========================================='

-- ==================================================
-- EXAMPLE 1: Create a New Tenant
-- ==================================================

\echo ''
\echo '=== EXAMPLE 1: Create a New Tenant ==='

-- Create a new tenant for Acme Corporation
-- This will:
-- 1. Create the tenant record
-- 2. Create an admin user
-- 3. Link the user to the tenant with 'owner' role
-- 4. Log the operation to audit table

SELECT create_tenant(
    'Acme Corporation',          -- Tenant name (human-readable)
    'acme-corp',                 -- Tenant slug (URL-safe identifier)
    'admin@acme.com',            -- Admin email
    'acme_admin'                 -- Admin username
) AS new_tenant_id;

-- Expected result: UUID of the newly created tenant
-- Example: a1b2c3d4-e5f6-7890-abcd-ef1234567890

-- Save the tenant ID for later use
\gset

\echo 'New tenant created with ID: :new_tenant_id'

-- ==================================================
-- EXAMPLE 2: Create Multiple Tenants
-- ==================================================

\echo ''
\echo '=== EXAMPLE 2: Create Multiple Tenants ==='

-- Create several tenants in one transaction
BEGIN;

SELECT create_tenant(
    'TechStart Inc',
    'techstart',
    'admin@techstart.io',
    'techstart_admin'
) AS techstart_id \gset

SELECT create_tenant(
    'Global Innovations',
    'global-innovations',
    'admin@globalinno.com',
    'global_admin'
) AS global_id \gset

SELECT create_tenant(
    'DataCorp Solutions',
    'datacorp',
    'admin@datacorp.com',
    'datacorp_admin'
) AS datacorp_id \gset

COMMIT;

\echo 'Created 3 tenants successfully'

-- ==================================================
-- EXAMPLE 3: Update Tenant Name
-- ==================================================

\echo ''
\echo '=== EXAMPLE 3: Update Tenant Name ==='

-- Update only the tenant name
SELECT update_tenant(
    :new_tenant_id::UUID,        -- Tenant ID
    'Acme Corporation Inc.',     -- New name
    NULL,                        -- Status unchanged
    NULL                         -- Settings unchanged
);

-- Verify the update
SELECT name, status, settings
FROM core.tenants
WHERE id = :new_tenant_id::UUID;

-- ==================================================
-- EXAMPLE 4: Update Tenant Status
-- ==================================================

\echo ''
\echo '=== EXAMPLE 4: Update Tenant Status ==='

-- Suspend a tenant (useful for billing issues, violations)
SELECT update_tenant(
    :techstart_id::UUID,
    NULL,                        -- Name unchanged
    'suspended',                 -- Set status to suspended
    NULL                         -- Settings unchanged
);

-- Reactivate the tenant
SELECT update_tenant(
    :techstart_id::UUID,
    NULL,
    'active',
    NULL
);

-- ==================================================
-- EXAMPLE 5: Update Tenant Settings
-- ==================================================

\echo ''
\echo '=== EXAMPLE 5: Update Tenant Settings ==='

-- Configure tenant settings (plan, limits, features)
SELECT update_tenant(
    :new_tenant_id::UUID,
    NULL,
    NULL,
    '{
        "plan": "professional",
        "max_users": 100,
        "max_storage_gb": 500,
        "features": {
            "api_access": true,
            "custom_domain": true,
            "sso": false,
            "advanced_analytics": true
        },
        "billing": {
            "stripe_customer_id": "cus_123456789",
            "subscription_id": "sub_987654321"
        }
    }'::jsonb
);

-- Update specific settings (merge with existing)
SELECT update_tenant(
    :new_tenant_id::UUID,
    NULL,
    NULL,
    '{"features": {"sso": true}}'::jsonb  -- This will merge with existing features
);

-- View current settings
SELECT settings
FROM core.tenants
WHERE id = :new_tenant_id::UUID;

-- ==================================================
-- EXAMPLE 6: Update Multiple Tenant Fields
-- ==================================================

\echo ''
\echo '=== EXAMPLE 6: Update Multiple Fields at Once ==='

SELECT update_tenant(
    :global_id::UUID,
    'Global Innovations Ltd',    -- Update name
    'active',                    -- Ensure active status
    '{"plan": "enterprise"}'::jsonb  -- Set plan
);

-- ==================================================
-- EXAMPLE 7: Create and Add Users to Tenant
-- ==================================================

\echo ''
\echo '=== EXAMPLE 7: Add Users to Tenant ==='

-- First, create some users in the core.users table
-- (In production, this would be done via authentication service)

DO $$
DECLARE
    user1_id UUID;
    user2_id UUID;
    user3_id UUID;
BEGIN
    -- Create users for Acme Corporation
    INSERT INTO core.users (tenant_id, email, username, status)
    VALUES (:'new_tenant_id'::UUID, 'john@acme.com', 'john_doe', 'active')
    RETURNING id INTO user1_id;

    INSERT INTO core.users (tenant_id, email, username, status)
    VALUES (:'new_tenant_id'::UUID, 'jane@acme.com', 'jane_smith', 'active')
    RETURNING id INTO user2_id;

    INSERT INTO core.users (tenant_id, email, username, status)
    VALUES (:'new_tenant_id'::UUID, 'bob@acme.com', 'bob_johnson', 'active')
    RETURNING id INTO user3_id;

    -- Add users to tenant with different roles
    PERFORM add_user_to_tenant(user1_id, :'new_tenant_id'::UUID, 'admin');
    PERFORM add_user_to_tenant(user2_id, :'new_tenant_id'::UUID, 'member');
    PERFORM add_user_to_tenant(user3_id, :'new_tenant_id'::UUID, 'readonly');

    RAISE NOTICE 'Added 3 users to tenant with different roles';
END $$;

-- ==================================================
-- EXAMPLE 8: List User's Tenants
-- ==================================================

\echo ''
\echo '=== EXAMPLE 8: List User Tenants ==='

-- Get a user ID (in this example, we'll get the admin user)
SELECT id AS admin_user_id
FROM core.users
WHERE email = 'admin@acme.com'
\gset

-- List all tenants this user has access to
SELECT
    tenant_name,
    tenant_slug,
    tenant_status,
    user_role,
    joined_at
FROM list_user_tenants(:admin_user_id::UUID)
ORDER BY tenant_name;

-- ==================================================
-- EXAMPLE 9: Multi-Tenant User Access
-- ==================================================

\echo ''
\echo '=== EXAMPLE 9: Multi-Tenant User Access ==='

-- Create a user who belongs to multiple tenants

DO $$
DECLARE
    multi_user_id UUID;
BEGIN
    -- Create user in first tenant
    INSERT INTO core.users (tenant_id, email, username, status)
    VALUES (:'new_tenant_id'::UUID, 'consultant@example.com', 'consultant', 'active')
    RETURNING id INTO multi_user_id;

    -- Add to first tenant as admin
    PERFORM add_user_to_tenant(multi_user_id, :'new_tenant_id'::UUID, 'admin');

    -- Add to second tenant as member
    PERFORM add_user_to_tenant(multi_user_id, :'techstart_id'::UUID, 'member');

    -- Add to third tenant as readonly
    PERFORM add_user_to_tenant(multi_user_id, :'global_id'::UUID, 'readonly');

    RAISE NOTICE 'User added to 3 different tenants with different roles';

    -- List all tenants for this user
    RAISE NOTICE 'User tenants:';
    FOR rec IN SELECT * FROM list_user_tenants(multi_user_id) LOOP
        RAISE NOTICE '  - % (%) as %', rec.tenant_name, rec.tenant_slug, rec.user_role;
    END LOOP;
END $$;

-- ==================================================
-- EXAMPLE 10: Remove User from Tenant
-- ==================================================

\echo ''
\echo '=== EXAMPLE 10: Remove User from Tenant ==='

-- Get a member user (not owner)
SELECT u.id AS member_user_id
FROM core.users u
JOIN core.tenant_users tu ON u.id = tu.user_id
WHERE tu.tenant_id = :new_tenant_id::UUID
AND tu.role = 'member'
LIMIT 1
\gset

-- Remove user from tenant
SELECT remove_user_from_tenant(
    :member_user_id::UUID,
    :new_tenant_id::UUID
);

-- Verify removal
SELECT COUNT(*) as remaining_users
FROM core.tenant_users
WHERE tenant_id = :new_tenant_id::UUID;

-- ==================================================
-- EXAMPLE 11: Soft Delete Tenant
-- ==================================================

\echo ''
\echo '=== EXAMPLE 11: Soft Delete Tenant (Safe) ==='

-- Soft delete sets status to 'inactive' but preserves all data
SELECT delete_tenant(:datacorp_id::UUID);
-- or explicitly: SELECT delete_tenant(:datacorp_id::UUID, FALSE);

-- Verify soft delete
SELECT name, status
FROM core.tenants
WHERE id = :datacorp_id::UUID;

-- Check that users still exist
SELECT COUNT(*) as users_still_exist
FROM core.users
WHERE tenant_id = :datacorp_id::UUID;

-- Reactivate soft-deleted tenant
SELECT update_tenant(:datacorp_id::UUID, NULL, 'active', NULL);

-- ==================================================
-- EXAMPLE 12: Hard Delete Tenant (DANGEROUS)
-- ==================================================

\echo ''
\echo '=== EXAMPLE 12: Hard Delete Tenant (PERMANENT) ==='

-- Create a test tenant specifically for hard deletion
SELECT create_tenant(
    'Temporary Test Tenant',
    'temp-test-tenant',
    'temp@test.com',
    'temp_admin'
) AS temp_tenant_id \gset

-- Hard delete (PERMANENT - cannot be undone!)
-- Use with extreme caution in production
SELECT delete_tenant(:temp_tenant_id::UUID, TRUE);

-- Verify complete removal
SELECT EXISTS (
    SELECT 1 FROM core.tenants WHERE id = :temp_tenant_id::UUID
) AS tenant_exists;

-- ==================================================
-- EXAMPLE 13: Tenant Creation with RLS Context
-- ==================================================

\echo ''
\echo '=== EXAMPLE 13: Working with RLS ==='

-- After creating a tenant, set it as the current tenant for RLS
SELECT set_current_tenant(:new_tenant_id::UUID);

-- Now queries will be filtered by RLS
SELECT COUNT(*) as my_data
FROM tenant.sample_data;

-- View current tenant context
SELECT * FROM show_current_context();

-- Add some tenant-specific data
INSERT INTO tenant.sample_data (tenant_id, name, description, value, category)
VALUES
    (:new_tenant_id::UUID, 'Q1 Revenue', 'First quarter revenue', 150000.00, 'finance'),
    (:new_tenant_id::UUID, 'User Growth', 'New users this month', 1250.00, 'metrics'),
    (:new_tenant_id::UUID, 'Support Tickets', 'Open support tickets', 42.00, 'operations');

-- Query with RLS active
SELECT name, category, value
FROM tenant.sample_data
ORDER BY category, name;

-- ==================================================
-- EXAMPLE 14: Tenant Onboarding Flow
-- ==================================================

\echo ''
\echo '=== EXAMPLE 14: Complete Tenant Onboarding ==='

-- Simulate a complete tenant onboarding process
DO $$
DECLARE
    new_company_id UUID;
    admin_id UUID;
    user1_id UUID;
    user2_id UUID;
BEGIN
    -- Step 1: Create tenant
    RAISE NOTICE '1. Creating tenant...';
    new_company_id := create_tenant(
        'New Company Inc',
        'new-company',
        'admin@newco.com',
        'newco_admin'
    );

    -- Step 2: Configure tenant settings
    RAISE NOTICE '2. Configuring tenant...';
    PERFORM update_tenant(
        new_company_id,
        NULL,
        NULL,
        '{
            "plan": "starter",
            "max_users": 10,
            "onboarding_completed": false,
            "features": {
                "api_access": false,
                "custom_domain": false
            }
        }'::jsonb
    );

    -- Step 3: Set up initial users
    RAISE NOTICE '3. Adding team members...';

    INSERT INTO core.users (tenant_id, email, username, status)
    VALUES (new_company_id, 'dev@newco.com', 'developer', 'active')
    RETURNING id INTO user1_id;

    INSERT INTO core.users (tenant_id, email, username, status)
    VALUES (new_company_id, 'sales@newco.com', 'sales_rep', 'active')
    RETURNING id INTO user2_id;

    PERFORM add_user_to_tenant(user1_id, new_company_id, 'admin');
    PERFORM add_user_to_tenant(user2_id, new_company_id, 'member');

    -- Step 4: Create initial data
    RAISE NOTICE '4. Creating initial data...';
    PERFORM set_current_tenant(new_company_id);

    INSERT INTO tenant.sample_data (tenant_id, name, description, category)
    VALUES
        (new_company_id, 'Welcome Guide', 'Getting started with Taifabase', 'documentation'),
        (new_company_id, 'Sample Dashboard', 'Example dashboard configuration', 'templates');

    -- Step 5: Mark onboarding complete
    RAISE NOTICE '5. Completing onboarding...';
    PERFORM update_tenant(
        new_company_id,
        NULL,
        NULL,
        '{"onboarding_completed": true}'::jsonb
    );

    RAISE NOTICE 'Onboarding complete for tenant: %', new_company_id;
END $$;

-- ==================================================
-- EXAMPLE 15: Audit Trail Query
-- ==================================================

\echo ''
\echo '=== EXAMPLE 15: View Audit Trail ==='

-- View recent tenant operations
SELECT
    created_at,
    operation,
    performed_by,
    details->>'tenant_name' as tenant_name,
    details->>'tenant_slug' as tenant_slug,
    CASE
        WHEN operation = 'CREATE_TENANT' THEN 'Tenant created'
        WHEN operation = 'UPDATE_TENANT' THEN 'Tenant updated'
        WHEN operation = 'DELETE_TENANT' THEN 'Tenant deleted'
        WHEN operation = 'ADD_USER_TO_TENANT' THEN 'User added'
        WHEN operation = 'REMOVE_USER_FROM_TENANT' THEN 'User removed'
        ELSE operation
    END as description
FROM audit.tenant_operations
ORDER BY created_at DESC
LIMIT 20;

-- View all operations for a specific tenant
SELECT
    created_at,
    operation,
    performed_by,
    details
FROM audit.tenant_operations
WHERE tenant_id = :new_tenant_id::UUID
ORDER BY created_at;

-- ==================================================
-- EXAMPLE 16: Tenant User Statistics
-- ==================================================

\echo ''
\echo '=== EXAMPLE 16: Tenant Statistics ==='

-- Get user count by role for each tenant
SELECT
    t.name as tenant_name,
    t.status,
    COUNT(tu.id) as total_users,
    COUNT(CASE WHEN tu.role = 'owner' THEN 1 END) as owners,
    COUNT(CASE WHEN tu.role = 'admin' THEN 1 END) as admins,
    COUNT(CASE WHEN tu.role = 'member' THEN 1 END) as members,
    COUNT(CASE WHEN tu.role = 'readonly' THEN 1 END) as readonly_users
FROM core.tenants t
LEFT JOIN core.tenant_users tu ON t.id = tu.tenant_id
WHERE t.status = 'active'
GROUP BY t.id, t.name, t.status
ORDER BY total_users DESC;

-- ==================================================
-- EXAMPLE 17: Settings Management
-- ==================================================

\echo ''
\echo '=== EXAMPLE 17: Advanced Settings Management ==='

-- Add nested settings
SELECT update_tenant(
    :new_tenant_id::UUID,
    NULL,
    NULL,
    '{
        "notifications": {
            "email": {
                "enabled": true,
                "digest": "daily"
            },
            "slack": {
                "enabled": false,
                "webhook": null
            }
        },
        "security": {
            "password_policy": {
                "min_length": 12,
                "require_special_chars": true,
                "require_numbers": true
            },
            "session_timeout_minutes": 60,
            "mfa_required": false
        }
    }'::jsonb
);

-- Update specific nested setting
SELECT update_tenant(
    :new_tenant_id::UUID,
    NULL,
    NULL,
    '{"security": {"mfa_required": true}}'::jsonb
);

-- Query specific setting
SELECT
    name,
    settings->'security'->>'mfa_required' as mfa_enabled,
    settings->'notifications'->'email'->>'digest' as email_digest
FROM core.tenants
WHERE id = :new_tenant_id::UUID;

-- ==================================================
-- EXAMPLE 18: Bulk Operations
-- ==================================================

\echo ''
\echo '=== EXAMPLE 18: Bulk Operations ==='

-- Suspend all tenants with overdue payments (example)
DO $$
DECLARE
    tenant RECORD;
BEGIN
    FOR tenant IN
        SELECT id, name
        FROM core.tenants
        WHERE status = 'active'
        AND settings->>'payment_status' = 'overdue'
    LOOP
        PERFORM update_tenant(tenant.id, NULL, 'suspended', NULL);
        RAISE NOTICE 'Suspended tenant: %', tenant.name;
    END LOOP;
END $$;

-- Reactivate specific tenants
DO $$
DECLARE
    tenant_slugs TEXT[] := ARRAY['acme-corp', 'techstart', 'global-innovations'];
    slug TEXT;
BEGIN
    FOREACH slug IN ARRAY tenant_slugs
    LOOP
        UPDATE core.tenants SET status = 'active' WHERE slug = slug;
        RAISE NOTICE 'Reactivated tenant: %', slug;
    END LOOP;
END $$;

-- ==================================================
-- EXAMPLE 19: Error Handling
-- ==================================================

\echo ''
\echo '=== EXAMPLE 19: Error Handling Examples ==='

-- Example: Handle duplicate slug error
DO $$
BEGIN
    PERFORM create_tenant('Duplicate Test', 'acme-corp', 'test@test.com', 'test');
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Caught expected error: %', SQLERRM;
END $$;

-- Example: Handle invalid status
DO $$
BEGIN
    PERFORM update_tenant(:new_tenant_id::UUID, NULL, 'invalid_status', NULL);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Caught expected error: %', SQLERRM;
END $$;

-- ==================================================
-- EXAMPLE 20: Integration with Application
-- ==================================================

\echo ''
\echo '=== EXAMPLE 20: Application Integration Pattern ==='

-- This is how you might call these functions from an application

-- Example Node.js/JavaScript pattern:
\echo 'JavaScript/Node.js pattern:'
\echo '```javascript'
\echo '// Create tenant'
\echo 'const { rows } = await pool.query('
\echo '  "SELECT create_tenant($1, $2, $3, $4) as tenant_id",'
\echo '  [name, slug, adminEmail, adminUsername]'
\echo ');'
\echo ''
\echo '// Update tenant settings'
\echo 'await pool.query('
\echo '  "SELECT update_tenant($1, NULL, NULL, $2)",'
\echo '  [tenantId, JSON.stringify(settings)]'
\echo ');'
\echo ''
\echo '// List user tenants'
\echo 'const { rows } = await pool.query('
\echo '  "SELECT * FROM list_user_tenants($1)",'
\echo '  [userId]'
\echo ');'
\echo '```'

\echo ''
\echo '=========================================='
\echo 'END OF EXAMPLES'
\echo '=========================================='
\echo ''
\echo 'For more information, see:'
\echo '  - API Documentation: docs/tenant-management-api.md'
\echo '  - Test Suite: database/testing/scripts/test_tenant_management.sql'
\echo '  - Function Definitions: database/scripts/04_tenant_management_functions.sql'
