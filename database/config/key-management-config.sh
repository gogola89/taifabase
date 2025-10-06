#!/bin/bash
# ===========================================================================
# key-management-config.sh
# ===========================================================================
# Development Key Management Configuration
#
# PURPOSE:
#   Provides encryption key management configuration for development environment.
#   Production environments MUST use HashiCorp Vault or AWS Secrets Manager.
#
# USAGE:
#   source database/config/key-management-config.sh
#
# SECURITY WARNING:
#   This is for DEVELOPMENT ONLY. Never use these settings in production.
#   Production requires HashiCorp Vault or equivalent secrets management.
#
# COMPLIANCE:
#   - SOC2 CC6.6: Key management and rotation
#   - GDPR Article 32: Encryption with secure key management
#
# AUTHOR: Raj Patel (DevOps Engineer)
# CREATED: 2025-10-06 (Sprint 2, Day 1)
# ===========================================================================

echo "======================================"
echo "Loading Key Management Configuration"
echo "======================================"
echo ""

# ===========================================================================
# DEVELOPMENT ENCRYPTION KEYS
# ===========================================================================
# CRITICAL: These are DEVELOPMENT KEYS ONLY
# Production MUST use HashiCorp Vault or AWS Secrets Manager
# ===========================================================================

# Master encryption key for development
export TAIFABASE_ENCRYPTION_KEY_DEV="dev_master_encryption_key_2025_replace_in_production"

# Alternate key for key rotation testing (Day 2 automation)
export TAIFABASE_ENCRYPTION_KEY_DEV_PREVIOUS="dev_previous_key_for_rotation_testing"

# Encryption algorithm configuration
export TAIFABASE_ENCRYPTION_ALGORITHM="AES-256"  # Via pgcrypto pgp_sym_encrypt

echo "✅ Development encryption keys loaded"
echo "   Algorithm: AES-256 (pgcrypto)"
echo ""

# ===========================================================================
# KEY ROTATION CONFIGURATION
# ===========================================================================
# SOC2 CC6.6 Requirement: Keys rotated every 90 days
# ===========================================================================

# Key rotation frequency (days)
export TAIFABASE_KEY_ROTATION_DAYS=90

# Key rotation enabled (false for Day 1, true after US-901 automation Day 6-8)
export TAIFABASE_KEY_ROTATION_ENABLED=false

# Key rotation grace period (old key valid for 24 hours after rotation)
export TAIFABASE_KEY_ROTATION_GRACE_PERIOD_HOURS=24

# Key rotation monitoring (alert 7 days before expiration)
export TAIFABASE_KEY_ROTATION_ALERT_DAYS=7

echo "✅ Key rotation configuration loaded"
echo "   Rotation frequency: ${TAIFABASE_KEY_ROTATION_DAYS} days"
echo "   Rotation enabled: ${TAIFABASE_KEY_ROTATION_ENABLED} (will enable with US-901)"
echo "   Grace period: ${TAIFABASE_KEY_ROTATION_GRACE_PERIOD_HOURS} hours"
echo ""

# ===========================================================================
# PRODUCTION KEY MANAGEMENT (Sprint 2 Target / Phase 6)
# ===========================================================================
# Production environments MUST use one of these options:
#   1. HashiCorp Vault (recommended for on-premise/multi-cloud)
#   2. AWS Secrets Manager (for AWS-only deployments)
# ===========================================================================

# Key manager selection (vault | aws-secrets-manager)
export TAIFABASE_KEY_MANAGER="vault"  # Default: HashiCorp Vault

# HashiCorp Vault configuration (production)
export TAIFABASE_VAULT_ADDR="${TAIFABASE_VAULT_ADDR:-}"  # To be configured for production
export TAIFABASE_VAULT_TOKEN="${TAIFABASE_VAULT_TOKEN:-}"  # To be configured for production
export TAIFABASE_VAULT_PATH="secret/taifabase/encryption-keys"  # Vault secrets path

# AWS Secrets Manager configuration (alternative)
export TAIFABASE_AWS_SECRETS_MANAGER_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export TAIFABASE_AWS_SECRET_NAME="taifabase/encryption-keys"

echo "✅ Production key management configuration loaded"
echo "   Key manager: ${TAIFABASE_KEY_MANAGER}"
if [ "$TAIFABASE_KEY_MANAGER" = "vault" ]; then
    if [ -z "$TAIFABASE_VAULT_ADDR" ]; then
        echo "   Vault address: Not configured (production setup required)"
    else
        echo "   Vault address: ${TAIFABASE_VAULT_ADDR}"
    fi
elif [ "$TAIFABASE_KEY_MANAGER" = "aws-secrets-manager" ]; then
    echo "   AWS region: ${TAIFABASE_AWS_SECRETS_MANAGER_REGION}"
    echo "   Secret name: ${TAIFABASE_AWS_SECRET_NAME}"
fi
echo ""

# ===========================================================================
# SECURITY AUDIT LOGGING
# ===========================================================================

# Enable key access logging
export TAIFABASE_KEY_ACCESS_LOGGING=true

# Audit log path (development)
export TAIFABASE_KEY_AUDIT_LOG_PATH="/var/log/taifabase/key-access.log"

echo "✅ Security audit configuration loaded"
echo "   Key access logging: ${TAIFABASE_KEY_ACCESS_LOGGING}"
echo "   Audit log path: ${TAIFABASE_KEY_AUDIT_LOG_PATH}"
echo ""

# ===========================================================================
# VALIDATION
# ===========================================================================

# Validate required environment variables are set
validate_key_management_config() {
    local errors=0

    # Check development key is set
    if [ -z "$TAIFABASE_ENCRYPTION_KEY_DEV" ]; then
        echo "❌ ERROR: TAIFABASE_ENCRYPTION_KEY_DEV not set"
        errors=$((errors + 1))
    fi

    # Warn if production keys not configured (expected for development)
    if [ -z "$TAIFABASE_VAULT_ADDR" ] && [ "$TAIFABASE_KEY_MANAGER" = "vault" ]; then
        echo "⚠️  WARNING: Vault not configured (expected for development, required for production)"
    fi

    if [ $errors -eq 0 ]; then
        echo "✅ Key management configuration validated"
    else
        echo "❌ Key management configuration validation FAILED ($errors errors)"
        return 1
    fi
}

# Run validation
validate_key_management_config
echo ""

# ===========================================================================
# REMINDERS
# ===========================================================================

echo "======================================"
echo "Key Management Configuration Loaded"
echo "======================================"
echo ""
echo "⚠️  CRITICAL REMINDERS:"
echo "  1. This is DEVELOPMENT configuration only"
echo "  2. Production MUST use HashiCorp Vault or AWS Secrets Manager"
echo "  3. Never commit production keys to version control"
echo "  4. Key rotation required every 90 days (SOC2 CC6.6)"
echo "  5. Enable key access logging in production"
echo ""
echo "📅 Day 2 Integration:"
echo "  - Marcus will integrate get_encryption_key() with these environment variables"
echo "  - Replace placeholder key in database functions"
echo ""
echo "📅 Day 6-8 Automation (US-901):"
echo "  - Implement automated key rotation"
echo "  - Set TAIFABASE_KEY_ROTATION_ENABLED=true"
echo "  - Deploy key rotation monitoring and alerts"
echo ""
echo "📅 Phase 6 Production Deployment:"
echo "  - Deploy HashiCorp Vault cluster (HA configuration)"
echo "  - Configure dynamic secret generation"
echo "  - Migrate from environment variables to Vault"
echo ""
