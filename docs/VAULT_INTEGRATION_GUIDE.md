# Vault Integration Guide

Guide for integrating HashiCorp Vault with ScriptonBasestar Helm charts for secrets management.

## Overview

HashiCorp Vault provides secure secret management, encryption as a service, and identity-based access. This guide covers integrating Vault with Kubernetes workloads deployed using these Helm charts.

## Integration Methods

| Method | Complexity | Use Case |
|--------|------------|----------|
| External Secrets Operator | Low | Sync Vault secrets to K8s Secrets |
| Vault Agent Sidecar | Medium | Direct injection into pods |
| CSI Provider | Medium | Mount secrets as volumes |
| Vault SDK | High | Application-level integration |

## Prerequisites

- Vault server (self-hosted or HCP Vault)
- Kubernetes 1.24+
- Helm 3.8+

## External Secrets Operator

The recommended approach for most use cases.

### Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

### Configure Vault SecretStore

**Token-based authentication:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com:8200"
      path: "secret"
      version: "v2"
      auth:
        tokenSecretRef:
          name: vault-token
          namespace: external-secrets
          key: token
```

**Kubernetes authentication (recommended):**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

### Vault Configuration for Kubernetes Auth

```bash
# Enable Kubernetes auth
vault auth enable kubernetes

# Configure Kubernetes auth
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Create policy
vault policy write external-secrets - <<EOF
path "secret/data/*" {
  capabilities = ["read"]
}
EOF

# Create role
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=1h
```

### ExternalSecret Examples

**PostgreSQL credentials:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgresql-credentials
  namespace: database
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: postgresql-secret
    creationPolicy: Owner
  data:
    - secretKey: postgres-password
      remoteRef:
        key: secret/data/database/postgresql
        property: password
    - secretKey: replication-password
      remoteRef:
        key: secret/data/database/postgresql
        property: replication_password
```

**Grafana admin credentials:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-credentials
  namespace: monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: grafana-admin-secret
  data:
    - secretKey: admin-user
      remoteRef:
        key: secret/data/monitoring/grafana
        property: admin_user
    - secretKey: admin-password
      remoteRef:
        key: secret/data/monitoring/grafana
        property: admin_password
```

**Keycloak database credentials:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: keycloak-db-credentials
  namespace: identity
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: keycloak-db-secret
  data:
    - secretKey: db-password
      remoteRef:
        key: secret/data/identity/keycloak
        property: db_password
    - secretKey: admin-password
      remoteRef:
        key: secret/data/identity/keycloak
        property: admin_password
```

### Chart Configuration with ExternalSecret

**PostgreSQL:**
```yaml
# values.yaml
auth:
  existingSecret: postgresql-secret
  secretKeys:
    adminPasswordKey: postgres-password
    replicationPasswordKey: replication-password
```

**Grafana:**
```yaml
# values.yaml
admin:
  existingSecret: grafana-admin-secret
  userKey: admin-user
  passwordKey: admin-password
```

**Keycloak:**
```yaml
# values.yaml
auth:
  existingSecret: keycloak-db-secret
  passwordKey: admin-password

postgresql:
  enabled: false
  external:
    enabled: true
    host: postgresql.database.svc
    existingSecret: keycloak-db-secret
    passwordKey: db-password
```

## Vault Agent Sidecar

For applications that need direct Vault access or dynamic secrets.

### Install Vault Agent Injector

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --set "injector.enabled=true" \
  --set "server.enabled=false" \
  -n vault --create-namespace
```

### Configure Application for Injection

```yaml
# Add annotations to enable injection
podAnnotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "app-role"
  vault.hashicorp.com/agent-inject-secret-db-creds: "secret/data/app/database"
  vault.hashicorp.com/agent-inject-template-db-creds: |
    {{- with secret "secret/data/app/database" -}}
    export DB_HOST="{{ .Data.data.host }}"
    export DB_USER="{{ .Data.data.username }}"
    export DB_PASS="{{ .Data.data.password }}"
    {{- end -}}
```

### Chart Values for Agent Injection

```yaml
# values.yaml
podAnnotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "grafana"
  vault.hashicorp.com/agent-inject-secret-config: "secret/data/monitoring/grafana"
  vault.hashicorp.com/agent-inject-template-config: |
    {{- with secret "secret/data/monitoring/grafana" -}}
    GF_SECURITY_ADMIN_USER={{ .Data.data.admin_user }}
    GF_SECURITY_ADMIN_PASSWORD={{ .Data.data.admin_password }}
    {{- end -}}

