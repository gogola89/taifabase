# Production Key Management Setup

**Document Metadata**
- **Created**: 2025-10-06 (Sprint 2, Day 1)
- **Version**: 1.0
- **Owner**: Raj Patel (DevOps Engineer)
- **Status**: Planning (Day 1) → Implementation (Phase 6)

---

## Executive Summary

This document outlines the production key management strategy for Taifabase encryption at rest. Two approaches are documented: HashiCorp Vault (recommended) and AWS Secrets Manager (cloud-only alternative).

**Recommendation**: HashiCorp Vault for maximum flexibility (on-premise, multi-cloud, hybrid)
**Timeline**: Planning (Sprint 2), Implementation (Phase 6)

---

## Option 1: HashiCorp Vault (Recommended)

### Overview

**HashiCorp Vault** is an industry-standard secrets management platform with enterprise-grade security features.

**Advantages**:
- ✅ Works on-premise, multi-cloud, or hybrid environments
- ✅ Dynamic secret generation (automatic key rotation)
- ✅ Audit logging and access control built-in
- ✅ High availability (HA) configuration
- ✅ Integration with Kubernetes, Docker, PostgreSQL
- ✅ Compliance-ready (SOC2, GDPR, HIPAA)

**Disadvantages**:
- ⚠️ More complex setup than managed services
- ⚠️ Requires infrastructure management (HA cluster, unseal keys)
- ⚠️ Operational overhead (monitoring, upgrades, backups)

**Use Cases**:
- On-premise deployments
- Multi-cloud environments (AWS + Azure + GCP)
- Hybrid cloud (on-premise + cloud)
- Maximum control and flexibility requirements

---

### Vault Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Application Layer                           │
│  (PostgreSQL, Backend Services)                         │
└────────────────────┬────────────────────────────────────┘
                     │ Get Encryption Key
                     ▼
┌─────────────────────────────────────────────────────────┐
│              HashiCorp Vault Cluster (HA)               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │ Vault-0  │  │ Vault-1  │  │ Vault-2  │  (3 nodes) │
│  │ (Leader) │  │(Follower)│  │(Follower)│            │
│  └──────────┘  └──────────┘  └──────────┘            │
│                                                         │
│  Storage Backend: Consul / etcd / Integrated Storage   │
└─────────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│              Persistent Storage                          │
│  (Encrypted data at rest)                              │
└─────────────────────────────────────────────────────────┘
```

### Vault Deployment (Kubernetes)

**Step 1: Add Vault Helm Repository**

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

**Step 2: Create Vault Values File**

**File**: `infrastructure/kubernetes/vault-values.yaml`

```yaml
# Vault HA Configuration for Production
global:
  enabled: true
  tlsDisable: false  # TLS required for production

server:
  # High Availability (HA) mode
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      setNodeId: true
      config: |
        ui = true

        listener "tcp" {
          tls_disable = 0
          address = "[::]:8200"
          cluster_address = "[::]:8201"
          tls_cert_file = "/vault/userconfig/vault-server-tls/vault.crt"
          tls_key_file  = "/vault/userconfig/vault-server-tls/vault.key"
        }

        storage "raft" {
          path = "/vault/data"
        }

        service_registration "kubernetes" {}

  # Resource allocation
  resources:
    requests:
      memory: 256Mi
      cpu: 250m
    limits:
      memory: 512Mi
      cpu: 500m

  # Data storage
  dataStorage:
    enabled: true
    size: 10Gi
    storageClass: "fast-ssd"  # Use fast storage for Vault

  # Audit logging
  auditStorage:
    enabled: true
    size: 5Gi

  # Ingress (for UI and API access)
  ingress:
    enabled: true
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
    hosts:
      - host: vault.taifabase.com
        paths:
          - /
    tls:
      - secretName: vault-tls
        hosts:
          - vault.taifabase.com

ui:
  enabled: true
  serviceType: "ClusterIP"
```

**Step 3: Deploy Vault**

```bash
# Deploy Vault with custom values
helm install vault hashicorp/vault \
    --namespace vault \
    --create-namespace \
    --values infrastructure/kubernetes/vault-values.yaml

# Wait for Vault pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault --namespace vault --timeout=300s

