-- Test Data Generation for Performance Baseline Testing
-- This script creates sample data for performance testing and RLS validation
-- Created by: Marcus Rodriguez - Backend Engineer
-- Date: 2025-10-03

-- Insert test tenants
INSERT INTO core.tenants (id, name, slug) VALUES 
    ('11111111-1111-1111-1111-111111111111', 'Acme Corporation', 'acme-corp'),
    ('22222222-2222-2222-2222-222222222222', 'TechStart Inc', 'techstart-inc'),
    ('33333333-3333-3333-3333-333333333333', 'Global Enterprises', 'global-enterprises'),
    ('44444444-4444-4444-4444-444444444444', 'Innovation Labs', 'innovation-labs'),
    ('55555555-5555-5555-5555-555555555555', 'Cloud Solutions', 'cloud-solutions')
ON CONFLICT (id) DO NOTHING;

-- Insert test users for each tenant
INSERT INTO core.users (tenant_id, email, username) VALUES 
    -- Acme Corporation users
    ('11111111-1111-1111-1111-111111111111', 'admin@acme.com', 'acme_admin'),
    ('11111111-1111-1111-1111-111111111111', 'user1@acme.com', 'acme_user1'),
    ('11111111-1111-1111-1111-111111111111', 'user2@acme.com', 'acme_user2'),
    
    -- TechStart Inc users
    ('22222222-2222-2222-2222-222222222222', 'admin@techstart.com', 'tech_admin'),
    ('22222222-2222-2222-2222-222222222222', 'dev@techstart.com', 'tech_dev'),
    
    -- Global Enterprises users
    ('33333333-3333-3333-3333-333333333333', 'admin@global.com', 'global_admin'),
    ('33333333-3333-3333-3333-333333333333', 'manager@global.com', 'global_manager'),
    ('33333333-3333-3333-3333-333333333333', 'user@global.com', 'global_user'),
    
    -- Innovation Labs users
    ('44444444-4444-4444-4444-444444444444', 'lead@innovation.com', 'innovation_lead'),
    
    -- Cloud Solutions users
    ('55555555-5555-5555-5555-555555555555', 'ops@cloudsol.com', 'cloud_ops')
ON CONFLICT (tenant_id, email) DO NOTHING;

-- Generate sample data for performance testing
-- This will create different volumes of data per tenant to test RLS performance

-- Function to generate sample data
CREATE OR REPLACE FUNCTION generate_sample_data(tenant_uuid UUID, record_count INTEGER)
RETURNS VOID AS $$
DECLARE
    i INTEGER;
    categories TEXT[] := ARRAY['finance', 'marketing', 'operations', 'hr', 'it', 'sales'];
    sample_tags TEXT[];
BEGIN
    FOR i IN 1..record_count LOOP
        sample_tags := ARRAY['tag' || (i % 5 + 1)::TEXT, 'category_' || categories[i % 6 + 1]];
        
        INSERT INTO tenant.sample_data (
            tenant_id,
            name,
            description,
            value,
            category,
            tags,
            metadata,
            created_by
        ) VALUES (
            tenant_uuid,
            'Sample Record ' || i::TEXT || ' for ' || tenant_uuid::TEXT,
            'This is a test description for record ' || i::TEXT || '. It contains sample text to test performance.',
            (random() * 10000)::NUMERIC(10,2),
            categories[i % 6 + 1],
            sample_tags,
            jsonb_build_object(
                'test_field_1', 'value_' || i::TEXT,
                'test_field_2', random() * 100,
                'test_field_3', (i % 10 = 0),
                'nested', jsonb_build_object('level', 2, 'data', 'nested_' || i::TEXT)
            ),
            (SELECT id FROM core.users WHERE tenant_id = tenant_uuid LIMIT 1)
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Generate different volumes of test data per tenant for performance testing
SELECT generate_sample_data('11111111-1111-1111-1111-111111111111', 10000); -- Acme Corp - Large dataset
SELECT generate_sample_data('22222222-2222-2222-2222-222222222222', 5000);  -- TechStart - Medium dataset
SELECT generate_sample_data('33333333-3333-3333-3333-333333333333', 7500);  -- Global - Large-medium dataset
SELECT generate_sample_data('44444444-4444-4444-4444-444444444444', 2000);  -- Innovation - Small dataset
SELECT generate_sample_data('55555555-5555-5555-5555-555555555555', 1000);  -- Cloud Solutions - Very small dataset

-- Clean up the function
DROP FUNCTION generate_sample_data(UUID, INTEGER);

-- Create summary view for testing
CREATE OR REPLACE VIEW tenant.data_summary AS
SELECT 
    t.name as tenant_name,
    t.slug as tenant_slug,
    COUNT(sd.id) as record_count,
    AVG(sd.value) as avg_value,
    MIN(sd.created_at) as first_record,
    MAX(sd.created_at) as last_record
FROM core.tenants t
LEFT JOIN tenant.sample_data sd ON t.id = sd.tenant_id
GROUP BY t.id, t.name, t.slug
ORDER BY record_count DESC;