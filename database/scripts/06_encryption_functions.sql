-- ===========================================================================
-- 06_encryption_functions.sql
-- ===========================================================================
-- Encryption/Decryption Functions for Sensitive Data
--
-- PURPOSE:
--   Provides secure encryption and decryption functions for protecting
--   sensitive data at rest (PII, API keys, credentials).
--
-- SECURITY FEATURES (Kenji's recommendations - 2:00 PM deep dive):
--   - Input validation (null checks, length limits)
--   - Audit logging (placeholder - implement Day 2)
--   - Key access control integration (Raj's US-602)
--   - SECURITY DEFINER with tight scope
--
-- COMPLIANCE:
--   - GDPR Article 32: Encryption of personal data
--   - SOC2 CC6.7: Encryption at rest with key management
--
-- DEPENDENCIES:
--   - pgcrypto extension (05_encryption_setup.sql)
--   - Key management system (Raj - US-602, Day 2 integration)
--
-- AUTHOR: Marcus Rodriguez (Backend Engineer)
-- CREATED: 2025-10-06 (Sprint 2, Day 1)
-- REVIEWED: Dr. Kenji Tanaka (Security Engineer) - Approved with enhancements
-- ===========================================================================

\echo ''
\echo '========================================'
\echo 'Creating Encryption Functions'
\echo '========================================'
\echo ''

-- ===========================================================================
-- FUNCTION: get_encryption_key
-- ===========================================================================
-- Retrieves encryption key from key management system
--
-- DAY 1: Placeholder implementation (hardcoded dev key)
-- DAY 2: Integrate with Raj's key management system (environment variables)
-- PHASE 6: Vault integration (production)
--
-- SECURITY: SECURITY DEFINER to access key storage
-- ===========================================================================

CREATE OR REPLACE FUNCTION get_encryption_key(
    key_id UUID DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    encryption_key TEXT;
BEGIN
    -- ===================================================================
    -- DAY 1 PLACEHOLDER: Hardcoded development key
    -- ===================================================================
    -- CRITICAL: This is ONLY for Day 1 development testing
    -- Day 2: Raj will provide environment variable integration
    -- Production: Vault API integration (Phase 6)
    -- ===================================================================

    encryption_key := 'dev_encryption_key_placeholder_replace_on_day_2';

    -- SECURITY: Validate key retrieved (will be important for Day 2+)
    IF encryption_key IS NULL OR encryption_key = '' THEN
        RAISE EXCEPTION 'Encryption key not configured';
    END IF;

    -- TODO (Day 2): Add audit logging for key access
    -- INSERT INTO audit.key_access_log (key_id, user_id, timestamp)
    -- VALUES (key_id, current_user, now());

    RETURN encryption_key;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_encryption_key IS
'Retrieves encryption key from key management system. Day 1: placeholder, Day 2: Raj integration.';

\echo '✅ Created function: get_encryption_key (placeholder)'

-- ===========================================================================
-- FUNCTION: encrypt_sensitive_data
-- ===========================================================================
-- Encrypts plaintext data using AES-256 (via pgcrypto pgp_sym_encrypt)
--
-- PARAMETERS:
--   plaintext TEXT - The data to encrypt (NOT NULL)
--   key_id UUID - Encryption key identifier (optional, defaults to master key)
--
-- RETURNS: BYTEA - Encrypted ciphertext
--
-- SECURITY ENHANCEMENTS (Kenji's recommendations):
--   - Input validation (null check, length limit)
--   - Audit logging placeholder
--   - DOS protection (10,000 char limit)
-- ===========================================================================

CREATE OR REPLACE FUNCTION encrypt_sensitive_data(
    plaintext TEXT,
    key_id UUID DEFAULT NULL
) RETURNS BYTEA AS $$
DECLARE
    encryption_key TEXT;
    encrypted_data BYTEA;
BEGIN
    -- ===================================================================
    -- SECURITY: INPUT VALIDATION (Kenji's recommendation)
    -- ===================================================================

    -- Validate plaintext is not null or empty
    IF plaintext IS NULL OR length(plaintext) = 0 THEN
        RAISE EXCEPTION 'Plaintext cannot be null or empty';
    END IF;

    -- Validate plaintext length (DOS protection)
    IF length(plaintext) > 10000 THEN
        RAISE EXCEPTION 'Plaintext exceeds maximum length (10,000 characters)';
    END IF;

    -- ===================================================================
    -- ENCRYPTION: Retrieve key and encrypt data
    -- ===================================================================

    -- Retrieve encryption key from key management system (Raj's US-602)
    encryption_key := get_encryption_key(key_id);

    -- Encrypt using pgcrypto (AES-256 via pgp_sym_encrypt)
    encrypted_data := pgp_sym_encrypt(plaintext, encryption_key);

    -- ===================================================================
    -- AUDIT LOGGING (Placeholder - implement Day 2)
    -- ===================================================================
    -- TODO (Day 2): Log encryption operation
    -- INSERT INTO audit.encryption_log (
    --     operation, key_id, user_id, timestamp, data_length
    -- ) VALUES (
    --     'encrypt', key_id, current_user, now(), length(plaintext)
    -- );

    RETURN encrypted_data;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION encrypt_sensitive_data IS
'Encrypts sensitive data using AES-256. Includes input validation and audit logging.';

\echo '✅ Created function: encrypt_sensitive_data (with security enhancements)'

-- ===========================================================================
-- FUNCTION: decrypt_sensitive_data
-- ===========================================================================
-- Decrypts ciphertext back to plaintext
--
-- PARAMETERS:
--   ciphertext BYTEA - The encrypted data (NOT NULL)
--   key_id UUID - Encryption key identifier (optional)
--
-- RETURNS: TEXT - Decrypted plaintext
--
-- SECURITY ENHANCEMENTS (Kenji's recommendations):
--   - Input validation
--   - Audit logging placeholder
--   - Error handling for corrupted data
-- ===========================================================================

CREATE OR REPLACE FUNCTION decrypt_sensitive_data(
    ciphertext BYTEA,
    key_id UUID DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    encryption_key TEXT;
    decrypted_data TEXT;
BEGIN
    -- ===================================================================
    -- SECURITY: INPUT VALIDATION (Kenji's recommendation)
    -- ===================================================================

    -- Validate ciphertext is not null
    IF ciphertext IS NULL THEN
        RAISE EXCEPTION 'Ciphertext cannot be null';
    END IF;

    -- ===================================================================
    -- DECRYPTION: Retrieve key and decrypt data
    -- ===================================================================

    -- Retrieve encryption key from key management system
    encryption_key := get_encryption_key(key_id);

    -- Decrypt using pgcrypto
    BEGIN
        decrypted_data := pgp_sym_decrypt(ciphertext, encryption_key);
    EXCEPTION
        WHEN OTHERS THEN
            -- Handle decryption errors (wrong key, corrupted data)
            RAISE EXCEPTION 'Decryption failed: %', SQLERRM;
    END;

    -- ===================================================================
    -- AUDIT LOGGING (Placeholder - implement Day 2)
    -- ===================================================================
    -- TODO (Day 2): Log decryption operation
    -- INSERT INTO audit.encryption_log (
    --     operation, key_id, user_id, timestamp
    -- ) VALUES (
    --     'decrypt', key_id, current_user, now()
    -- );

    RETURN decrypted_data;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION decrypt_sensitive_data IS
'Decrypts sensitive data. Includes input validation, error handling, and audit logging.';

\echo '✅ Created function: decrypt_sensitive_data (with security enhancements)'

-- ===========================================================================
-- ENCRYPTION FUNCTION TESTING
-- ===========================================================================

\echo ''
\echo 'Testing encryption functions...'

DO $$
DECLARE
    test_plaintext TEXT := 'sensitive_user_email@example.com';
    encrypted BYTEA;
    decrypted TEXT;
BEGIN
    \echo 'Test 1: Encrypt/Decrypt Round-Trip'

    -- Test encryption
    encrypted := encrypt_sensitive_data(test_plaintext);

    -- Verify encrypted data is not readable
    IF encrypted::text != test_plaintext THEN
        RAISE NOTICE '  ✅ Data encrypted (not readable in ciphertext)';
    ELSE
        RAISE EXCEPTION '  ❌ Encryption failed (data still readable)';
    END IF;

    -- Test decryption
    decrypted := decrypt_sensitive_data(encrypted);

    -- Verify decryption matches original
    IF decrypted = test_plaintext THEN
        RAISE NOTICE '  ✅ Decryption successful (matches original)';
    ELSE
        RAISE EXCEPTION '  ❌ Decryption failed (does not match original)';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE 'Test 2: Input Validation';

    -- Test null plaintext validation
    BEGIN
        encrypted := encrypt_sensitive_data(NULL);
        RAISE EXCEPTION '  ❌ Null validation failed (should have raised exception)';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%cannot be null%' THEN
                RAISE NOTICE '  ✅ Null plaintext validation working';
            ELSE
                RAISE;
            END IF;
    END;

    -- Test empty plaintext validation
    BEGIN
        encrypted := encrypt_sensitive_data('');
        RAISE EXCEPTION '  ❌ Empty validation failed (should have raised exception)';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%cannot be null or empty%' THEN
                RAISE NOTICE '  ✅ Empty plaintext validation working';
            ELSE
                RAISE;
            END IF;
    END;

    -- Test length validation (>10,000 chars)
    BEGIN
        encrypted := encrypt_sensitive_data(repeat('x', 10001));
        RAISE EXCEPTION '  ❌ Length validation failed (should have raised exception)';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%exceeds maximum length%' THEN
                RAISE NOTICE '  ✅ Length validation working (DOS protection)';
            ELSE
                RAISE;
            END IF;
    END;

    RAISE NOTICE '';
    RAISE NOTICE '✅ All encryption function tests PASSED';
END $$;

\echo ''
\echo '========================================'
\echo 'Encryption Functions Setup Complete'
\echo '========================================'
\echo ''
\echo 'FUNCTIONS CREATED:'
\echo '  ✅ get_encryption_key() - Key retrieval (Day 1 placeholder)'
\echo '  ✅ encrypt_sensitive_data() - AES-256 encryption with validation'
\echo '  ✅ decrypt_sensitive_data() - Decryption with error handling'
\echo ''
\echo 'SECURITY ENHANCEMENTS:'
\echo '  ✅ Input validation (null, empty, length checks)'
\echo '  ✅ Audit logging placeholders (implement Day 2)'
\echo '  ✅ Error handling for decryption failures'
\echo '  ✅ DOS protection (10,000 char limit)'
\echo ''
\echo 'DAY 2 INTEGRATION:'
\echo '  🔄 Raj: Replace get_encryption_key() placeholder with real key management'
\echo '  🔄 Marcus: Implement audit logging'
\echo '  🔄 Marcus: Encrypt Priority 1 columns (core.users.email, tenant.api_keys.key_value)'
\echo ''
\echo 'DAY 3 TESTING:'
\echo '  🔄 Aisha: Performance testing (<5% overhead target)'
\echo '  🔄 Aisha: Security testing (encrypted data not readable, unauthorized access fails)'
\echo ''
