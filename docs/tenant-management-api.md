# Tenant Management API Documentation

**Version:** 1.0
**Date:** 2025-10-05
**Author:** Marcus Rodriguez - Backend Engineer
**User Story:** US-102
**Status:** Production Ready

## Overview

The Tenant Management API provides comprehensive functions for managing multi-tenant operations in Taifabase. These SQL functions enable programmatic creation, updating, deletion, and user management for tenants with full Row-Level Security (RLS) integration.

### Key Features

- **Tenant Lifecycle Management**: Create, update, and delete tenants
- **User-Tenant Relationships**: Add/remove users to/from tenants with role management
- **Multi-Tenant Support**: Users can belong to multiple tenants with different roles
- **Security**: All functions are SECURITY DEFINER with comprehensive input validation
- **Audit Logging**: All operations logged to `audit.tenant_operations` table
- **RLS Integration**: Works seamlessly with Day 2 RLS optimizations
- **PgBouncer Compatible**: Designed for transaction pooling environments

---

## Functions Reference

### 1. create_tenant()

Creates a new tenant with an admin user and establishes the initial tenant-user relationship.

#### Signature

```sql
create_tenant(
    tenant_name TEXT,
    tenant_slug TEXT,
    admin_email TEXT,
    admin_username TEXT,
    admin_password_hash TEXT DEFAULT NULL
) RETURNS UUID
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `tenant_name` | TEXT | Yes | Human-readable tenant name (must be unique) |
| `tenant_slug` | TEXT | Yes | URL-safe identifier (lowercase, alphanumeric, hyphens only) |
| `admin_email` | TEXT | Yes | Email address for the tenant admin user |
| `admin_username` | TEXT | Yes | Username for the tenant admin user |
| `admin_password_hash` | TEXT | No | Password hash (for Phase 2 authentication integration) |

#### Returns

- **UUID**: The newly created tenant's ID

#### Behavior

1. Validates all input parameters (non-empty, proper format)
2. Validates slug format (lowercase, alphanumeric, hyphens)
3. Checks for duplicate tenant name or slug
4. Creates tenant record with 'active' status
5. Creates admin user linked to the tenant
6. Creates tenant-user relationship with 'owner' role
7. Logs operation to audit table
8. Returns tenant UUID

#### Exceptions

- `Tenant name cannot be empty`
- `Tenant slug cannot be empty`
- `Admin email cannot be empty`
- `Admin username cannot be empty`
- `Tenant slug must contain only lowercase letters, numbers, and hyphens`
- `Tenant slug already exists: {slug}`
- `Tenant name already exists: {name}`
- `Duplicate tenant or user data detected`

#### Example

```sql
-- Create a new tenant for Acme Corporation
SELECT create_tenant(
    'Acme Corporation',
    'acme-corp',
    'admin@acme.com',
    'acme_admin'
);
-- Returns: a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

#### Performance

- **Average execution time**: ~50ms
- **Database impact**: 3 inserts (tenant, user, tenant_users), 1 audit log
- **Indexes used**: Primary keys, unique constraints on slug and name

---

### 2. update_tenant()

Updates tenant metadata including name, status, and settings. All parameters except tenant UUID are optional.

#### Signature

```sql
update_tenant(
    tenant_uuid UUID,
    new_name TEXT DEFAULT NULL,
    new_status TEXT DEFAULT NULL,
    new_settings JSONB DEFAULT NULL
) RETURNS BOOLEAN
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `tenant_uuid` | UUID | Yes | Tenant ID to update |
| `new_name` | TEXT | No | New tenant name (must be unique if provided) |
| `new_status` | TEXT | No | New status: 'active', 'inactive', or 'suspended' |
| `new_settings` | JSONB | No | Settings to merge with existing settings |

#### Returns

- **BOOLEAN**: `TRUE` on success

#### Behavior

1. Validates tenant exists
2. Validates status value (if provided)
3. Checks for duplicate name (if changing name)
4. Updates specified fields only (others remain unchanged)
5. Merges settings with existing settings (preserves unmodified keys)
6. Updates `updated_at` timestamp
7. Logs changes to audit table with before/after values
8. Returns TRUE

#### Exceptions

- `Tenant not found: {uuid}`
- `Invalid status. Must be: active, inactive, or suspended`
- `Tenant name already exists: {name}`

#### Examples

```sql
-- Update tenant name only
SELECT update_tenant(
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::UUID,
    'Acme Corporation Inc.',
    NULL,
    NULL
);