# Check Vault status
kubectl get pods --namespace vault
# Expected: 3 vault pods running
```

**Step 4: Initialize Vault**

```bash
# Initialize Vault (first time only)
kubectl exec -it vault-0 --namespace vault -- vault operator init \
    -key-shares=5 \
    -key-threshold=3 \
    > vault-init-keys.txt

# CRITICAL: Securely store vault-init-keys.txt
# Contains: 5 unseal keys + root token
# Required for unsealing Vault after restart

# Unseal Vault (requires 3 of 5 keys)
for i in 0 1 2; do
    kubectl exec -it vault-$i --namespace vault -- vault operator unseal <unseal_key_1>
    kubectl exec -it vault-$i --namespace vault -- vault operator unseal <unseal_key_2>
    kubectl exec -it vault-$i --namespace vault -- vault operator unseal <unseal_key_3>
done

# Verify Vault unsealed and ready
kubectl exec -it vault-0 --namespace vault -- vault status
# Expected: Sealed = false, Cluster Mode = active
```

### Vault Configuration for Taifabase

**Step 5: Enable KV Secrets Engine**

```bash
# Login to Vault
kubectl exec -it vault-0 --namespace vault -- vault login <root_token>

# Enable KV v2 secrets engine
kubectl exec -it vault-0 --namespace vault -- vault secrets enable -path=secret kv-v2

# Verify secrets engine enabled
kubectl exec -it vault-0 --namespace vault -- vault secrets list
# Expected: secret/ KV version 2
```

**Step 6: Create Encryption Keys**

```bash
# Generate initial master encryption key
NEW_KEY=$(openssl rand -base64 32)

# Store encryption key in Vault
kubectl exec -it vault-0 --namespace vault -- vault kv put secret/taifabase/encryption-keys \
    master_key="$NEW_KEY" \
    generated_at="$(date -Iseconds)" \
    expires_at="$(date -d '+90 days' -Iseconds)" \
    key_version="1"

# Verify key stored
kubectl exec -it vault-0 --namespace vault -- vault kv get secret/taifabase/encryption-keys
```

**Step 7: Create Access Policies**

**PostgreSQL Read Policy** (`taifabase-postgres-read.hcl`):

```hcl
# Policy for PostgreSQL to read encryption keys
path "secret/data/taifabase/encryption-keys" {
  capabilities = ["read"]
}

# Allow listing keys
path "secret/metadata/taifabase/encryption-keys" {
  capabilities = ["list", "read"]
}
```

**DevOps Rotation Policy** (`taifabase-devops-rotate.hcl`):

```hcl
# Policy for DevOps to rotate encryption keys
path "secret/data/taifabase/encryption-keys" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/taifabase/encryption-keys" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow key rotation operations
path "secret/data/taifabase/encryption-keys/previous" {
  capabilities = ["create", "read", "update"]
}
```

**Apply Policies**:

```bash
# Create PostgreSQL read policy
kubectl exec -it vault-0 --namespace vault -- vault policy write taifabase-postgres-read - <<EOF
path "secret/data/taifabase/encryption-keys" {
  capabilities = ["read"]
}
EOF

# Create DevOps rotation policy
kubectl exec -it vault-0 --namespace vault -- vault policy write taifabase-devops-rotate - <<EOF
path "secret/data/taifabase/encryption-keys" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

**Step 8: Create Service Accounts and Tokens**

```bash
# Enable Kubernetes auth method
kubectl exec -it vault-0 --namespace vault -- vault auth enable kubernetes

# Configure Kubernetes auth
kubectl exec -it vault-0 --namespace vault -- vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443"

# Create role for PostgreSQL service
kubectl exec -it vault-0 --namespace vault -- vault write auth/kubernetes/role/taifabase-postgres \
    bound_service_account_names=taifabase-postgres \
    bound_service_account_namespaces=taifabase \
    policies=taifabase-postgres-read \
    ttl=24h

# Generate token for PostgreSQL (alternative: use Kubernetes ServiceAccount)
POSTGRES_TOKEN=$(kubectl exec -it vault-0 --namespace vault -- vault token create \
    -policy=taifabase-postgres-read \
    -ttl=8760h \
    -format=json | jq -r '.auth.client_token')

echo "PostgreSQL Vault Token: $POSTGRES_TOKEN"
# Store securely in Kubernetes Secret
```

