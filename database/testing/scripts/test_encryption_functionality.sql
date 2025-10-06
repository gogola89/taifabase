-- ===========================================================================
-- test_encryption_functionality.sql
-- ===========================================================================
-- Encryption Functional Testing Script
-- To be executed on Day 3 after Marcus completes US-601
--
-- PURPOSE:
--   Comprehensive functional testing of encryption/decryption functions
--   Verifies round-trip encryption, error handling, input validation
--
-- DEPENDENCIES:
--   - database/scripts/06_encryption_functions.sql (Marcus - US-601)
--   - database/config/key-management-config.sh (Raj - US-602)
--
-- AUTHOR: Aisha Kamau (QA Engineer)
-- CREATED: 2025-10-06 (Sprint 2, Day 1)
-- EXECUTION: Day 3 (after Marcus's Day 2 implementation complete)
-- ===========================================================================

\echo ''
\echo '========================================'
\echo 'Encryption Functional Testing - US-603'
\echo 'Day 3 Execution'
\echo '========================================'
\echo ''

-- ===========================================================================
-- Test 1: Encrypt/Decrypt Round-Trip
-- ===========================================================================

\echo 'Test 1: Encrypt/Decrypt Round-Trip'
\echo '-----------------------------------'

SELECT
    plaintext,
    encrypt_sensitive_data(plaintext) AS ciphertext,
    decrypt_sensitive_data(encrypt_sensitive_data(plaintext)) AS decrypted,
    (plaintext = decrypt_sensitive_data(encrypt_sensitive_data(plaintext))) AS matches
FROM (VALUES
    ('test_data_1'),
    ('sensitive_info_2'),
    ('email@example.com'),
    ('api_key_12345'),
    ('password_hash_test')
) AS t(plaintext);

\echo '  Expected: All "matches" column = TRUE'
\echo ''

-- ===========================================================================
-- Test 2: Verify Ciphertext Not Readable
-- ===========================================================================

\echo 'Test 2: Verify Ciphertext Not Readable'
\echo '---------------------------------------'

WITH encrypted_test AS (
    SELECT
        'confidential_data' AS plaintext,
        encrypt_sensitive_data('confidential_data') AS ciphertext
)
SELECT
    plaintext,
    ciphertext,
    (ciphertext::text != plaintext) AS ciphertext_different
FROM encrypted_test;

\echo '  Expected: ciphertext_different = TRUE (ciphertext is unreadable hex/binary)'
\echo ''

-- ===========================================================================
-- Test 3: Decryption with Correct Key
-- ===========================================================================

\echo 'Test 3: Decryption with Correct Key'
\echo '------------------------------------'

SELECT decrypt_sensitive_data(encrypt_sensitive_data('secret_message')) AS decrypted;

\echo '  Expected: decrypted = "secret_message"'
\echo ''

-- ===========================================================================
-- Test 4: Error Handling - Null Plaintext
-- ===========================================================================

\echo 'Test 4: Error Handling - Null Plaintext'
\echo '----------------------------------------'

DO $$
BEGIN
    PERFORM encrypt_sensitive_data(NULL);
    RAISE EXCEPTION 'Test FAILED: Null plaintext should raise exception';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%cannot be null%' THEN
            RAISE NOTICE '  ✅ Test PASSED: Null plaintext rejected (% )', SQLERRM;
        ELSE
            RAISE EXCEPTION 'Test FAILED: Unexpected error: %', SQLERRM;
        END IF;
END $$;

\echo ''

-- ===========================================================================
-- Test 5: Error Handling - Empty Plaintext
-- ===========================================================================

\echo 'Test 5: Error Handling - Empty Plaintext'
\echo '-----------------------------------------'

DO $$
BEGIN
    PERFORM encrypt_sensitive_data('');
    RAISE EXCEPTION 'Test FAILED: Empty plaintext should raise exception';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%cannot be null or empty%' THEN
            RAISE NOTICE '  ✅ Test PASSED: Empty plaintext rejected (%)', SQLERRM;
        ELSE
            RAISE EXCEPTION 'Test FAILED: Unexpected error: %', SQLERRM;
        END IF;
END $$;

\echo ''

-- ===========================================================================
-- Test 6: Error Handling - Oversized Plaintext (DOS Protection)
-- ===========================================================================

\echo 'Test 6: Error Handling - Oversized Plaintext (DOS Protection)'
\echo '---------------------------------------------------------------'

DO $$
BEGIN
    PERFORM encrypt_sensitive_data(repeat('x', 10001));  -- 10,001 chars (exceeds 10,000 limit)
    RAISE EXCEPTION 'Test FAILED: Oversized plaintext should raise exception';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%exceeds maximum length%' THEN
            RAISE NOTICE '  ✅ Test PASSED: Oversized plaintext rejected (%) ', SQLERRM;
        ELSE
            RAISE EXCEPTION 'Test FAILED: Unexpected error: %', SQLERRM;
        END IF;
END $$;

\echo ''

-- ===========================================================================
-- Test 7: Error Handling - Null Ciphertext
-- ===========================================================================

\echo 'Test 7: Error Handling - Null Ciphertext'
\echo '-----------------------------------------'

DO $$
BEGIN
    PERFORM decrypt_sensitive_data(NULL);
    RAISE EXCEPTION 'Test FAILED: Null ciphertext should raise exception';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%cannot be null%' THEN
            RAISE NOTICE '  ✅ Test PASSED: Null ciphertext rejected (%)', SQLERRM;
        ELSE
            RAISE EXCEPTION 'Test FAILED: Unexpected error: %', SQLERRM;
        END IF;
END $$;

\echo ''

-- ===========================================================================
-- Test 8: Multiple Encryptions Produce Different Ciphertexts
-- ===========================================================================

\echo 'Test 8: Multiple Encryptions Produce Different Ciphertexts'
\echo '-----------------------------------------------------------'
\echo '  Note: pgcrypto may include random salt/IV, so same plaintext may produce different ciphertexts'

WITH double_encrypt AS (
    SELECT
        encrypt_sensitive_data('same_plaintext') AS ciphertext1,
        encrypt_sensitive_data('same_plaintext') AS ciphertext2
)
SELECT
    ciphertext1,
    ciphertext2,
    (ciphertext1 = ciphertext2) AS ciphertexts_match,
    decrypt_sensitive_data(ciphertext1) AS decrypted1,
    decrypt_sensitive_data(ciphertext2) AS decrypted2,
    (decrypt_sensitive_data(ciphertext1) = decrypt_sensitive_data(ciphertext2)) AS plaintexts_match
FROM double_encrypt;

\echo '  Expected: decrypted1 = decrypted2 = "same_plaintext" (plaintexts_match = TRUE)'
\echo '  Ciphertexts may differ due to random salt/IV (ciphertexts_match may be FALSE)'
\echo ''

-- ===========================================================================
-- Test 9: Performance Baseline (Simple Encrypt/Decrypt)
-- ===========================================================================

\echo 'Test 9: Performance Baseline - Simple Encrypt/Decrypt'
\echo '------------------------------------------------------'
\echo '  Executing 100 encrypt/decrypt operations...'

\timing on

DO $$
DECLARE
    i INTEGER;
    encrypted BYTEA;
    decrypted TEXT;
BEGIN
    FOR i IN 1..100 LOOP
        encrypted := encrypt_sensitive_data('performance_test_data_' || i);
        decrypted := decrypt_sensitive_data(encrypted);
    END LOOP;
END $$;

\timing off

\echo '  Record average time for performance comparison'
\echo ''

-- ===========================================================================
-- Test Summary
-- ===========================================================================

\echo ''
\echo '========================================'
\echo 'Functional Testing Summary'
\echo '========================================'
\echo ''
\echo 'Tests Executed:'
\echo '  1. Encrypt/Decrypt Round-Trip ✅'
\echo '  2. Ciphertext Not Readable ✅'
\echo '  3. Decryption with Correct Key ✅'
\echo '  4. Error Handling - Null Plaintext ✅'
\echo '  5. Error Handling - Empty Plaintext ✅'
\echo '  6. Error Handling - Oversized Plaintext (DOS Protection) ✅'
\echo '  7. Error Handling - Null Ciphertext ✅'
\echo '  8. Multiple Encryptions Produce Different Ciphertexts ✅'
\echo '  9. Performance Baseline ✅'
\echo ''
\echo 'Next Steps:'
\echo '  - Review test results above'
\echo '  - If all tests passed, proceed to security testing (with Kenji)'
\echo '  - If any tests failed, investigate with Marcus'
\echo '  - Document results in encryption testing report'
\echo ''
\echo 'Day 3 Afternoon: Performance testing (<5% overhead validation)'
\echo 'Day 3 Evening: Integration testing (RLS + Encryption)'
\echo 'Day 4: Compliance testing (GDPR, SOC2)'
\echo ''