-- Update status to suspended
SELECT update_tenant(
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::UUID,
    NULL,
    'suspended',
    NULL
);

-- Add or update settings
SELECT update_tenant(
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::UUID,
    NULL,
    NULL,
    '{"max_users": 100, "features": {"api_access": true}}'::jsonb
);

-- Update multiple fields at once
SELECT update_tenant(
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::UUID,
    'New Acme Corp',
    'active',
    '{"plan": "enterprise"}'::jsonb
);
```

#### Performance

- **Average execution time**: ~20ms
- **Database impact**: 1-4 updates (depending on parameters), 1 audit log
- **Indexes used**: Primary key lookup

---

### 3. delete_tenant()

Deletes a tenant with soft delete (default) or hard delete options.

#### Signature

```sql
delete_tenant(
    tenant_uuid UUID,
    hard_delete BOOLEAN DEFAULT FALSE
) RETURNS BOOLEAN
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `tenant_uuid` | UUID | Yes | Tenant ID to delete |
| `hard_delete` | BOOLEAN | No | `FALSE` (default) = soft delete, `TRUE` = permanent deletion |

#### Returns

- **BOOLEAN**: `TRUE` on success

#### Behavior

**Soft Delete (hard_delete = FALSE):**
1. Sets tenant status to 'inactive'
2. Data remains in database (reversible)
3. Logs operation with previous status
4. Users and data are preserved

**Hard Delete (hard_delete = TRUE):**
1. **PERMANENT DELETION** - cannot be undone
2. Logs operation with affected counts BEFORE deletion
3. Deletes tenant record
4. CASCADE deletes: users, tenant_users, sample_data, and all tenant-associated records
5. Raises WARNING about permanent deletion

#### Exceptions

- `Tenant not found: {uuid}`

#### Examples

```sql
-- Soft delete (safe, reversible)
SELECT delete_tenant('a1b2c3d4-e5f6-7890-abcd-ef1234567890'::UUID);

-- Reactivate a soft-deleted tenant
SELECT update_tenant('a1b2c3d4-e5f6-7890-abcd-ef1234567890'::UUID, NULL, 'active', NULL);

-- Hard delete (DANGEROUS - permanent!)
SELECT delete_tenant('a1b2c3d4-e5f6-7890-abcd-ef1234567890'::UUID, TRUE);
```

#### Performance

- **Soft delete**: ~10ms
- **Hard delete**: ~50-200ms (depends on data volume)
- **Database impact**: Soft = 1 update; Hard = CASCADE deletes across multiple tables

#### Security Considerations

- **Hard delete is irreversible** - use with extreme caution
- Recommend requiring additional confirmation in application layer
- Consider data retention policies and compliance requirements (GDPR, SOC2)
- Audit logs are preserved even after hard delete

---

### 4. list_user_tenants()

Returns all tenants a user has access to with their role in each tenant.

#### Signature

```sql
list_user_tenants(
    user_uuid UUID
) RETURNS TABLE(
    tenant_id UUID,
    tenant_name TEXT,
    tenant_slug TEXT,
    tenant_status TEXT,
    user_role TEXT,
    joined_at TIMESTAMP WITH TIME ZONE
)
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `user_uuid` | UUID | Yes | User ID to query |

#### Returns

Table with columns:

| Column | Type | Description |
|--------|------|-------------|
| `tenant_id` | UUID | Tenant's unique identifier |
| `tenant_name` | TEXT | Tenant's display name |
| `tenant_slug` | TEXT | Tenant's URL slug |
| `tenant_status` | TEXT | Current status (active/inactive/suspended) |
| `user_role` | TEXT | User's role in this tenant |
| `joined_at` | TIMESTAMP WITH TIME ZONE | When user was added to tenant |

#### Behavior

1. Validates user exists
2. Queries tenant_users join table
3. Returns all tenants user belongs to
4. Results sorted by tenant name
5. Logs query to audit table

#### Exceptions

- `User not found: {uuid}`

#### Examples

```sql
-- List all tenants for a user
SELECT * FROM list_user_tenants('user-uuid-here'::UUID);