### PostgreSQL Integration with Vault

**Step 9: Update get_encryption_key() Function**

```sql
-- Production: Retrieve key from Vault
CREATE OR REPLACE FUNCTION get_encryption_key(
    key_id UUID DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    vault_addr TEXT := current_setting('taifabase.vault_addr', true);
    vault_token TEXT := current_setting('taifabase.vault_token', true);
    vault_path TEXT := 'secret/data/taifabase/encryption-keys';
    encryption_key TEXT;
    http_response RECORD;
BEGIN
    -- Validate Vault configuration
    IF vault_addr IS NULL OR vault_addr = '' THEN
        RAISE EXCEPTION 'Vault address not configured (taifabase.vault_addr)';
    END IF;

    IF vault_token IS NULL OR vault_token = '' THEN
        RAISE EXCEPTION 'Vault token not configured (taifabase.vault_token)';
    END IF;

    -- Call Vault API to retrieve encryption key
    -- Requires http extension or external script
    -- Example using http extension (if available):
    --
    -- SELECT * FROM http_get(
    --     vault_addr || '/v1/' || vault_path,
    --     ARRAY[http_header('X-Vault-Token', vault_token)]
    -- ) INTO http_response;
    --
    -- encryption_key := (http_response.content::json->'data'->'data'->>'master_key');

    -- For Phase 6: Implement Vault API integration
    -- For Sprint 2: Document approach, implement in Phase 6

    -- Temporary: Use environment variable fallback
    encryption_key := current_setting('taifabase.encryption_key_dev', true);

    IF encryption_key IS NULL OR encryption_key = '' THEN
        RAISE EXCEPTION 'Encryption key not retrieved from Vault';
    END IF;

    -- Audit logging
    INSERT INTO audit.key_access_log (key_id, operation, user_id, source_ip, success)
    VALUES (key_id, 'retrieve', current_user, inet_client_addr(), true);

    RETURN encryption_key;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**Step 10: Configure PostgreSQL Environment Variables**

Update `docker-compose.yml` or Kubernetes Deployment:

```yaml
environment:
  TAIFABASE_VAULT_ADDR: "https://vault.taifabase.com"
  TAIFABASE_VAULT_TOKEN: "${POSTGRES_VAULT_TOKEN}"  # From Kubernetes Secret
```

---

## Option 2: AWS Secrets Manager (Cloud-Only Alternative)

### Overview

**AWS Secrets Manager** is a fully managed secrets management service by Amazon Web Services.

**Advantages**:
- ✅ Fully managed (no infrastructure to maintain)
- ✅ Automatic rotation support
- ✅ Native AWS integration (IAM, KMS, CloudWatch)
- ✅ Simple setup compared to Vault
- ✅ Compliance-ready (SOC2, GDPR, HIPAA)

**Disadvantages**:
- ⚠️ AWS-only (vendor lock-in)
- ⚠️ Higher cost ($0.40/secret/month + $0.05/10,000 API calls)
- ⚠️ Less flexible than Vault (limited customization)

**Use Cases**:
- AWS-only deployments
- Prefer managed services over self-hosted
- Minimal operational overhead requirements

---

### AWS Secrets Manager Setup

**Step 1: Create Secret**

```bash
# Create encryption key secret
aws secretsmanager create-secret \
    --name taifabase/encryption-keys/master \
    --description "Taifabase master encryption key" \
    --secret-string "{
        \"master_key\": \"$(openssl rand -base64 32)\",
        \"generated_at\": \"$(date -Iseconds)\",
        \"expires_at\": \"$(date -d '+90 days' -Iseconds)\",
        \"key_version\": \"1\"
    }" \
    --region us-east-1

# Verify secret created
aws secretsmanager describe-secret \
    --secret-id taifabase/encryption-keys/master \
    --region us-east-1
```

**Step 2: Configure Automatic Rotation**

```bash
# Create rotation Lambda function (AWS provides template)
aws lambda create-function \
    --function-name TaifabaseKeyRotation \
    --runtime python3.11 \
    --role arn:aws:iam::ACCOUNT_ID:role/SecretsManagerRotationRole \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://rotation-function.zip \
    --region us-east-1