# Use injected secrets
extraEnvFrom:
  - secretRef:
      name: ""  # Empty, secrets injected by agent
```

## Secrets CSI Provider

Mount secrets directly as files in pods.

### Install CSI Provider

```bash
# Install Secrets Store CSI Driver
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system

# Install Vault CSI Provider
helm install vault hashicorp/vault \
  --set "injector.enabled=false" \
  --set "csi.enabled=true" \
  -n vault --create-namespace
```

### SecretProviderClass

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-db-creds
  namespace: production
spec:
  provider: vault
  parameters:
    vaultAddress: "https://vault.example.com:8200"
    roleName: "app-role"
    objects: |
      - objectName: "db-password"
        secretPath: "secret/data/database/postgresql"
        secretKey: "password"
  secretObjects:
    - secretName: db-credentials
      type: Opaque
      data:
        - objectName: db-password
          key: password
```

### Chart Values for CSI

```yaml
# values.yaml
extraVolumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: vault-db-creds

extraVolumeMounts:
  - name: secrets-store
    mountPath: /mnt/secrets
    readOnly: true
```

## Dynamic Secrets

Vault can generate short-lived credentials on demand.

### Database Dynamic Secrets

```bash
# Enable database secrets engine
vault secrets enable database

# Configure PostgreSQL connection
vault write database/config/postgresql \
  plugin_name=postgresql-database-plugin \
  allowed_roles="app-role" \
  connection_url="postgresql://{{username}}:{{password}}@postgresql:5432/appdb?sslmode=disable" \
  username="vault" \
  password="vault-password"

# Create role for dynamic credentials
vault write database/roles/app-role \
  db_name=postgresql \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

### Using Dynamic Secrets with Agent

```yaml
podAnnotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "app-role"
  vault.hashicorp.com/agent-inject-secret-db: "database/creds/app-role"
  vault.hashicorp.com/agent-inject-template-db: |
    {{- with secret "database/creds/app-role" -}}
    DB_USER={{ .Data.username }}
    DB_PASS={{ .Data.password }}
    {{- end -}}
```

## PKI Integration

Use Vault for TLS certificate management.

### Configure PKI Engine

```bash
# Enable PKI
vault secrets enable pki

# Configure CA
vault write pki/root/generate/internal \
  common_name="Example Root CA" \
  ttl=87600h

# Enable intermediate CA
vault secrets enable -path=pki_int pki

# Create role for certificates
vault write pki_int/roles/app-cert \
  allowed_domains="example.com,svc.cluster.local" \
  allow_subdomains=true \
  max_ttl="720h"
```

### cert-manager Integration

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: vault-issuer
  namespace: production
spec:
  vault:
    path: pki_int/sign/app-cert
    server: https://vault.example.com:8200
    auth:
      kubernetes:
        role: cert-manager
        mountPath: /v1/auth/kubernetes
        serviceAccountRef:
          name: cert-manager

---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-tls
  namespace: production
spec:
  secretName: app-tls-secret
  issuerRef:
    name: vault-issuer
    kind: Issuer
  commonName: app.example.com
  dnsNames:
    - app.example.com
    - app.production.svc.cluster.local
```

### Chart Values with Vault-issued Certificates

```yaml
ingress:
  enabled: true
  tls:
    - secretName: app-tls-secret  # Managed by cert-manager + Vault
      hosts:
        - app.example.com
```

## Transit Encryption

Use Vault for encryption as a service.

### Configure Transit Engine

```bash
# Enable transit
vault secrets enable transit

# Create encryption key
vault write -f transit/keys/app-key

# Create policy
vault policy write app-transit - <<EOF
path "transit/encrypt/app-key" {
  capabilities = ["update"]
}
path "transit/decrypt/app-key" {
  capabilities = ["update"]
}
EOF
```

### Application Usage

```python
import hvac

client = hvac.Client(url='https://vault.example.com:8200')
client.auth.kubernetes.login(role='app-role')

# Encrypt
encrypted = client.secrets.transit.encrypt_data(
    name='app-key',
    plaintext=base64.b64encode(b'sensitive data').decode()
)

# Decrypt
decrypted = client.secrets.transit.decrypt_data(
    name='app-key',
    ciphertext=encrypted['data']['ciphertext']
)
```