-- Example result:
--  tenant_id                              | tenant_name        | tenant_slug   | tenant_status | user_role | joined_at
-- ----------------------------------------+--------------------+---------------+---------------+-----------+---------------------------
--  a1b2c3d4-e5f6-7890-abcd-ef1234567890  | Acme Corporation   | acme-corp     | active        | owner     | 2025-10-05 10:00:00+00
--  b2c3d4e5-f6a7-8901-bcde-f12345678901  | TechStart Inc      | techstart     | active        | admin     | 2025-10-04 14:30:00+00

-- Use in application to populate tenant switcher
SELECT tenant_id, tenant_name, user_role
FROM list_user_tenants('user-uuid-here'::UUID)
WHERE tenant_status = 'active';
```

#### Performance

- **Average execution time**: ~10ms per tenant
- **Database impact**: 1 join query
- **Indexes used**: tenant_users(user_id), tenants(id)

#### Use Cases

- Multi-tenant user dashboard
- Tenant switcher UI component
- Access control verification
- User permission auditing

---

### 5. add_user_to_tenant()

Adds an existing user to a tenant with a specified role.

#### Signature

```sql
add_user_to_tenant(
    user_uuid UUID,
    tenant_uuid UUID,
    user_role TEXT DEFAULT 'member'
) RETURNS BOOLEAN
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `user_uuid` | UUID | Yes | User ID to add |
| `tenant_uuid` | UUID | Yes | Tenant ID to add user to |
| `user_role` | TEXT | No | Role: 'owner', 'admin', 'member' (default), or 'readonly' |

#### Returns

- **BOOLEAN**: `TRUE` on success

#### Behavior

1. Validates user exists
2. Validates tenant exists and is active
3. Validates role value
4. Checks for existing relationship
5. Creates tenant_users record
6. Logs operation to audit table
7. Returns TRUE

#### Exceptions

- `User not found: {uuid}`
- `Tenant not found: {uuid}`
- `Cannot add users to inactive tenant: {name}`
- `Invalid role. Must be: owner, admin, member, or readonly`
- `User {email} is already a member of tenant {name}`

#### Examples

```sql
-- Add user as member (default role)
SELECT add_user_to_tenant(
    'user-uuid'::UUID,
    'tenant-uuid'::UUID
);

-- Add user as admin
SELECT add_user_to_tenant(
    'user-uuid'::UUID,
    'tenant-uuid'::UUID,
    'admin'
);

-- Add user with readonly access
SELECT add_user_to_tenant(
    'user-uuid'::UUID,
    'tenant-uuid'::UUID,
    'readonly'
);
```

#### Performance

- **Average execution time**: ~20ms
- **Database impact**: 1 insert, 1 audit log
- **Indexes used**: tenant_users unique constraint, user/tenant lookups

#### Role Permissions

| Role | Permissions |
|------|-------------|
| `owner` | Full control, can manage other users, delete tenant |
| `admin` | Manage data and settings, add/remove members |
| `member` | Standard access, create/edit tenant data |
| `readonly` | Read-only access to tenant data |

---

### 6. remove_user_from_tenant()

Removes a user from a tenant (bonus function).

#### Signature

```sql
remove_user_from_tenant(
    user_uuid UUID,
    tenant_uuid UUID
) RETURNS BOOLEAN
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `user_uuid` | UUID | Yes | User ID to remove |
| `tenant_uuid` | UUID | Yes | Tenant ID to remove user from |

#### Returns

- **BOOLEAN**: `TRUE` on success

#### Behavior

1. Validates user-tenant relationship exists
2. Prevents removing the last owner (safety check)
3. Deletes tenant_users record
4. Logs operation to audit table
5. Returns TRUE

#### Exceptions

- `User is not a member of this tenant`
- `Cannot remove the last owner from tenant. Please assign another owner first.`

#### Examples

```sql
-- Remove user from tenant
SELECT remove_user_from_tenant(
    'user-uuid'::UUID,
    'tenant-uuid'::UUID
);
```

#### Performance

- **Average execution time**: ~15ms
- **Database impact**: 1 delete, 1 audit log

#### Safety Features

- **Last Owner Protection**: Cannot remove the last owner to prevent orphaned tenants
- Recommendation: Assign a new owner before removing current owner

---

## Database Schema

### Tables Created/Modified

#### core.tenant_users

Join table for many-to-many user-tenant relationships.

```sql
CREATE TABLE core.tenant_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL DEFAULT 'member',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(tenant_id, user_id)
);
```

**Indexes:**
- `idx_tenant_users_tenant_id` - Efficient tenant user lookups
- `idx_tenant_users_user_id` - Efficient user tenant lookups
- `idx_tenant_users_role` - Role-based queries

#### core.tenants (modified)

Added `settings` column:

```sql
ALTER TABLE core.tenants ADD COLUMN settings JSONB DEFAULT '{}'::jsonb;
```

#### audit.tenant_operations

Audit log for all tenant operations.

```sql
CREATE TABLE audit.tenant_operations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES core.tenants(id) ON DELETE SET NULL,
    operation VARCHAR(50) NOT NULL,
    performed_by VARCHAR(255) NOT NULL,
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