# Configure automatic rotation (90 days)
aws secretsmanager rotate-secret \
    --secret-id taifabase/encryption-keys/master \
    --rotation-lambda-arn arn:aws:lambda:us-east-1:ACCOUNT_ID:function:TaifabaseKeyRotation \
    --rotation-rules "{\"AutomaticallyAfterDays\": 90}" \
    --region us-east-1
```

**Step 3: IAM Policy for PostgreSQL**

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:taifabase/encryption-keys/*"
        }
    ]
}
```

**Step 4: PostgreSQL Integration**

```sql
-- Retrieve key from AWS Secrets Manager
CREATE OR REPLACE FUNCTION get_encryption_key(
    key_id UUID DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    aws_region TEXT := current_setting('taifabase.aws_region', true);
    secret_name TEXT := 'taifabase/encryption-keys/master';
    encryption_key TEXT;
BEGIN
    -- Call AWS Secrets Manager API
    -- Requires AWS SDK or CLI integration

    -- Example using aws CLI (if available):
    -- encryption_key := (
    --     SELECT value FROM aws_cli_get_secret(secret_name, aws_region)
    -- );

    -- For Phase 6: Implement AWS Secrets Manager integration

    -- Temporary: Use environment variable fallback
    encryption_key := current_setting('taifabase.encryption_key_dev', true);

    RETURN encryption_key;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## Decision Matrix

| Criteria | HashiCorp Vault | AWS Secrets Manager |
|----------|-----------------|---------------------|
| **Deployment Flexibility** | ✅ On-premise, multi-cloud, hybrid | ⚠️ AWS-only |
| **Operational Overhead** | ⚠️ High (self-managed) | ✅ Low (fully managed) |
| **Cost** | ✅ Lower (self-hosted) | ⚠️ Higher ($0.40/secret/month) |
| **Customization** | ✅ Highly customizable | ⚠️ Limited customization |
| **Integration** | ✅ Kubernetes, Docker, many platforms | ✅ Native AWS integration |
| **Audit Logging** | ✅ Built-in, customizable | ✅ CloudWatch Logs |
| **High Availability** | ✅ HA cluster (3+ nodes) | ✅ AWS-managed HA |
| **Compliance** | ✅ SOC2, GDPR, HIPAA | ✅ SOC2, GDPR, HIPAA |

**Recommendation**: **HashiCorp Vault** for Taifabase (maximum flexibility, multi-cloud support)

---

## Implementation Timeline

### Sprint 2 (Current) - Planning

- ✅ Day 1: Document Vault and AWS Secrets Manager approaches
- 🔄 Day 2-5: Development environment uses environment variables
- 🔄 Day 6-8: Plan automated rotation (US-901)

### Phase 6 - Production Implementation

- Week 1: Deploy Vault cluster (HA configuration)
- Week 2: Configure Vault secrets engine and policies
- Week 3: Integrate PostgreSQL with Vault
- Week 4: Testing and validation (staging environment)
- Week 5: Production deployment and monitoring

---

## Security Best Practices

1. **Never commit secrets to version control** - Use .gitignore for sensitive files
2. **Rotate keys every 90 days** - SOC2 CC6.6 requirement
3. **Use TLS for all Vault communication** - Prevent man-in-the-middle attacks
4. **Audit all key access** - Log retrieval, rotation, and access attempts
5. **Implement least privilege** - Grant minimum necessary permissions
6. **Test rotation procedures regularly** - Quarterly rotation drills
7. **Secure unseal keys** - Store in separate, secure locations (Vault)
8. **Monitor key expiration** - Alert 7 days before expiration

---

## References

- **Vault Documentation**: https://www.vaultproject.io/docs
- **AWS Secrets Manager**: https://docs.aws.amazon.com/secretsmanager/
- **SOC2 CC6.6**: Key management controls
- **GDPR Article 32**: Encryption and key management

---

**Document Status**: Planning Complete (Day 1), Implementation Pending (Phase 6)
**Next Update**: Phase 6 (production deployment planning)
**Questions**: Contact Raj Patel (DevOps Engineer) or escalate to Sarah Chen (PM)