## Complete Example: Observability Stack

### Vault Secrets Structure

```bash
# Create secrets for observability stack
vault kv put secret/monitoring/grafana \
  admin_user=admin \
  admin_password=$(openssl rand -base64 24)

vault kv put secret/monitoring/prometheus \
  remote_write_password=$(openssl rand -base64 24)

vault kv put secret/database/postgresql \
  password=$(openssl rand -base64 24) \
  replication_password=$(openssl rand -base64 24)

vault kv put secret/monitoring/loki \
  s3_access_key=minioadmin \
  s3_secret_key=$(openssl rand -base64 24)
```

### External Secrets

```yaml
# monitoring-secrets.yaml
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-credentials
  namespace: monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: grafana-admin
  data:
    - secretKey: admin-user
      remoteRef:
        key: secret/data/monitoring/grafana
        property: admin_user
    - secretKey: admin-password
      remoteRef:
        key: secret/data/monitoring/grafana
        property: admin_password
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: loki-s3-credentials
  namespace: monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: loki-s3
  data:
    - secretKey: access-key
      remoteRef:
        key: secret/data/monitoring/loki
        property: s3_access_key
    - secretKey: secret-key
      remoteRef:
        key: secret/data/monitoring/loki
        property: s3_secret_key
```

### Chart Values

```yaml
# grafana values.yaml
admin:
  existingSecret: grafana-admin
  userKey: admin-user
  passwordKey: admin-password

---
# loki values.yaml
storage:
  s3:
    endpoint: minio.storage.svc:9000
    existingSecret: loki-s3
    accessKeyIdKey: access-key
    secretAccessKeyKey: secret-key
```

## Secret Rotation

### Automatic Rotation with External Secrets

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rotating-credentials
spec:
  refreshInterval: 15m  # Check Vault every 15 minutes
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: app-credentials
    template:
      metadata:
        annotations:
          # Trigger pod restart on secret change
          reloader.stakater.com/match: "true"
  data:
    - secretKey: api-key
      remoteRef:
        key: secret/data/app/credentials
        property: api_key
```

### Install Reloader for Auto-restart

```bash
helm repo add stakater https://stakater.github.io/stakater-charts
helm install reloader stakater/reloader -n kube-system
```

### Chart Values for Rotation

```yaml
# Enable reloader annotation
podAnnotations:
  reloader.stakater.com/auto: "true"

# Reference external secret
existingSecret: app-credentials
```

## Troubleshooting

### Common Issues

**External Secrets not syncing:**
```bash
# Check ExternalSecret status
kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <namespace>

# Check operator logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

**Vault authentication failing:**
```bash
# Verify Kubernetes auth
vault read auth/kubernetes/config

# Test role
vault write auth/kubernetes/login \
  role=external-secrets \
  jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
```

**Agent injector not working:**
```bash
# Check injector logs
kubectl logs -n vault -l app.kubernetes.io/name=vault-agent-injector

# Verify pod annotations
kubectl get pod <pod> -o jsonpath='{.metadata.annotations}'
```

### Debug Commands

```bash
# Test Vault connectivity
kubectl run vault-test --rm -it --image=vault:latest -- \
  vault status -address=https://vault.example.com:8200

# Check secret sync
kubectl get secret -n monitoring -o yaml

# Verify CSI driver
kubectl get csidriver
kubectl get secretproviderclass -A
```

## Security Best Practices

1. **Use Kubernetes auth** instead of static tokens
2. **Limit secret access** with fine-grained policies
3. **Enable audit logging** in Vault
4. **Rotate root tokens** regularly
5. **Use namespaced SecretStore** for multi-tenant environments
6. **Set appropriate TTLs** for dynamic secrets
7. **Monitor secret access** with Vault audit logs

## References

- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [External Secrets Operator](https://external-secrets.io/)
- [Vault Agent Injector](https://developer.hashicorp.com/vault/docs/platform/k8s/injector)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
- [cert-manager Vault Issuer](https://cert-manager.io/docs/configuration/vault/)

---

**Created**: 2025-11-25
**Maintained by**: ScriptonBasestar
