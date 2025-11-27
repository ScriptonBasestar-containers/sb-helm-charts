# Multi-Tenancy Guide for Kubernetes

## Table of Contents

1. [Overview](#overview)
2. [Multi-Tenancy Models](#multi-tenancy-models)
3. [Namespace Isolation](#namespace-isolation)
4. [Resource Quotas](#resource-quotas)
5. [Network Policies](#network-policies)
6. [RBAC Configuration](#rbac-configuration)
7. [Pod Security](#pod-security)
8. [Storage Isolation](#storage-isolation)
9. [Monitoring & Observability](#monitoring--observability)
10. [Best Practices](#best-practices)
11. [Implementation Examples](#implementation-examples)

---

## Overview

### Purpose

This guide provides comprehensive procedures for implementing multi-tenancy in Kubernetes clusters, enabling multiple teams, projects, or customers to share cluster resources while maintaining isolation, security, and fair resource allocation.

### What is Multi-Tenancy?

Multi-tenancy in Kubernetes refers to sharing a single Kubernetes cluster among multiple tenants (teams, projects, customers) while providing:

- **Isolation**: Tenants cannot access or affect each other's resources
- **Security**: Strong boundaries between tenant workloads
- **Fair Resource Allocation**: Guaranteed minimum resources and usage limits
- **Cost Efficiency**: Shared infrastructure with independent billing/chargeback

### Multi-Tenancy Benefits

| Benefit | Description |
|---------|-------------|
| **Cost Reduction** | Shared infrastructure reduces per-tenant costs (50-70% savings) |
| **Operational Efficiency** | Centralized management reduces operational overhead |
| **Resource Utilization** | Better cluster resource utilization (70-80% vs 30-40% single-tenant) |
| **Faster Provisioning** | Instant namespace creation vs cluster provisioning (minutes vs hours) |
| **Simplified Upgrades** | Single cluster upgrade benefits all tenants |

### Multi-Tenancy Challenges

| Challenge | Mitigation |
|-----------|------------|
| **Security Boundaries** | Strong RBAC, NetworkPolicies, PodSecurityPolicies/Standards |
| **Resource Contention** | ResourceQuotas, LimitRanges, PriorityClasses |
| **Network Isolation** | NetworkPolicies, service mesh (Istio, Linkerd) |
| **Noisy Neighbor** | Resource limits, QoS classes, node affinity |
| **Tenant Onboarding** | Automated provisioning, self-service portals |

---

## Multi-Tenancy Models

### Model 1: Namespace-based Isolation (Soft Multi-Tenancy)

**Description:** Each tenant gets one or more namespaces within a shared cluster. Tenants are typically trusted (internal teams).

**Characteristics:**
- Shared control plane (API server, scheduler, controller manager)
- Shared worker nodes
- Namespace-level isolation
- RBAC-based access control
- NetworkPolicies for network isolation

**Use Cases:**
- Multiple development teams within same organization
- Different environments (dev, staging, prod) for same application
- Microservices with different teams owning different services

**Pros:**
- ✅ Cost-effective (shared infrastructure)
- ✅ Easy to implement
- ✅ Fast tenant provisioning
- ✅ Good for trusted tenants

**Cons:**
- ❌ Shared kernel (potential security risks)
- ❌ Limited isolation for untrusted workloads
- ❌ All tenants see same Kubernetes version

**Recommendation:** Best for internal teams, non-sensitive workloads.

### Model 2: Node-based Isolation (Hard Multi-Tenancy)

**Description:** Each tenant gets dedicated nodes within a shared cluster. Stronger isolation with node-level boundaries.

**Characteristics:**
- Shared control plane
- Dedicated worker nodes per tenant
- Node taints and tolerations
- Node selectors/affinity for tenant assignment

**Use Cases:**
- Customers with compliance requirements
- Workloads with different security postures
- Tenants requiring guaranteed compute resources

**Pros:**
- ✅ Stronger isolation (separate kernel/OS)
- ✅ No noisy neighbor on compute
- ✅ Can run different node configurations
- ✅ Suitable for compliance workloads

**Cons:**
- ❌ Lower resource utilization
- ❌ Higher costs (dedicated nodes)
- ❌ More complex capacity planning

**Recommendation:** Best for external customers, compliance-sensitive workloads.

### Model 3: Cluster-based Isolation (Complete Isolation)

**Description:** Each tenant gets a dedicated Kubernetes cluster. Maximum isolation with separate control plane and data plane.

**Characteristics:**
- Separate control plane per tenant
- Separate worker nodes per tenant
- Complete isolation
- Independent cluster upgrades

**Use Cases:**
- Highly sensitive workloads (financial, healthcare)
- Regulatory compliance requirements (PCI-DSS, HIPAA)
- Tenants requiring custom Kubernetes versions/configurations

**Pros:**
- ✅ Maximum isolation and security
- ✅ Independent cluster configuration
- ✅ No shared fate (failure isolation)
- ✅ Compliance-friendly

**Cons:**
- ❌ High operational overhead
- ❌ Highest cost (separate infrastructure)
- ❌ Lower resource utilization
- ❌ Complex multi-cluster management

**Recommendation:** Best for highly sensitive workloads, large enterprise customers.

### Model Comparison

| Aspect | Namespace-based | Node-based | Cluster-based |
|--------|----------------|------------|---------------|
| **Isolation** | Soft | Medium | Hard |
| **Cost** | Low | Medium | High |
| **Operational Complexity** | Low | Medium | High |
| **Resource Utilization** | High (80%+) | Medium (60%) | Low (40%) |
| **Security** | Good | Better | Best |
| **Use Case** | Internal teams | External customers | Compliance/Sensitive |

**This guide focuses on Namespace-based and Node-based models**, which are most commonly used with Helm charts.

---

## Namespace Isolation

### Namespace Design Patterns

**Pattern 1: One Namespace per Tenant**
```
├── tenant-a
├── tenant-b
├── tenant-c
```
- Simple, clear ownership
- Best for small number of tenants (<50)

**Pattern 2: Multiple Namespaces per Tenant**
```
├── tenant-a-prod
├── tenant-a-staging
├── tenant-a-dev
├── tenant-b-prod
├── tenant-b-staging
```
- Environment separation within tenant
- Best for tenants with multiple environments

**Pattern 3: Hierarchical Namespaces**
```
├── org-engineering
│   ├── team-frontend
│   ├── team-backend
│   ├── team-data
├── org-product
│   ├── team-analytics
│   ├── team-growth
```
- Organizational structure mapping
- Best for large enterprises with divisions

### Namespace Creation

**Manual creation:**
```bash
# Create namespace for tenant
kubectl create namespace tenant-a

# Add labels for organization
kubectl label namespace tenant-a \
  tenant=tenant-a \
  environment=production \
  cost-center=engineering
```

**Automated creation with template:**
```yaml
# namespace-template.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${TENANT_NAME}
  labels:
    tenant: ${TENANT_NAME}
    environment: ${ENVIRONMENT}
    cost-center: ${COST_CENTER}
  annotations:
    contact: ${CONTACT_EMAIL}
    created-by: automation
    created-at: ${TIMESTAMP}
---
# ResourceQuota for namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${TENANT_NAME}-quota
  namespace: ${TENANT_NAME}
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    persistentvolumeclaims: "10"
    services.loadbalancers: "2"
---
# LimitRange for namespace
apiVersion: v1
kind: LimitRange
metadata:
  name: ${TENANT_NAME}-limits
  namespace: ${TENANT_NAME}
spec:
  limits:
    - max:
        cpu: "4"
        memory: 8Gi
      min:
        cpu: "100m"
        memory: 128Mi
      default:
        cpu: "500m"
        memory: 512Mi
      defaultRequest:
        cpu: "250m"
        memory: 256Mi
      type: Container
```

**Provisioning script:**
```bash
#!/bin/bash
# tenant-provision.sh

TENANT_NAME=$1
ENVIRONMENT=${2:-production}
COST_CENTER=${3:-default}
CONTACT_EMAIL=${4:-admin@example.com}
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Validate inputs
if [ -z "$TENANT_NAME" ]; then
  echo "Usage: $0 <tenant-name> [environment] [cost-center] [contact-email]"
  exit 1
fi

# Create namespace from template
cat namespace-template.yaml | \
  sed "s/\${TENANT_NAME}/$TENANT_NAME/g" | \
  sed "s/\${ENVIRONMENT}/$ENVIRONMENT/g" | \
  sed "s/\${COST_CENTER}/$COST_CENTER/g" | \
  sed "s/\${CONTACT_EMAIL}/$CONTACT_EMAIL/g" | \
  sed "s/\${TIMESTAMP}/$TIMESTAMP/g" | \
  kubectl apply -f -

echo "Tenant $TENANT_NAME provisioned successfully"
```

### Namespace Metadata

**Best practices for namespace labels and annotations:**

```yaml
metadata:
  name: tenant-a-prod
  labels:
    # Organizational labels
    tenant: tenant-a
    environment: production
    cost-center: engineering
    business-unit: platform

    # Technical labels
    monitoring: enabled
    backup: enabled
    network-policy: strict

    # Compliance labels
    compliance: pci-dss
    data-classification: confidential

  annotations:
    # Contact information
    contact.email: "team-a@example.com"
    contact.slack: "#team-a"
    contact.oncall: "https://oncall.example.com/team-a"

    # Documentation
    documentation: "https://wiki.example.com/tenant-a"
    runbook: "https://runbook.example.com/tenant-a"

    # Metadata
    created-by: "automation"
    created-at: "2025-01-27T10:00:00Z"
    owner: "team-a"

    # Cost tracking
    billing-code: "CC-12345"
    cost-center: "engineering-platform"
```

---

## Resource Quotas

### ResourceQuota Overview

ResourceQuotas limit aggregate resource consumption per namespace, ensuring fair resource allocation and preventing resource exhaustion.

**Types of quotas:**
- **Compute quotas**: CPU, memory requests and limits
- **Storage quotas**: PersistentVolumeClaims, storage requests
- **Object count quotas**: Pods, services, secrets, configmaps

### Compute Resource Quotas

**Example ResourceQuota:**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: tenant-a
spec:
  hard:
    # CPU quotas
    requests.cpu: "10"        # Total CPU requests
    limits.cpu: "20"          # Total CPU limits

    # Memory quotas
    requests.memory: 20Gi     # Total memory requests
    limits.memory: 40Gi       # Total memory limits

    # Pod count
    pods: "50"                # Maximum 50 pods
```

**Quota sizing guidelines:**

| Tenant Size | CPU Requests | Memory Requests | Pods |
|-------------|-------------|-----------------|------|
| **Small** (1-3 services) | 2-4 cores | 4-8 Gi | 10-20 |
| **Medium** (4-10 services) | 10-20 cores | 20-40 Gi | 50-100 |
| **Large** (>10 services) | 50+ cores | 100+ Gi | 200+ |

**Example: Development vs Production quotas:**

```yaml
# Development namespace (smaller quotas)
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dev-quota
  namespace: tenant-a-dev
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
---
# Production namespace (larger quotas)
apiVersion: v1
kind: ResourceQuota
metadata:
  name: prod-quota
  namespace: tenant-a-prod
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    pods: "100"
```

### Storage Resource Quotas

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storage-quota
  namespace: tenant-a
spec:
  hard:
    # PVC quotas
    persistentvolumeclaims: "10"              # Max 10 PVCs
    requests.storage: "100Gi"                 # Total storage requests

    # Storage class specific quotas
    requests.storage.class.fast: "50Gi"       # Fast SSD storage
    requests.storage.class.standard: "50Gi"   # Standard storage

    # Volume snapshot quotas
    volumesnapshots.storage.k8s.io: "20"      # Max 20 snapshots
```

### Object Count Quotas

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: object-quota
  namespace: tenant-a
spec:
  hard:
    # Workload quotas
    pods: "50"
    replicationcontrollers: "20"

    # Service quotas
    services: "10"
    services.loadbalancers: "2"               # Max 2 LoadBalancers
    services.nodeports: "5"                   # Max 5 NodePorts

    # Configuration quotas
    configmaps: "50"
    secrets: "50"

    # Network quotas
    ingresses.networking.k8s.io: "10"
    networkpolicies.networking.k8s.io: "20"
```

### LimitRange for Default Limits

LimitRange sets default resource limits and requests for containers, ensuring all pods have resource constraints.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: resource-limits
  namespace: tenant-a
spec:
  limits:
    # Container limits
    - max:
        cpu: "4"              # Max CPU per container
        memory: 8Gi           # Max memory per container
      min:
        cpu: "100m"           # Min CPU per container
        memory: 128Mi         # Min memory per container
      default:
        cpu: "500m"           # Default limit
        memory: 512Mi
      defaultRequest:
        cpu: "250m"           # Default request
        memory: 256Mi
      type: Container

    # Pod limits
    - max:
        cpu: "8"              # Max CPU per pod
        memory: 16Gi          # Max memory per pod
      type: Pod

    # PVC limits
    - max:
        storage: 20Gi         # Max storage per PVC
      min:
        storage: 1Gi          # Min storage per PVC
      type: PersistentVolumeClaim
```

### Monitoring Quota Usage

**Check quota status:**
```bash
# View quota details
kubectl describe resourcequota -n tenant-a

# Output:
# Name:            compute-quota
# Namespace:       tenant-a
# Resource         Used    Hard
# --------         ----    ----
# limits.cpu       10      20
# limits.memory    20Gi    40Gi
# pods             25      50
# requests.cpu     5       10
# requests.memory  10Gi    20Gi
```

**Alert on quota threshold:**
```yaml
# Prometheus alert
- alert: ResourceQuotaNearLimit
  expr: |
    (kube_resourcequota{type="used"} / kube_resourcequota{type="hard"}) > 0.85
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "Namespace {{ $labels.namespace }} quota near limit"
    description: "{{ $labels.resource }} is at {{ $value }}% of quota"
```

---

## Network Policies

### NetworkPolicy Overview

NetworkPolicies control traffic flow between pods, providing network-level isolation between tenants.

**Default behavior:**
- Without NetworkPolicies, all pods can communicate with all pods
- NetworkPolicies are **additive** (multiple policies are OR'd together)
- Empty policy selector (`{}`) matches all pods

### Policy Patterns

**Pattern 1: Default Deny All**

Deny all ingress and egress traffic (most secure, whitelist approach):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: tenant-a
spec:
  podSelector: {}  # Apply to all pods
  policyTypes:
    - Ingress
    - Egress
```

**Pattern 2: Allow Within Namespace**

Allow communication within namespace only:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: tenant-a
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}  # All pods in same namespace
  egress:
    - to:
        - podSelector: {}  # All pods in same namespace
```

**Pattern 3: Allow DNS and Internet Egress**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-internet
  namespace: tenant-a
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # Allow DNS (kube-dns/CoreDNS)
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53

    # Allow internet egress
    - to:
        - namespaceSelector: {}
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 443
```

**Pattern 4: Allow Ingress from Specific Namespace**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-nginx
  namespace: tenant-a
spec:
  podSelector:
    matchLabels:
      app: web  # Apply to pods with label app=web
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx  # Allow from ingress-nginx namespace
      ports:
        - protocol: TCP
          port: 8080
```

### Complete Multi-Tenant Network Policy Example

**Tenant-A namespace policies:**
```yaml
# 1. Default deny all
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: tenant-a
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
# 2. Allow within namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: tenant-a
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
  egress:
    - to:
        - podSelector: {}
---
# 3. Allow DNS
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: tenant-a
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
---
# 4. Allow ingress from ingress controller
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller
  namespace: tenant-a
spec:
  podSelector:
    matchLabels:
      expose: "true"  # Only pods with this label
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
---
# 5. Allow egress to internet
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internet-egress
  namespace: tenant-a
spec:
  podSelector:
    matchLabels:
      internet-access: "true"  # Only pods with this label
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 80
---
# 6. Allow monitoring (Prometheus scraping)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: tenant-a
spec:
  podSelector:
    matchLabels:
      monitoring: "true"  # Only pods with this label
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
      ports:
        - protocol: TCP
          port: 8080  # Metrics port
```

### Testing Network Policies

**Test connectivity between namespaces:**
```bash
# Create test pods
kubectl run test-a -n tenant-a --image=busybox --restart=Never -- sleep 3600
kubectl run test-b -n tenant-b --image=busybox --restart=Never -- sleep 3600

# Test connectivity from tenant-a to tenant-b (should fail with NetworkPolicy)
kubectl exec -n tenant-a test-a -- wget -qO- --timeout=2 http://test-b.tenant-b.svc.cluster.local

# Test connectivity within tenant-a (should succeed)
kubectl exec -n tenant-a test-a -- wget -qO- --timeout=2 http://my-service.tenant-a.svc.cluster.local
```

**Debug NetworkPolicy:**
```bash
# Check NetworkPolicies in namespace
kubectl get networkpolicies -n tenant-a

# Describe NetworkPolicy
kubectl describe networkpolicy default-deny-all -n tenant-a

# Use tools like Cilium CLI for advanced debugging
cilium policy trace -s tenant-a/test-a -d tenant-b/test-b
```

---

## RBAC Configuration

### RBAC Multi-Tenancy Model

**Three-tier RBAC model for multi-tenancy:**

1. **Cluster Admins** (cluster-wide access)
   - Platform team managing Kubernetes cluster
   - Full access to all namespaces
   - ClusterRole: `cluster-admin`

2. **Namespace Admins** (namespace-scoped access)
   - Tenant administrators
   - Full access within their namespace(s)
   - Role: `namespace-admin` (custom)

3. **Namespace Users** (limited namespace access)
   - Application developers
   - Read/write access to specific resources
   - Role: `developer`, `viewer` (custom)

### Custom Roles

**Namespace Admin Role:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: namespace-admin
  namespace: tenant-a
rules:
  # Full access to most resources
  - apiGroups: ["", "apps", "batch", "extensions"]
    resources: ["*"]
    verbs: ["*"]

  # Access to networking
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["*"]

  # Access to RBAC (limited to namespace)
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # Read-only access to quotas
  - apiGroups: [""]
    resources: ["resourcequotas", "limitranges"]
    verbs: ["get", "list", "watch"]
```

**Developer Role:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: tenant-a
rules:
  # Workload resources
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # Pods and logs
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec"]
    verbs: ["get", "list", "watch", "create", "delete"]

  # Services and ingress
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # ConfigMaps and Secrets
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # Jobs and CronJobs
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # Read-only access to quotas
  - apiGroups: [""]
    resources: ["resourcequotas", "limitranges"]
    verbs: ["get", "list", "watch"]
```

**Viewer Role (read-only):**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: viewer
  namespace: tenant-a
rules:
  # Read-only access to all resources
  - apiGroups: ["", "apps", "batch", "networking.k8s.io"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
```

### RoleBindings

**Bind user to namespace-admin:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tenant-a-admin-binding
  namespace: tenant-a
subjects:
  - kind: User
    name: alice@example.com  # User from OIDC/LDAP
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: namespace-admin
  apiGroup: rbac.authorization.k8s.io
```

**Bind group to developer:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tenant-a-developers-binding
  namespace: tenant-a
subjects:
  - kind: Group
    name: tenant-a-developers  # Group from OIDC/LDAP
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

**Bind ServiceAccount to role:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-deployer-binding
  namespace: tenant-a
subjects:
  - kind: ServiceAccount
    name: ci-deployer
    namespace: tenant-a
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

### ClusterRole for Cross-Namespace Access

**Read-only access to multiple namespaces:**
```yaml
# ClusterRole for reading across namespaces
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: multi-namespace-viewer
rules:
  - apiGroups: ["", "apps"]
    resources: ["pods", "deployments", "services"]
    verbs: ["get", "list", "watch"]
---
# ClusterRoleBinding to grant access
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: alice-multi-namespace-viewer
subjects:
  - kind: User
    name: alice@example.com
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: multi-namespace-viewer
  apiGroup: rbac.authorization.k8s.io
```

### Testing RBAC

**Test user permissions:**
```bash
# Check if user can create deployment
kubectl auth can-i create deployments -n tenant-a --as alice@example.com

# Check if user can delete namespace
kubectl auth can-i delete namespace tenant-a --as alice@example.com

# List all permissions for user
kubectl auth can-i --list -n tenant-a --as alice@example.com
```

---

## Pod Security

### Pod Security Standards (PSS)

Kubernetes Pod Security Standards define three policies:

1. **Privileged** - Unrestricted (no restrictions)
2. **Baseline** - Minimally restrictive (blocks known privilege escalations)
3. **Restricted** - Highly restrictive (hardened security)

**Apply at namespace level:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-a
  labels:
    # Enforce restricted policy
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest

    # Warn on baseline violations
    pod-security.kubernetes.io/warn: baseline
    pod-security.kubernetes.io/warn-version: latest

    # Audit privileged usage
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/audit-version: latest
```

**Restricted policy requirements:**
- No privileged containers
- No host network, PID, or IPC
- No host path volumes
- Drop all capabilities
- Run as non-root user
- Read-only root filesystem

**Example compliant pod:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
  namespace: tenant-a
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: my-app:latest
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir: {}
```

### PodSecurityPolicy (Deprecated)

**Note**: PodSecurityPolicy is deprecated in Kubernetes 1.21+ and removed in 1.25+. Use Pod Security Standards instead.

---

## Storage Isolation

### StorageClass per Tenant

Create dedicated StorageClasses for tenant isolation:

```yaml
# Fast SSD storage for tenant-a
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: tenant-a-fast
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
volumeBindingMode: WaitForFirstConsumer
allowedTopologies:
  - matchLabelExpressions:
      - key: topology.kubernetes.io/zone
        values:
          - us-east-1a
---
# Standard storage for tenant-a
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: tenant-a-standard
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
volumeBindingMode: WaitForFirstConsumer
```

### PVC Resource Quotas

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storage-quota
  namespace: tenant-a
spec:
  hard:
    # Total PVC count
    persistentvolumeclaims: "10"

    # Total storage across all PVCs
    requests.storage: "100Gi"

    # Storage class specific quotas
    tenant-a-fast.storageclass.storage.k8s.io/requests.storage: "50Gi"
    tenant-a-fast.storageclass.storage.k8s.io/persistentvolumeclaims: "5"

    tenant-a-standard.storageclass.storage.k8s.io/requests.storage: "50Gi"
    tenant-a-standard.storageclass.storage.k8s.io/persistentvolumeclaims: "5"
```

---

## Monitoring & Observability

### Per-Tenant Monitoring

**Prometheus scrape configs per tenant:**
```yaml
# Prometheus scrape config
scrape_configs:
  - job_name: 'tenant-a-pods'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - tenant-a
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace]
        action: keep
        regex: tenant-a
      - source_labels: [__meta_kubernetes_namespace]
        target_label: tenant
        replacement: tenant-a
```

**Grafana multi-tenancy:**
```yaml
# Grafana datasource with namespace filtering
apiVersion: 1
datasources:
  - name: Prometheus-Tenant-A
    type: prometheus
    url: http://prometheus:9090
    jsonData:
      httpMethod: POST
      # Filter queries to tenant-a namespace
      customQueryParameters: "namespace=tenant-a"
```

### Cost Tracking

**Track costs per tenant using labels:**
```bash
# Prometheus query for CPU usage by tenant
sum(rate(container_cpu_usage_seconds_total{namespace="tenant-a"}[5m])) * 3600 * 24 * 30 * 0.05

# Memory usage by tenant
sum(container_memory_working_set_bytes{namespace="tenant-a"}) / 1024 / 1024 / 1024 * 30 * 0.01
```

---

## Best Practices

### 1. Namespace Design

- ✅ Use consistent naming conventions (e.g., `<tenant>-<environment>`)
- ✅ Add comprehensive labels and annotations
- ✅ Limit number of namespaces per cluster (<100)
- ❌ Don't use default namespace for tenants

### 2. Resource Management

- ✅ Always set ResourceQuotas for tenant namespaces
- ✅ Use LimitRanges to enforce default limits
- ✅ Size quotas based on tenant tier (small/medium/large)
- ✅ Monitor quota usage and alert on thresholds
- ❌ Don't allow unlimited resources

### 3. Network Security

- ✅ Start with default-deny-all NetworkPolicy
- ✅ Explicitly allow required traffic
- ✅ Isolate tenants at network level
- ✅ Allow DNS and monitoring traffic
- ❌ Don't allow unrestricted cross-namespace communication

### 4. RBAC

- ✅ Follow principle of least privilege
- ✅ Use groups instead of individual users
- ✅ Create custom roles for tenant personas
- ✅ Regular RBAC audits
- ❌ Don't grant cluster-admin to tenants

### 5. Security

- ✅ Enforce Pod Security Standards (Baseline or Restricted)
- ✅ Use separate StorageClasses per tenant
- ✅ Enable audit logging for compliance
- ✅ Scan images for vulnerabilities
- ❌ Don't allow privileged containers for tenants

### 6. Monitoring

- ✅ Per-tenant monitoring dashboards
- ✅ Cost tracking and chargeback
- ✅ Resource usage alerts
- ✅ SLI/SLO tracking per tenant
- ❌ Don't expose cross-tenant metrics

---

## Implementation Examples

### Example 1: SaaS Platform with Multiple Customers

**Scenario:** SaaS platform with 50 customers, each requiring isolation.

**Implementation:**
- **Model:** Namespace-based isolation
- **Pattern:** One namespace per customer (`customer-<id>`)
- **Security:** Restricted PodSecurityStandard, strict NetworkPolicies
- **Resources:** Tiered ResourceQuotas (small/medium/large)
- **Storage:** Shared StorageClass with per-namespace quotas
- **Monitoring:** Per-customer Grafana dashboards

**Provisioning:**
```bash
# Create customer namespace
./tenant-provision.sh customer-123 production saas-platform customer-123@example.com

# Apply security policies
kubectl apply -f networkpolicy-strict.yaml -n customer-123
kubectl label namespace customer-123 pod-security.kubernetes.io/enforce=restricted

# Set tier-based quota (medium tier)
kubectl apply -f resourcequota-medium.yaml -n customer-123
```

### Example 2: Enterprise with Multiple Teams

**Scenario:** Large enterprise with 20 engineering teams sharing cluster.

**Implementation:**
- **Model:** Namespace-based isolation with hierarchical structure
- **Pattern:** `<org>-<team>-<environment>`
- **Security:** Baseline PodSecurityStandard, moderate NetworkPolicies
- **Resources:** Generous ResourceQuotas, allow inter-team communication
- **Storage:** Shared StorageClasses
- **Monitoring:** Org-wide monitoring, team-specific dashboards

**Structure:**
```
├── eng-frontend-prod
├── eng-frontend-staging
├── eng-backend-prod
├── eng-backend-staging
├── eng-data-prod
├── eng-data-staging
```

### Example 3: Regulated Workloads (Banking, Healthcare)

**Scenario:** Financial institution with strict compliance requirements.

**Implementation:**
- **Model:** Node-based isolation (dedicated nodes per tenant)
- **Pattern:** Namespace + node affinity
- **Security:** Restricted PodSecurityStandard, zero-trust NetworkPolicies
- **Resources:** Strict ResourceQuotas, guaranteed resources
- **Storage:** Encrypted StorageClasses per tenant
- **Monitoring:** Audit logging, compliance reporting

**Node configuration:**
```bash
# Taint nodes for specific tenant
kubectl taint nodes node1 tenant=banking-app:NoSchedule

# Label nodes
kubectl label nodes node1 tenant=banking-app
```

**Pod with toleration:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: banking-app
  namespace: banking-app-prod
spec:
  nodeSelector:
    tenant: banking-app
  tolerations:
    - key: tenant
      operator: Equal
      value: banking-app
      effect: NoSchedule
  # ... rest of pod spec
```

---

## Appendix: Quick Reference

### Checklist for Tenant Onboarding

- [ ] Create namespace(s) with proper labels/annotations
- [ ] Apply ResourceQuota (CPU, memory, storage, objects)
- [ ] Apply LimitRange (default limits and requests)
- [ ] Create NetworkPolicies (default-deny, allow-same-namespace, allow-dns)
- [ ] Set Pod Security Standard (enforce baseline/restricted)
- [ ] Create RBAC roles (namespace-admin, developer, viewer)
- [ ] Create RoleBindings for users/groups
- [ ] Create ServiceAccounts for CI/CD
- [ ] Configure monitoring (Prometheus scrape, Grafana dashboard)
- [ ] Document runbooks and contact information
- [ ] Test access and connectivity
- [ ] Enable cost tracking and billing

### Common kubectl Commands

```bash
# List all namespaces with labels
kubectl get namespaces --show-labels

# Get resource quota usage
kubectl describe resourcequota -n tenant-a

# Test RBAC permissions
kubectl auth can-i create pods -n tenant-a --as user@example.com

# List NetworkPolicies
kubectl get networkpolicies -n tenant-a

# View pod security admission labels
kubectl get namespace tenant-a -o yaml | grep pod-security

# Get resource usage by namespace
kubectl top pods -n tenant-a

# List all resources in namespace
kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get -n tenant-a
```

---

**Document Version**: 1.0
**Last Updated**: 2025-01-27
**Maintained by**: ScriptonBasestar
**Related**: [Observability Stack Guide](observability-stack-guide.md)