---

## Security Considerations

### SECURITY DEFINER

All functions are marked as `SECURITY DEFINER`, which means they execute with the privileges of the function owner, not the caller. This enables:

1. **Controlled Privilege Escalation**: Users can perform tenant operations without direct table access
2. **Centralized Security Logic**: All validation and authorization in one place
3. **Audit Trail**: All operations logged with the actual user context

### Input Validation

Every function includes comprehensive input validation:

- Non-null and non-empty checks
- Format validation (slug format, email format)
- Value constraints (status values, role values)
- Uniqueness checks (duplicate names, slugs)
- Referential integrity (user exists, tenant exists)

### RLS Integration

Functions work seamlessly with Day 2 RLS optimizations:

- Session variables (`app.current_tenant_id`) remain compatible
- Functions can be called with RLS active
- Tenant isolation maintained throughout operations
- No RLS performance degradation

### Audit Logging

All operations logged to `audit.tenant_operations`:

- **Operation type**: CREATE_TENANT, UPDATE_TENANT, etc.
- **Performed by**: Current database user
- **Details**: JSONB with operation-specific metadata
- **Timestamp**: When operation occurred

Example audit log query:

```sql
-- View recent tenant operations
SELECT
    created_at,
    operation,
    performed_by,
    details->>'tenant_name' as tenant_name,
    details
FROM audit.tenant_operations
ORDER BY created_at DESC
LIMIT 20;
```

---

## Performance Characteristics

### Benchmarks

Tested on development environment with Day 2 optimizations:

| Operation | Average Time | Database Impact |
|-----------|--------------|-----------------|
| create_tenant() | ~50ms | 3 inserts + 1 audit |
| update_tenant() | ~20ms | 1-4 updates + 1 audit |
| delete_tenant() (soft) | ~10ms | 1 update + 1 audit |
| delete_tenant() (hard) | ~50-200ms | CASCADE deletes |
| list_user_tenants() | ~10ms/tenant | 1 join query |
| add_user_to_tenant() | ~20ms | 1 insert + 1 audit |
| remove_user_from_tenant() | ~15ms | 1 delete + 1 audit |

### Optimization Tips

1. **Batch Operations**: For bulk user additions, consider wrapping in a transaction
2. **Index Maintenance**: Ensure indexes on tenant_users table are healthy
3. **Settings Updates**: Use JSONB merge (||) to avoid overwriting settings
4. **Audit Log Cleanup**: Implement retention policy for audit.tenant_operations

---

## Error Handling

All functions use PostgreSQL exception handling:

```sql
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Duplicate tenant or user data detected';
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to create tenant: %', SQLERRM;
```

### Application Layer Integration

Recommended error handling in application code:

```javascript
try {
    const result = await db.query(
        'SELECT create_tenant($1, $2, $3, $4)',
        [name, slug, email, username]
    );
} catch (error) {
    if (error.message.includes('already exists')) {
        // Handle duplicate error
    } else if (error.message.includes('cannot be empty')) {
        // Handle validation error
    } else {
        // Handle unexpected error
    }
}
```

---

## Integration with Phase 2 Authentication

These functions are designed with Phase 2 (Authentication Service) in mind:

### Password Hashing

The `create_tenant()` function accepts an optional `admin_password_hash` parameter:

