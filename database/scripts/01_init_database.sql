-- Taifabase Initial Database Setup
-- This script initializes the basic database structure for multi-tenant architecture
-- Created by: Marcus Rodriguez - Backend Engineer
-- Date: 2025-10-03
-- Purpose: Establish foundation for RLS implementation and performance testing

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Create schemas for organization
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS tenant;
CREATE SCHEMA IF NOT EXISTS audit;

-- Create basic tenant table (foundation for RLS)
CREATE TABLE IF NOT EXISTS core.tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    slug VARCHAR(100) NOT NULL UNIQUE,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create users table for tenant association
CREATE TABLE IF NOT EXISTS core.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    username VARCHAR(100) NOT NULL,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(tenant_id, email),
    UNIQUE(tenant_id, username)
);

-- Create sample data table for testing RLS and performance
CREATE TABLE IF NOT EXISTS tenant.sample_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES core.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    value NUMERIC(10,2),
    category VARCHAR(100),
    tags TEXT[],
    metadata JSONB,
    created_by UUID REFERENCES core.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_tenant_id ON core.users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sample_data_tenant_id ON tenant.sample_data(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sample_data_category ON tenant.sample_data(category);
CREATE INDEX IF NOT EXISTS idx_sample_data_created_at ON tenant.sample_data(created_at);
CREATE INDEX IF NOT EXISTS idx_sample_data_metadata ON tenant.sample_data USING GIN(metadata);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Add triggers for updated_at
CREATE TRIGGER update_tenants_updated_at BEFORE UPDATE ON core.tenants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON core.users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sample_data_updated_at BEFORE UPDATE ON tenant.sample_data
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Grant necessary permissions
GRANT USAGE ON SCHEMA core TO taifabase_user;
GRANT USAGE ON SCHEMA tenant TO taifabase_user;
GRANT USAGE ON SCHEMA audit TO taifabase_user;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA core TO taifabase_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA tenant TO taifabase_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA audit TO taifabase_user;

GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA core TO taifabase_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA tenant TO taifabase_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA audit TO taifabase_user;