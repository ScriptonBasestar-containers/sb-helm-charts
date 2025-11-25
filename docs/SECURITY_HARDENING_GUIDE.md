# Security Hardening Guide

Comprehensive security hardening guide for Kubernetes deployments using ScriptonBasestar Helm charts.

## Overview

This guide covers security best practices for deploying and operating workloads in Kubernetes. It follows defense-in-depth principles and aligns with industry standards including CIS Kubernetes Benchmark and NIST guidelines.

## Pod Security Standards (PSS)

Kubernetes Pod Security Standards define three policy levels for pod security.

### Policy Levels

| Level | Description | Use Case |
|-------|-------------|----------|
| **Privileged** | Unrestricted | System components, CNI |
| **Baseline** | Minimally restrictive | General workloads |
| **Restricted** | Heavily restricted | Security-sensitive apps |

### Namespace Labels

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Chart Configuration

Most charts support PSS-compliant configuration:

```yaml
# values.yaml - Restricted PSS compliant
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

### Per-Chart Security Contexts

**Grafana:**
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 472
  runAsGroup: 472
  fsGroup: 472

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false  # Grafana needs write access
  capabilities:
    drop: [ALL]
```

**Prometheus:**
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 65534
  runAsGroup: 65534
  fsGroup: 65534

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
```

**PostgreSQL:**
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 999
  runAsGroup: 999
  fsGroup: 999

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false  # Database needs write
  capabilities:
    drop: [ALL]
```

## Network Policies

### Default Deny All

Start with deny-all policy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### Allow Specific Traffic

**Prometheus scraping:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: prometheus
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 9090
        - protocol: TCP
          port: 9100
        - protocol: TCP
          port: 8080
```

**Grafana to data sources:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: grafana-egress
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: grafana
  policyTypes:
    - Egress
  egress:
    # Prometheus
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: prometheus
      ports:
        - protocol: TCP
          port: 9090
    # Loki
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: loki
      ports:
        - protocol: TCP
          port: 3100
    # Tempo
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: tempo
      ports:
        - protocol: TCP
          port: 3200
    # DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
```

**Database access:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgresql-ingress
  namespace: database
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: postgresql
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              access-database: "true"
        - podSelector:
            matchLabels:
              database-access: "true"
      ports:
        - protocol: TCP
          port: 5432
```

### Chart Integration

Enable NetworkPolicy in chart values:

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: database
      ports:
        - port: 5432
```

## RBAC Best Practices

### Principle of Least Privilege

**Minimal ServiceAccount:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: production
automountServiceAccountToken: false  # Disable unless needed
```

**Scoped Role (namespace-level):**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-role
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
    resourceNames: ["app-config"]  # Specific resources only
```

**ClusterRole for monitoring:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-reader
rules:
  - apiGroups: [""]
    resources:
      - nodes
      - nodes/metrics
      - services
      - endpoints
      - pods
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get"]
  - nonResourceURLs: ["/metrics"]
    verbs: ["get"]
```

### Chart RBAC Configuration

```yaml
serviceAccount:
  create: true
  name: ""
  annotations: {}
  automountServiceAccountToken: false

rbac:
  create: true
  rules: []  # Custom rules if needed
```

### Audit RBAC

Check excessive permissions:

```bash
# List cluster-admin bindings
kubectl get clusterrolebindings -o json | \
  jq '.items[] | select(.roleRef.name=="cluster-admin") | .subjects'

# Check ServiceAccount permissions
kubectl auth can-i --list --as=system:serviceaccount:production:app-sa
```

## Container Security

### Non-Root Containers

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
```

### Read-Only Root Filesystem

```yaml
securityContext:
  readOnlyRootFilesystem: true

# Mount writable volumes for temp files
volumeMounts:
  - name: tmp
    mountPath: /tmp
  - name: cache
    mountPath: /var/cache

volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
```

### Drop All Capabilities

```yaml
securityContext:
  capabilities:
    drop:
      - ALL
    # Add only what's needed
    add:
      - NET_BIND_SERVICE  # For ports < 1024
```

### Seccomp Profiles

```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault
```

Custom seccomp profile:
```yaml
securityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: profiles/custom-profile.json
```

### AppArmor (if available)

```yaml
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/app: runtime/default
```

## Secret Management

### Kubernetes Secrets Best Practices

**Encryption at rest:**
```yaml
# EncryptionConfiguration
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-key>
      - identity: {}
```

**External Secrets Operator:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-secret
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: production/database
        property: password
```

**Sealed Secrets:**
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: database-secret
  namespace: production
spec:
  encryptedData:
    password: AgBy8hCi8...encrypted...
```

### Secret Rotation

**Using ExternalSecret with rotation:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rotating-secret
spec:
  refreshInterval: 15m  # Check for updates every 15 minutes
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: app-secret
    template:
      metadata:
        annotations:
          reloader.stakater.com/match: "true"  # Trigger pod restart
  data:
    - secretKey: api-key
      remoteRef:
        key: production/api
        property: key
```

### Chart Secret Configuration

```yaml
# Avoid plaintext in values.yaml
existingSecret: "pre-created-secret"

# Or use external secret reference
externalSecret:
  enabled: true
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  data:
    - secretKey: password
      remoteRef:
        key: path/to/secret