```sql
-- Phase 2: Create tenant with hashed password
SELECT create_tenant(
    'Acme Corporation',
    'acme-corp',
    'admin@acme.com',
    'acme_admin',
    '$2b$12$...'  -- bcrypt hash from GoTrue
);
```

### Session Management

Functions work with session-based authentication:

```sql
-- Phase 2: Verify user can create tenant
SELECT create_tenant(...);  -- Uses current_user from session
```

### API Gateway Integration

Functions designed to be called via API layer:

```
POST /api/v1/tenants
→ create_tenant() function
→ Returns tenant UUID in JSON response
```

---

## Compliance (GDPR/SOC2)

### GDPR Article 15-22 (Data Subject Rights)

- **Right to Access**: `list_user_tenants()` provides user's tenant access
- **Right to Rectification**: `update_tenant()` allows data correction
- **Right to Erasure**: `delete_tenant(hard_delete=TRUE)` for complete removal
- **Audit Logging**: All operations logged for compliance reporting

### SOC2 CC6.1 (Logical Access Controls)

- Role-based access (owner, admin, member, readonly)
- Audit trail for all tenant operations
- SECURITY DEFINER for controlled privilege escalation

---

## Examples and Use Cases

### Complete Tenant Onboarding Flow

```sql
-- 1. Create tenant
SELECT create_tenant(
    'Acme Corporation',
    'acme-corp',
    'admin@acme.com',
    'acme_admin'
) AS tenant_id \gset

-- 2. Configure tenant settings
SELECT update_tenant(
    :'tenant_id',
    NULL,
    NULL,
    '{"max_users": 50, "plan": "professional", "features": {"api_access": true}}'::jsonb
);

-- 3. Add additional users
-- (First create users in core.users table)
SELECT add_user_to_tenant(
    'user1-uuid'::UUID,
    :'tenant_id',
    'admin'
);

SELECT add_user_to_tenant(
    'user2-uuid'::UUID,
    :'tenant_id',
    'member'
);
```

### Tenant Migration/Transfer

```sql
-- 1. Export tenant data (application logic)
-- 2. Create new tenant
-- 3. Migrate users
-- 4. Soft delete old tenant
SELECT delete_tenant('old-tenant-uuid'::UUID, FALSE);
```

### Multi-Tenant User Dashboard

```sql
-- Get user's accessible tenants for dashboard
SELECT
    tenant_id,
    tenant_name,
    tenant_slug,
    user_role,
    CASE
        WHEN user_role = 'owner' THEN 'Full Access'
        WHEN user_role = 'admin' THEN 'Administrative Access'
        WHEN user_role = 'member' THEN 'Standard Access'
        ELSE 'View Only'
    END as access_level
FROM list_user_tenants('current-user-uuid'::UUID)
WHERE tenant_status = 'active'
ORDER BY user_role, tenant_name;
```

---

## Testing

Comprehensive test suite available at:
`database/testing/scripts/test_tenant_management.sql`

### Test Coverage

- ✅ Valid tenant creation
- ✅ Duplicate slug/name rejection
- ✅ Invalid input validation
- ✅ Tenant updates (name, status, settings)
- ✅ Soft delete and hard delete
- ✅ User-tenant relationship management
- ✅ Role validation
- ✅ Last owner protection
- ✅ RLS integration
- ✅ Performance benchmarks
- ✅ Audit logging verification

Run tests:

```bash
psql -U taifabase_user -d taifabase_dev -f database/testing/scripts/test_tenant_management.sql
```

---

## Future Enhancements (Phase 2+)

1. **Tenant Invitation System**: Invite users by email
2. **Role Permissions Customization**: Granular permission management
3. **Tenant Transfer**: Change ownership between users
4. **Tenant Suspension**: Temporary access suspension
5. **Usage Quotas**: Enforce tenant-level resource limits
6. **Billing Integration**: Link tenants to billing accounts

---

## Support and Documentation

- **Examples**: `database/examples/tenant-management-examples.sql`
- **Tests**: `database/testing/scripts/test_tenant_management.sql`
- **Schema**: `database/scripts/04_tenant_management_functions.sql`

For questions or issues, contact: Marcus Rodriguez - Backend Engineer

---

**Document Version**: 1.0
**Last Updated**: 2025-10-05
**Status**: Production Ready
