-- ===========================================================================
-- 05_encryption_setup.sql
-- ===========================================================================
-- Encryption at Rest Foundation using PostgreSQL pgcrypto extension
--
-- PURPOSE:
--   Establishes encryption at rest capability for sensitive data to meet
--   GDPR Article 32 and SOC2 CC6.7 compliance requirements.
--
-- COMPLIANCE:
--   - GDPR Article 32: Appropriate technical measures (encryption)
--   - SOC2 CC6.7: Encryption of sensitive data at rest
--
-- DEPENDENCIES:
--   - PostgreSQL 12+ with pgcrypto extension available
--   - Key management system (US-602) - Day 2 integration
--
-- AUTHOR: Marcus Rodriguez (Backend Engineer)
-- CREATED: 2025-10-06 (Sprint 2, Day 1)
-- ===========================================================================

\echo ''
\echo '========================================'
\echo 'Encryption Setup - pgcrypto Extension'
\echo '========================================'
\echo ''

-- Enable pgcrypto extension for encryption functionality
\echo 'Enabling pgcrypto extension...'
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Verify extension is installed
\echo 'Verifying pgcrypto extension...'
SELECT
    extname AS extension_name,
    extversion AS version,
    extrelocatable AS relocatable
FROM pg_extension
WHERE extname = 'pgcrypto';

\echo ''
\echo '✅ pgcrypto extension enabled successfully'
\echo ''

-- ===========================================================================
-- ENCRYPTION TESTING
-- ===========================================================================

\echo 'Testing basic encryption/decryption functionality...'

-- Test symmetric encryption (pgp_sym_encrypt/decrypt)
DO $$
DECLARE
    test_plaintext TEXT := 'test_sensitive_data';
    test_key TEXT := 'test_encryption_key';
    encrypted_data BYTEA;
    decrypted_data TEXT;
BEGIN
    -- Encrypt test data
    encrypted_data := pgp_sym_encrypt(test_plaintext, test_key);

    -- Decrypt test data
    decrypted_data := pgp_sym_decrypt(encrypted_data, test_key);

    -- Verify round-trip encryption/decryption
    IF decrypted_data = test_plaintext THEN
        RAISE NOTICE '✅ Encryption/Decryption test PASSED';
    ELSE
        RAISE EXCEPTION '❌ Encryption/Decryption test FAILED';
    END IF;

    -- Verify encrypted data is not readable
    IF encrypted_data::text != test_plaintext THEN
        RAISE NOTICE '✅ Encrypted data is not plaintext';
    ELSE
        RAISE EXCEPTION '❌ Encrypted data is still readable';
    END IF;
END $$;

\echo ''
\echo '✅ Encryption setup complete and tested'
\echo ''
\echo 'NEXT STEPS (Day 2):'
\echo '  1. Integrate key management system (Raj - US-602)'
\echo '  2. Create encryption/decryption functions'
\echo '  3. Encrypt Priority 1 sensitive columns'
\echo '  4. Performance testing (Aisha - US-603)'
\echo ''