```

## Image Security

### Image Pull Policies

```yaml
image:
  repository: grafana/grafana
  tag: "11.2.0"
  pullPolicy: IfNotPresent  # Use Always for :latest

imagePullSecrets:
  - name: registry-credentials
```

### Use Digests Instead of Tags

```yaml
image:
  repository: grafana/grafana
  digest: sha256:abc123...  # Immutable reference
```

### Private Registry

```yaml
# Create registry secret
kubectl create secret docker-registry registry-creds \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass \
  --namespace=production

# Reference in values
imagePullSecrets:
  - name: registry-creds
```

### Image Scanning

Integrate with admission controllers:

```yaml
# Kyverno policy for signed images
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-signature
      match:
        resources:
          kinds:
            - Pod
      verifyImages:
        - imageReferences:
            - "registry.example.com/*"
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      ...
                      -----END PUBLIC KEY-----
```

## Ingress Security

### TLS Configuration

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
  hosts:
    - host: app.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: app-tls
      hosts:
        - app.example.com
```

### Security Headers

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-XSS-Protection "1; mode=block" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;
      add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';" always;
```

### Rate Limiting

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "10"
    nginx.ingress.kubernetes.io/limit-connections: "5"
    nginx.ingress.kubernetes.io/limit-rpm: "100"
```

### IP Whitelisting

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,192.168.0.0/16"
```

### Authentication

```yaml
ingress:
  annotations:
    # Basic auth
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"

    # Or OAuth2 proxy
    nginx.ingress.kubernetes.io/auth-url: "https://oauth2.example.com/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://oauth2.example.com/oauth2/start"
```

## Resource Limits

### Define Limits and Requests

```yaml
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
    ephemeral-storage: 2Gi
  requests:
    cpu: 100m
    memory: 128Mi
    ephemeral-storage: 500Mi
```

### LimitRange for Namespace

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
    - default:
        cpu: 500m
        memory: 512Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      type: Container
```

### ResourceQuota

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-quota
  namespace: production
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    pods: "50"
    secrets: "20"
    configmaps: "20"
```

## Audit Logging

### Enable Kubernetes Audit Logging

```yaml
# Audit policy
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log all requests at Metadata level
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]

  # Log pod exec at RequestResponse level
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["pods/exec", "pods/portforward"]

  # Don't log read-only endpoints
  - level: None
    users: ["system:kube-proxy"]
    verbs: ["watch"]
    resources:
      - group: ""
        resources: ["endpoints", "services"]
```

### Application Audit Logging

Configure apps to log security events:

**Keycloak:**
```yaml
extraEnv:
  - name: KC_LOG_LEVEL
    value: "INFO"
  - name: KC_SPI_EVENTS_LISTENER_JBOSS_LOGGING_SUCCESS_LEVEL
    value: "info"
  - name: KC_SPI_EVENTS_LISTENER_JBOSS_LOGGING_ERROR_LEVEL
    value: "warn"
```

**Grafana:**
```yaml
grafana.ini:
  log:
    mode: console
    level: info
  security:
    disable_gravatar: true
    cookie_secure: true
```

## Security Checklist

### Pre-Deployment

- [ ] Review and minimize RBAC permissions
- [ ] Enable Pod Security Standards enforcement
- [ ] Configure NetworkPolicies
- [ ] Set resource limits and requests
- [ ] Use non-root containers
- [ ] Enable read-only root filesystem where possible
- [ ] Drop all capabilities
- [ ] Configure seccomp profiles
- [ ] Use image digests or pinned versions
- [ ] Scan images for vulnerabilities
- [ ] Encrypt secrets at rest
- [ ] Configure TLS for ingress

### Runtime

- [ ] Enable audit logging
- [ ] Monitor security events
- [ ] Implement secret rotation
- [ ] Regular security scanning
- [ ] Review and rotate credentials
- [ ] Update images regularly

### Per-Chart Checklist

```yaml
# Minimum security configuration
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true  # if supported
  capabilities:
    drop: [ALL]

serviceAccount:
  create: true
  automountServiceAccountToken: false

networkPolicy:
  enabled: true

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 100m
    memory: 128Mi
```

## Tools and Resources

### Security Scanning

- **Trivy**: Container and config scanning
- **Kubescape**: Kubernetes security scanning
- **Falco**: Runtime security monitoring
- **OPA/Gatekeeper**: Policy enforcement

### Useful Commands

```bash
# Check pod security context
kubectl get pod <pod> -o jsonpath='{.spec.securityContext}'

# List pods running as root
kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[].securityContext.runAsUser == 0 or .spec.securityContext.runAsUser == 0) | .metadata.name'

# Check NetworkPolicies
kubectl get networkpolicies -A

# Verify RBAC
kubectl auth can-i --list --as=system:serviceaccount:namespace:sa-name

# Scan with Trivy
trivy k8s --report summary cluster
```

## References

- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST Container Security Guide](https://csrc.nist.gov/publications/detail/sp/800-190/final)
- [NSA/CISA Kubernetes Hardening Guide](https://www.nsa.gov/Press-Room/News-Highlights/Article/Article/2716980/)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)

---

**Created**: 2025-11-25
**Maintained by**: ScriptonBasestar
