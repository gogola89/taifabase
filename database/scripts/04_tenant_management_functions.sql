-- Tenant Management Functions - Phase 1
-- Implements comprehensive tenant lifecycle management API
-- Created by: Marcus Rodriguez - Backend Engineer
-- Date: 2025-10-05
-- Purpose: Provide programmatic tenant creation, updates, deletion, and user management
-- User Story: US-102

-- ==================================================
-- PREREQUISITE: Tenant-Users Join Table
-- ==================================================
-- This table manages many-to-many relationships between users and tenants
-- Required for multi-tenant user management

CREATE TABLE IF NOT EXISTS core.tenant_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member', 'readonly')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(tenant_id, user_id)
);

-- Create indexes for efficient tenant-user queries
CREATE INDEX IF NOT EXISTS idx_tenant_users_tenant_id ON core.tenant_users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_users_user_id ON core.tenant_users(user_id);
CREATE INDEX IF NOT EXISTS idx_tenant_users_role ON core.tenant_users(tenant_id, role);

-- Add trigger for updated_at
CREATE TRIGGER update_tenant_users_updated_at BEFORE UPDATE ON core.tenant_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Add settings column to tenants table if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'core'
        AND table_name = 'tenants'
        AND column_name = 'settings'
    ) THEN
        ALTER TABLE core.tenants ADD COLUMN settings JSONB DEFAULT '{}'::jsonb;
    END IF;
END $$;

-- Create audit log table for tenant operations
CREATE TABLE IF NOT EXISTS audit.tenant_operations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES core.tenants(id) ON DELETE SET NULL,
    operation VARCHAR(50) NOT NULL,
    performed_by VARCHAR(255) NOT NULL,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tenant_operations_tenant_id ON audit.tenant_operations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_operations_created_at ON audit.tenant_operations(created_at DESC);

-- ==================================================
-- FUNCTION 1: create_tenant()
-- ==================================================
-- Creates a new tenant with an admin user
-- Returns the new tenant UUID
-- SECURITY DEFINER: Allows controlled privilege escalation

CREATE OR REPLACE FUNCTION create_tenant(
    tenant_name TEXT,
    tenant_slug TEXT,
    admin_email TEXT,
    admin_username TEXT,
    admin_password_hash TEXT DEFAULT NULL  -- Optional: For Phase 2 auth integration
) RETURNS UUID AS $$
DECLARE
    new_tenant_id UUID;
    new_user_id UUID;
    slug_valid BOOLEAN;
BEGIN
    -- Input validation
    IF tenant_name IS NULL OR trim(tenant_name) = '' THEN
        RAISE EXCEPTION 'Tenant name cannot be empty';
    END IF;

    IF tenant_slug IS NULL OR trim(tenant_slug) = '' THEN
        RAISE EXCEPTION 'Tenant slug cannot be empty';
    END IF;

    IF admin_email IS NULL OR trim(admin_email) = '' THEN
        RAISE EXCEPTION 'Admin email cannot be empty';
    END IF;

    IF admin_username IS NULL OR trim(admin_username) = '' THEN
        RAISE EXCEPTION 'Admin username cannot be empty';
    END IF;

    -- Validate slug format (lowercase, alphanumeric, hyphens only)
    slug_valid := tenant_slug ~ '^[a-z0-9-]+$';
    IF NOT slug_valid THEN
        RAISE EXCEPTION 'Tenant slug must contain only lowercase letters, numbers, and hyphens';
    END IF;

    -- Check for duplicate slug
    IF EXISTS (SELECT 1 FROM core.tenants WHERE slug = tenant_slug) THEN
        RAISE EXCEPTION 'Tenant slug already exists: %', tenant_slug;
    END IF;

    -- Check for duplicate tenant name
    IF EXISTS (SELECT 1 FROM core.tenants WHERE name = tenant_name) THEN
        RAISE EXCEPTION 'Tenant name already exists: %', tenant_name;
    END IF;

    -- Create the tenant
    INSERT INTO core.tenants (name, slug, status, settings)
    VALUES (tenant_name, tenant_slug, 'active', '{}'::jsonb)
    RETURNING id INTO new_tenant_id;

    -- Create the admin user
    INSERT INTO core.users (tenant_id, email, username, status)
    VALUES (new_tenant_id, admin_email, admin_username, 'active')
    RETURNING id INTO new_user_id;

    -- Link admin user to tenant with owner role
    INSERT INTO core.tenant_users (tenant_id, user_id, role)
    VALUES (new_tenant_id, new_user_id, 'owner');

    -- Audit log
    INSERT INTO audit.tenant_operations (tenant_id, operation, performed_by, details)
    VALUES (
        new_tenant_id,
        'CREATE_TENANT',
        current_user,
        jsonb_build_object(
            'tenant_name', tenant_name,
            'tenant_slug', tenant_slug,
            'admin_email', admin_email,
            'admin_username', admin_username
        )
    );

    -- Notification
    RAISE NOTICE 'Tenant created successfully: % (%) with admin user: %',
        tenant_name, new_tenant_id, admin_email;

    RETURN new_tenant_id;

EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Duplicate tenant or user data detected. Please check tenant slug and admin email.';
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to create tenant: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to appropriate roles
GRANT EXECUTE ON FUNCTION create_tenant(TEXT, TEXT, TEXT, TEXT, TEXT) TO admin_user;

-- ==================================================
-- FUNCTION 2: update_tenant()
-- ==================================================
-- Updates tenant metadata and settings
-- Returns true on success

CREATE OR REPLACE FUNCTION update_tenant(
    tenant_uuid UUID,
    new_name TEXT DEFAULT NULL,
    new_status TEXT DEFAULT NULL,
    new_settings JSONB DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    old_values RECORD;
    changes JSONB := '{}'::jsonb;
BEGIN
    -- Validate tenant exists
    SELECT name, status, settings INTO old_values
    FROM core.tenants
    WHERE id = tenant_uuid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tenant not found: %', tenant_uuid;
    END IF;

    -- Validate status if provided
    IF new_status IS NOT NULL AND new_status NOT IN ('active', 'inactive', 'suspended') THEN
        RAISE EXCEPTION 'Invalid status. Must be: active, inactive, or suspended';
    END IF;

    -- Build update query and track changes
    IF new_name IS NOT NULL AND trim(new_name) != '' THEN
        -- Check for duplicate name
        IF EXISTS (SELECT 1 FROM core.tenants WHERE name = new_name AND id != tenant_uuid) THEN
            RAISE EXCEPTION 'Tenant name already exists: %', new_name;
        END IF;

        UPDATE core.tenants SET name = new_name WHERE id = tenant_uuid;
        changes := changes || jsonb_build_object('name', jsonb_build_object('old', old_values.name, 'new', new_name));
    END IF;

    IF new_status IS NOT NULL THEN
        UPDATE core.tenants SET status = new_status WHERE id = tenant_uuid;
        changes := changes || jsonb_build_object('status', jsonb_build_object('old', old_values.status, 'new', new_status));
    END IF;

    IF new_settings IS NOT NULL THEN
        -- Merge settings (preserves existing keys, updates/adds new ones)
        UPDATE core.tenants
        SET settings = COALESCE(settings, '{}'::jsonb) || new_settings
        WHERE id = tenant_uuid;
        changes := changes || jsonb_build_object('settings', jsonb_build_object('old', old_values.settings, 'new', new_settings));
    END IF;

    -- Update timestamp
    UPDATE core.tenants SET updated_at = CURRENT_TIMESTAMP WHERE id = tenant_uuid;

    -- Audit log
    INSERT INTO audit.tenant_operations (tenant_id, operation, performed_by, details)
    VALUES (
        tenant_uuid,
        'UPDATE_TENANT',
        current_user,
        jsonb_build_object('changes', changes)
    );

    RAISE NOTICE 'Tenant updated successfully: %', tenant_uuid;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to update tenant: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_tenant(UUID, TEXT, TEXT, JSONB) TO admin_user;

-- ==================================================
-- FUNCTION 3: delete_tenant()
-- ==================================================
-- Deletes tenant data (soft or hard delete)
-- Soft delete: Sets status to 'inactive' (default, safe)
-- Hard delete: Permanently removes tenant and all associated data (dangerous!)

CREATE OR REPLACE FUNCTION delete_tenant(
    tenant_uuid UUID,
    hard_delete BOOLEAN DEFAULT FALSE
) RETURNS BOOLEAN AS $$
DECLARE
    tenant_info RECORD;
    affected_users INTEGER;
    affected_data INTEGER;
BEGIN
    -- Validate tenant exists
    SELECT id, name, slug, status INTO tenant_info
    FROM core.tenants
    WHERE id = tenant_uuid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tenant not found: %', tenant_uuid;
    END IF;

    -- Get counts for audit logging
    SELECT COUNT(*) INTO affected_users
    FROM core.users
    WHERE tenant_id = tenant_uuid;

    SELECT COUNT(*) INTO affected_data
    FROM tenant.sample_data
    WHERE tenant_id = tenant_uuid;

    IF hard_delete THEN
        -- HARD DELETE: Permanent removal (use with extreme caution!)
        RAISE WARNING 'HARD DELETE requested for tenant: % (%). This will permanently delete % users and % data records.',
            tenant_info.name, tenant_uuid, affected_users, affected_data;

        -- Audit log BEFORE deletion
        INSERT INTO audit.tenant_operations (tenant_id, operation, performed_by, details)
        VALUES (
            tenant_uuid,
            'HARD_DELETE_TENANT',
            current_user,
            jsonb_build_object(
                'tenant_name', tenant_info.name,
                'tenant_slug', tenant_info.slug,
                'affected_users', affected_users,
                'affected_data', affected_data,
                'warning', 'PERMANENT DELETION'
            )
        );

        -- Delete tenant (CASCADE will delete users, tenant_users, sample_data)
        DELETE FROM core.tenants WHERE id = tenant_uuid;

        RAISE NOTICE 'Tenant permanently deleted: % (%)', tenant_info.name, tenant_uuid;

    ELSE
        -- SOFT DELETE: Set status to inactive (safe, reversible)
        UPDATE core.tenants
        SET status = 'inactive', updated_at = CURRENT_TIMESTAMP
        WHERE id = tenant_uuid;

        -- Audit log
        INSERT INTO audit.tenant_operations (tenant_id, operation, performed_by, details)
        VALUES (
            tenant_uuid,
            'SOFT_DELETE_TENANT',
            current_user,
            jsonb_build_object(
                'tenant_name', tenant_info.name,
                'tenant_slug', tenant_info.slug,
                'previous_status', tenant_info.status
            )
        );

        RAISE NOTICE 'Tenant soft-deleted (status set to inactive): % (%)', tenant_info.name, tenant_uuid;
    END IF;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to delete tenant: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION delete_tenant(UUID, BOOLEAN) TO admin_user;

-- ==================================================
-- FUNCTION 4: list_user_tenants()
-- ==================================================
-- Returns all tenants a user has access to with their role
-- Useful for multi-tenant user dashboards

CREATE OR REPLACE FUNCTION list_user_tenants(
    user_uuid UUID
) RETURNS TABLE(
    tenant_id UUID,
    tenant_name TEXT,
    tenant_slug TEXT,
    tenant_status TEXT,
    user_role TEXT,
    joined_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    -- Validate user exists
    IF NOT EXISTS (SELECT 1 FROM core.users WHERE id = user_uuid) THEN
        RAISE EXCEPTION 'User not found: %', user_uuid;
    END IF;

    -- Return tenant list with user roles
    RETURN QUERY
    SELECT
        t.id AS tenant_id,
        t.name AS tenant_name,
        t.slug AS tenant_slug,
        t.status AS tenant_status,
        tu.role AS user_role,
        tu.created_at AS joined_at
    FROM core.tenants t
    INNER JOIN core.tenant_users tu ON t.id = tu.tenant_id
    WHERE tu.user_id = user_uuid
    ORDER BY t.name;

    -- Audit log
    INSERT INTO audit.tenant_operations (tenant_id, operation, performed_by, details)
    VALUES (
        NULL,  -- Operation not specific to one tenant
        'LIST_USER_TENANTS',
        current_user,
        jsonb_build_object('user_id', user_uuid)
    );

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to list user tenants: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION list_user_tenants(UUID) TO tenant_user, admin_user;

-- ==================================================
-- FUNCTION 5: add_user_to_tenant()
-- ==================================================
-- Adds an existing user to a tenant with specified role
-- Creates the user-tenant relationship

CREATE OR REPLACE FUNCTION add_user_to_tenant(
    user_uuid UUID,
    tenant_uuid UUID,
    user_role TEXT DEFAULT 'member'
) RETURNS BOOLEAN AS $$
DECLARE
    user_info RECORD;
    tenant_info RECORD;
BEGIN
    -- Validate user exists
    SELECT id, email, username INTO user_info
    FROM core.users
    WHERE id = user_uuid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found: %', user_uuid;
    END IF;

    -- Validate tenant exists and is active
    SELECT id, name, status INTO tenant_info
    FROM core.tenants
    WHERE id = tenant_uuid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tenant not found: %', tenant_uuid;
    END IF;

    IF tenant_info.status != 'active' THEN
        RAISE EXCEPTION 'Cannot add users to inactive tenant: %', tenant_info.name;
    END IF;

    -- Validate role
    IF user_role NOT IN ('owner', 'admin', 'member', 'readonly') THEN
        RAISE EXCEPTION 'Invalid role. Must be: owner, admin, member, or readonly';
    END IF;

    -- Check if relationship already exists
    IF EXISTS (SELECT 1 FROM core.tenant_users WHERE user_id = user_uuid AND tenant_id = tenant_uuid) THEN
        RAISE EXCEPTION 'User % is already a member of tenant %', user_info.email, tenant_info.name;
    END IF;

    -- Create user-tenant relationship
    INSERT INTO core.tenant_users (tenant_id, user_id, role)
    VALUES (tenant_uuid, user_uuid, user_role);

    -- Audit log
    INSERT INTO audit.tenant_operations (tenant_id, operation, performed_by, details)
    VALUES (
        tenant_uuid,
        'ADD_USER_TO_TENANT',
        current_user,
        jsonb_build_object(
            'user_id', user_uuid,
            'user_email', user_info.email,
            'role', user_role
        )
    );

    RAISE NOTICE 'User % added to tenant % with role: %', user_info.email, tenant_info.name, user_role;

    RETURN TRUE;

EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'User is already a member of this tenant';
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to add user to tenant: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION add_user_to_tenant(UUID, UUID, TEXT) TO admin_user;

-- ==================================================
-- BONUS FUNCTION: remove_user_from_tenant()
-- ==================================================
-- Removes a user from a tenant
-- Useful for user offboarding

CREATE OR REPLACE FUNCTION remove_user_from_tenant(
    user_uuid UUID,
    tenant_uuid UUID
) RETURNS BOOLEAN AS $$
DECLARE
    user_info RECORD;
    tenant_info RECORD;
    user_role TEXT;
BEGIN
    -- Validate relationship exists
    SELECT role INTO user_role
    FROM core.tenant_users
    WHERE user_id = user_uuid AND tenant_id = tenant_uuid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User is not a member of this tenant';
    END IF;

    -- Get user and tenant info for audit log
    SELECT email INTO user_info FROM core.users WHERE id = user_uuid;
    SELECT name INTO tenant_info FROM core.tenants WHERE id = tenant_uuid;

    -- Prevent removing the last owner
    IF user_role = 'owner' THEN
        IF (SELECT COUNT(*) FROM core.tenant_users WHERE tenant_id = tenant_uuid AND role = 'owner') = 1 THEN
            RAISE EXCEPTION 'Cannot remove the last owner from tenant. Please assign another owner first.';
        END IF;
    END IF;

    -- Remove user-tenant relationship
    DELETE FROM core.tenant_users
    WHERE user_id = user_uuid AND tenant_id = tenant_uuid;

    -- Audit log
    INSERT INTO audit.tenant_operations (tenant_id, operation, performed_by, details)
    VALUES (
        tenant_uuid,
        'REMOVE_USER_FROM_TENANT',
        current_user,
        jsonb_build_object(
            'user_id', user_uuid,
            'user_email', user_info.email,
            'removed_role', user_role
        )
    );

    RAISE NOTICE 'User % removed from tenant %', user_info.email, tenant_info.name;

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to remove user from tenant: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION remove_user_from_tenant(UUID, UUID) TO admin_user;

-- ==================================================
-- VERIFICATION QUERIES
-- ==================================================

\echo '=== TENANT MANAGEMENT FUNCTIONS CREATED ==='

-- List all tenant management functions
SELECT
    routine_name,
    routine_type,
    data_type as return_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN (
    'create_tenant',
    'update_tenant',
    'delete_tenant',
    'list_user_tenants',
    'add_user_to_tenant',
    'remove_user_from_tenant'
)
ORDER BY routine_name;

\echo '=== TENANT_USERS TABLE STRUCTURE ==='

SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'core'
AND table_name = 'tenant_users'
ORDER BY ordinal_position;

\echo '=== TENANT MANAGEMENT SETUP COMPLETE ==='
\echo 'Available functions:'
\echo '  1. create_tenant(name, slug, admin_email, admin_username, [password_hash])'
\echo '  2. update_tenant(tenant_id, [name], [status], [settings])'
\echo '  3. delete_tenant(tenant_id, [hard_delete])'
\echo '  4. list_user_tenants(user_id)'
\echo '  5. add_user_to_tenant(user_id, tenant_id, [role])'
\echo '  6. remove_user_from_tenant(user_id, tenant_id)'
\echo ''
\echo 'Next steps:'
\echo '  1. Run test suite: database/testing/scripts/test_tenant_management.sql'
\echo '  2. Review API docs: docs/tenant-management-api.md'
\echo '  3. Check examples: database/examples/tenant-management-examples.sql'
