# Multi-Tenancy Guide

Best practices for running multiple isolated workloads or tenants using Helm charts in shared Kubernetes clusters.

## Overview

Multi-tenancy allows multiple teams, projects, or customers to share a Kubernetes cluster while maintaining isolation, security, and resource fairness. This guide covers strategies for implementing multi-tenancy with charts from this repository.

**Multi-Tenancy Models:**
- **Soft Multi-Tenancy**: Teams within the same organization share a cluster
- **Hard Multi-Tenancy**: Different customers or untrusted workloads share a cluster

## Table of Contents

- [Namespace Isolation](#namespace-isolation)
- [Resource Quotas](#resource-quotas)
- [RBAC Patterns](#rbac-patterns)
- [Network Policies](#network-policies)
- [Storage Isolation](#storage-isolation)
- [Secrets Management](#secrets-management)
- [Monitoring Per Tenant](#monitoring-per-tenant)
- [Example Configurations](#example-configurations)

## Namespace Isolation

### Namespace Strategy

Create separate namespaces for each tenant or team:

```bash
# Create tenant namespaces
kubectl create namespace tenant-alpha
kubectl create namespace tenant-beta
kubectl create namespace tenant-gamma

# Add labels for identification
kubectl label namespace tenant-alpha tenant=alpha environment=production
kubectl label namespace tenant-beta tenant=beta environment=staging
```

### Namespace Naming Conventions

```
# By tenant
tenant-{name}           # tenant-acme
tenant-{name}-{env}     # tenant-acme-prod

# By team
team-{name}             # team-platform
team-{name}-{project}   # team-platform-auth

# By environment
{env}-{app}             # prod-nextcloud
{env}-{team}-{app}      # prod-platform-keycloak
```

### Deploy Charts to Tenant Namespaces

```bash
# Deploy PostgreSQL for tenant-alpha
helm install postgresql sb-charts/postgresql \
  --namespace tenant-alpha \
  --set fullnameOverride=postgresql-alpha \
  -f values-tenant-alpha.yaml

# Deploy PostgreSQL for tenant-beta (isolated)
helm install postgresql sb-charts/postgresql \
  --namespace tenant-beta \
  --set fullnameOverride=postgresql-beta \
  -f values-tenant-beta.yaml
```

## Resource Quotas

### Limit Resources Per Namespace

```yaml
# resource-quota-standard.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-quota
  namespace: tenant-alpha
spec:
  hard:
    # Compute resources
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi

    # Object counts
    pods: "20"
    services: "10"
    secrets: "20"
    configmaps: "20"
    persistentvolumeclaims: "10"

    # Storage
    requests.storage: 100Gi
```

### Tiered Resource Quotas

```yaml
# quota-tier-small.yaml (Small tenant)
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tier-small
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    pods: "10"
    persistentvolumeclaims: "5"
    requests.storage: 50Gi
---
# quota-tier-medium.yaml (Medium tenant)
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tier-medium
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    pods: "50"
    persistentvolumeclaims: "20"
    requests.storage: 200Gi
---
# quota-tier-large.yaml (Large tenant)
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tier-large
spec:
  hard:
    requests.cpu: "32"
    requests.memory: 64Gi
    limits.cpu: "64"
    limits.memory: 128Gi
    pods: "200"
    persistentvolumeclaims: "50"
    requests.storage: 1Ti
```

### Limit Ranges (Default Limits)

```yaml
# limit-range.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: tenant-limits
  namespace: tenant-alpha
spec:
  limits:
    # Default container limits
    - default:
        cpu: "500m"
        memory: "512Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      type: Container

    # PVC limits
    - type: PersistentVolumeClaim
      max:
        storage: 50Gi
      min:
        storage: 1Gi
```

## RBAC Patterns

### Tenant Admin Role

```yaml
# tenant-admin-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tenant-admin
  namespace: tenant-alpha
rules:
  # Full access to most resources
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - pods/exec
      - services
      - endpoints
      - persistentvolumeclaims
      - configmaps
      - secrets
    verbs: ["*"]

  - apiGroups: ["apps"]
    resources:
      - deployments
      - statefulsets
      - replicasets
      - daemonsets
    verbs: ["*"]

  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs: ["*"]

  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
      - networkpolicies
    verbs: ["*"]

  # Read-only for events
  - apiGroups: [""]
    resources:
      - events
    verbs: ["get", "list", "watch"]
---
# Bind role to tenant admin group
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tenant-admin-binding
  namespace: tenant-alpha
subjects:
  - kind: Group
    name: tenant-alpha-admins
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: tenant-admin
  apiGroup: rbac.authorization.k8s.io
```

### Tenant Developer Role

```yaml
# tenant-developer-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tenant-developer
  namespace: tenant-alpha
rules:
  # Read and create pods
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
    verbs: ["get", "list", "watch", "create", "delete"]

  # Read configmaps and secrets
  - apiGroups: [""]
    resources:
      - configmaps
      - secrets
    verbs: ["get", "list", "watch"]

  # Manage deployments
  - apiGroups: ["apps"]
    resources:
      - deployments
    verbs: ["get", "list", "watch", "create", "update", "patch"]

  # Read services
  - apiGroups: [""]
    resources:
      - services
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tenant-developer-binding
  namespace: tenant-alpha
subjects:
  - kind: Group
    name: tenant-alpha-developers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: tenant-developer
  apiGroup: rbac.authorization.k8s.io
```

### Tenant Viewer Role

```yaml
# tenant-viewer-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tenant-viewer
  namespace: tenant-alpha
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - endpoints
      - configmaps
      - persistentvolumeclaims
      - events
    verbs: ["get", "list", "watch"]

  - apiGroups: ["apps"]
    resources:
      - deployments
      - statefulsets
      - replicasets
    verbs: ["get", "list", "watch"]

  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs: ["get", "list", "watch"]
```

### Service Account for Applications

```yaml
# app-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: tenant-alpha
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-role
  namespace: tenant-alpha
rules:
  # Only what the app needs
  - apiGroups: [""]
    resources:
      - configmaps
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources:
      - secrets
    resourceNames: ["app-secrets"]  # Specific secret only
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-role-binding
  namespace: tenant-alpha
subjects:
  - kind: ServiceAccount
    name: app-service-account
    namespace: tenant-alpha
roleRef:
  kind: Role
  name: app-role
  apiGroup: rbac.authorization.k8s.io
```

## Network Policies

### Default Deny All

```yaml
# default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: tenant-alpha
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### Allow Same Namespace

```yaml
# allow-same-namespace.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: tenant-alpha
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}  # Same namespace
  egress:
    - to:
        - podSelector: {}  # Same namespace
    # Allow DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
```

### Allow Ingress from Ingress Controller

```yaml
# allow-ingress-controller.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller
  namespace: tenant-alpha
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: nextcloud  # Or any exposed app
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
          podSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
      ports:
        - protocol: TCP
          port: 80
```

### Allow Access to Shared Services

```yaml
# allow-shared-services.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-shared-services
  namespace: tenant-alpha
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # Allow access to shared PostgreSQL in database namespace
    - to:
        - namespaceSelector:
            matchLabels:
              name: shared-database
          podSelector:
            matchLabels:
              app.kubernetes.io/name: postgresql
      ports:
        - protocol: TCP
          port: 5432

    # Allow access to shared Redis
    - to:
        - namespaceSelector:
            matchLabels:
              name: shared-database
          podSelector:
            matchLabels:
              app.kubernetes.io/name: redis
      ports:
        - protocol: TCP
          port: 6379

    # Allow DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
```

### Complete Tenant Network Policy

```yaml
# tenant-network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-policy
  namespace: tenant-alpha
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow from same namespace
    - from:
        - podSelector: {}
    # Allow from ingress controller
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
  egress:
    # Allow to same namespace
    - to:
        - podSelector: {}
    # Allow DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
    # Allow external HTTPS (for updates, etc.)
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
      ports:
        - protocol: TCP
          port: 443
```

## Storage Isolation

### StorageClass Per Tenant

```yaml
# storageclass-tenant-alpha.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: tenant-alpha-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: ssd
```

### Use StorageClass in Charts

```yaml
# values-tenant-alpha.yaml
persistence:
  enabled: true
  storageClass: tenant-alpha-storage
  size: 10Gi
```

### PV/PVC Quotas

```yaml
# Storage quota per tenant
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storage-quota
  namespace: tenant-alpha
spec:
  hard:
    persistentvolumeclaims: "10"
    requests.storage: 100Gi
    # Limit specific storage classes
    tenant-alpha-storage.storageclass.storage.k8s.io/requests.storage: 100Gi
```

## Secrets Management

### Namespace-Scoped Secrets

```yaml
# tenant-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: tenant-alpha
type: Opaque
stringData:
  POSTGRES_USER: tenant_alpha
  POSTGRES_PASSWORD: secure-password-here
  POSTGRES_DB: tenant_alpha_db
```

### External Secrets (with External Secrets Operator)

```yaml
# external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: tenant-alpha
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: database-credentials
    creationPolicy: Owner
  data:
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: tenants/alpha/database
        property: password
```

### Sealed Secrets (GitOps-friendly)

```bash
# Create sealed secret
kubectl create secret generic database-credentials \
  --namespace tenant-alpha \
  --from-literal=POSTGRES_PASSWORD=mypassword \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-database-credentials.yaml
```

## Monitoring Per Tenant

### Prometheus with Namespace Filtering

```yaml
# Prometheus scrape config for tenant-alpha
prometheus:
  additionalScrapeConfigs:
    - job_name: 'tenant-alpha'
      kubernetes_sd_configs:
        - role: pod
          namespaces:
            names:
              - tenant-alpha
      relabel_configs:
        - source_labels: [__meta_kubernetes_namespace]
          action: keep
          regex: tenant-alpha
```

### Grafana with Namespace Variable

```json
{
  "templating": {
    "list": [
      {
        "name": "namespace",
        "type": "query",
        "query": "label_values(kube_namespace_labels{tenant=~\"$tenant\"}, namespace)",
        "multi": true
      }
    ]
  }
}
```

### Loki Tenant Isolation

```yaml
# Loki multi-tenant config
loki:
  auth_enabled: true
  server:
    http_listen_port: 3100

  # Tenant ID from HTTP header
  distributor:
    ring:
      kvstore:
        store: inmemory

  # Separate storage per tenant
  storage_config:
    boltdb_shipper:
      active_index_directory: /loki/index
      cache_location: /loki/cache
      shared_store: s3
```

### Uptime Kuma Per Tenant

Deploy separate Uptime Kuma instances per tenant:

```bash
# Deploy for tenant-alpha
helm install uptime-kuma sb-charts/uptime-kuma \
  --namespace tenant-alpha \
  --set fullnameOverride=uptime-kuma-alpha \
  -f values-tenant-alpha.yaml
```

## Example Configurations

### Complete Tenant Setup Script

```bash
#!/bin/bash
# setup-tenant.sh - Create complete tenant environment

TENANT_NAME="${1:?Tenant name required}"
TENANT_TIER="${2:-medium}"  # small, medium, large

# Create namespace
kubectl create namespace "tenant-${TENANT_NAME}"
kubectl label namespace "tenant-${TENANT_NAME}" \
  tenant="${TENANT_NAME}" \
  tier="${TENANT_TIER}"

# Apply resource quota based on tier
kubectl apply -f "quotas/quota-tier-${TENANT_TIER}.yaml" \
  -n "tenant-${TENANT_NAME}"

# Apply limit range
kubectl apply -f limit-ranges/default-limits.yaml \
  -n "tenant-${TENANT_NAME}"

# Apply network policies
kubectl apply -f network-policies/tenant-policy.yaml \
  -n "tenant-${TENANT_NAME}"

# Create RBAC
kubectl apply -f rbac/tenant-admin-role.yaml \
  -n "tenant-${TENANT_NAME}"
kubectl apply -f rbac/tenant-developer-role.yaml \
  -n "tenant-${TENANT_NAME}"

echo "Tenant ${TENANT_NAME} setup complete with ${TENANT_TIER} tier"
```

### Helm Values for Multi-Tenant Deployment

```yaml
# values-tenant-template.yaml
# Override with tenant-specific values

# Common settings
fullnameOverride: "{{ .Values.tenantName }}-app"

# Resources based on tier
resources:
  requests:
    cpu: "{{ .Values.tierCpu }}"
    memory: "{{ .Values.tierMemory }}"

# Network policy labels
podLabels:
  tenant: "{{ .Values.tenantName }}"

# Use tenant-specific secrets
existingSecret: "{{ .Values.tenantName }}-secrets"

# Persistence with tenant storage class
persistence:
  enabled: true
  storageClass: "tenant-{{ .Values.tenantName }}-storage"
```

### ArgoCD Application Per Tenant

```yaml
# argocd-tenant-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tenant-alpha-apps
  namespace: argocd
spec:
  project: tenant-alpha
  source:
    repoURL: https://github.com/org/tenant-configs
    targetRevision: HEAD
    path: tenants/alpha
  destination:
    server: https://kubernetes.default.svc
    namespace: tenant-alpha
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false  # Namespace must exist
```

### Kyverno Policy for Tenant Isolation

```yaml
# require-tenant-label.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-tenant-label
spec:
  validationFailureAction: enforce
  rules:
    - name: check-tenant-label
      match:
        resources:
          kinds:
            - Pod
          namespaces:
            - "tenant-*"
      validate:
        message: "Pods must have a 'tenant' label matching namespace"
        pattern:
          metadata:
            labels:
              tenant: "{{ request.namespace | replace('tenant-', '') }}"
```

## Best Practices Summary

### DO

- ✅ Use namespaces as primary isolation boundary
- ✅ Apply resource quotas to all tenant namespaces
- ✅ Set default limits via LimitRange
- ✅ Implement default-deny network policies
- ✅ Use RBAC with least-privilege principle
- ✅ Separate secrets per tenant
- ✅ Monitor resource usage per tenant
- ✅ Use labels consistently for tenant identification

### DON'T

- ❌ Share secrets across tenants
- ❌ Allow unrestricted network access
- ❌ Give cluster-admin to tenant users
- ❌ Share PersistentVolumes across tenants
- ❌ Skip resource quotas
- ❌ Use same service accounts across tenants
- ❌ Allow pods to run as root by default

## Troubleshooting

### Quota Exceeded

```bash
# Check current usage
kubectl describe resourcequota -n tenant-alpha

# Check which pods are using resources
kubectl top pods -n tenant-alpha

# Check events for quota-related issues
kubectl get events -n tenant-alpha --field-selector reason=FailedCreate
```

### Network Policy Issues

```bash
# Test connectivity
kubectl run test-pod --rm -it --image=busybox -n tenant-alpha -- wget -qO- http://service

# Check network policies
kubectl get networkpolicy -n tenant-alpha -o yaml

# Debug with ephemeral container
kubectl debug pod/app-pod -n tenant-alpha --image=nicolaka/netshoot -- tcpdump -i any
```

### RBAC Debugging

```bash
# Check user permissions
kubectl auth can-i create pods -n tenant-alpha --as=user@example.com

# List all roles in namespace
kubectl get roles,rolebindings -n tenant-alpha

# Check effective permissions
kubectl auth can-i --list --as=user@example.com -n tenant-alpha
```

## References

- [Kubernetes Multi-tenancy Working Group](https://github.com/kubernetes-sigs/multi-tenancy)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Hierarchical Namespaces Controller](https://github.com/kubernetes-sigs/hierarchical-namespaces)
