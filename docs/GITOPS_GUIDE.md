# GitOps Guide

Deploy ScriptonBasestar Helm charts using GitOps workflows with ArgoCD or Flux.

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [ArgoCD Deployment](#argocd-deployment)
- [Flux Deployment](#flux-deployment)
- [Secrets Management](#secrets-management)
- [Multi-Environment Setup](#multi-environment-setup)
- [Best Practices](#best-practices)

## Overview

GitOps enables declarative infrastructure management where Git repositories serve as the single source of truth. This guide covers deploying sb-helm-charts using:

- **ArgoCD** - Kubernetes-native continuous delivery
- **Flux** - GitOps toolkit for Kubernetes

### Prerequisites

- Kubernetes 1.24+
- ArgoCD 2.8+ or Flux v2
- Helm 3.8+
- kubectl configured

## Repository Structure

Recommended GitOps repository layout:

```
gitops-repo/
├── apps/                      # Application definitions
│   ├── base/                  # Base configurations
│   │   ├── monitoring/
│   │   │   ├── prometheus.yaml
│   │   │   ├── grafana.yaml
│   │   │   └── loki.yaml
│   │   └── apps/
│   │       ├── keycloak.yaml
│   │       └── nextcloud.yaml
│   └── overlays/              # Environment-specific
│       ├── dev/
│       ├── staging/
│       └── production/
├── infrastructure/            # Cluster infrastructure
│   ├── namespaces/
│   └── secrets/
└── clusters/                  # Cluster-specific configs
    ├── dev-cluster/
    ├── staging-cluster/
    └── prod-cluster/
```

## ArgoCD Deployment

### 1. Add Helm Repository

```yaml
# infrastructure/helm-repos/sb-charts.yaml
apiVersion: v1
kind: Secret
metadata:
  name: sb-helm-charts
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  name: sb-charts
  url: https://scriptonbasestar-containers.github.io/sb-helm-charts
  type: helm
```

### 2. Application Definition

**Single Application:**

```yaml
# apps/base/monitoring/prometheus.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://scriptonbasestar-containers.github.io/sb-helm-charts
    targetRevision: 0.3.0
    chart: prometheus
    helm:
      releaseName: prometheus
      valuesObject:
        persistence:
          enabled: true
          size: 50Gi

        retention: "30d"

        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 4Gi

        ingress:
          enabled: true
          className: nginx
          hosts:
            - prometheus.example.com

  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### 3. ApplicationSet for Multiple Environments

```yaml
# clusters/applicationset-monitoring.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: monitoring-stack
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - matrix:
        generators:
          - list:
              elements:
                - cluster: dev
                  url: https://dev-cluster.example.com
                  values: values-home-single.yaml
                - cluster: staging
                  url: https://staging-cluster.example.com
                  values: values-startup-single.yaml
                - cluster: production
                  url: https://prod-cluster.example.com
                  values: values-prod-master-replica.yaml
          - list:
              elements:
                - app: prometheus
                  chart: prometheus
                  version: "0.3.0"
                - app: grafana
                  chart: grafana
                  version: "0.3.0"
                - app: loki
                  chart: loki
                  version: "0.3.0"
  template:
    metadata:
      name: "{{ .cluster }}-{{ .app }}"
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://scriptonbasestar-containers.github.io/sb-helm-charts
        targetRevision: "{{ .version }}"
        chart: "{{ .chart }}"
        helm:
          releaseName: "{{ .app }}"
          valueFiles:
            - "$values/{{ .cluster }}/monitoring/{{ .values }}"
      sources:
        - repoURL: https://github.com/your-org/gitops-repo.git
          targetRevision: main
          ref: values
      destination:
        server: "{{ .url }}"
        namespace: monitoring
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### 4. App of Apps Pattern

```yaml
# clusters/prod-cluster/apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo.git
    targetRevision: main
    path: apps/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 5. Keycloak with External Database

```yaml
# apps/base/apps/keycloak.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://scriptonbasestar-containers.github.io/sb-helm-charts
    targetRevision: 0.3.0
    chart: keycloak
    helm:
      releaseName: keycloak
      valuesObject:
        keycloak:
          adminUser: admin
          hostname: auth.example.com

        postgresql:
          enabled: false
          external:
            enabled: true
            host: postgres.database.svc.cluster.local
            port: 5432
            database: keycloak
            username: keycloak

        # Reference external secret for password
        extraEnv:
          - name: KC_DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: keycloak-db-credentials
                key: password

        ingress:
          enabled: true
          className: nginx
          hosts:
            - auth.example.com
          tls:
            - secretName: keycloak-tls
              hosts:
                - auth.example.com

  destination:
    server: https://kubernetes.default.svc
    namespace: auth

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Flux Deployment

### 1. Add Helm Repository

```yaml
# infrastructure/helm-repos/sb-charts.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: sb-charts
  namespace: flux-system
spec:
  interval: 1h
  url: https://scriptonbasestar-containers.github.io/sb-helm-charts
```

### 2. HelmRelease Definition

**Single Application:**

```yaml
# apps/base/monitoring/prometheus.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: prometheus
  namespace: monitoring
spec:
  interval: 30m
  chart:
    spec:
      chart: prometheus
      version: "0.3.0"
      sourceRef:
        kind: HelmRepository
        name: sb-charts
        namespace: flux-system
      interval: 12h

  install:
    createNamespace: true
    remediation:
      retries: 3

  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true

  values:
    persistence:
      enabled: true
      size: 50Gi

    retention: "30d"

    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 2000m
        memory: 4Gi

    ingress:
      enabled: true
      className: nginx
      hosts:
        - prometheus.example.com
```

### 3. Kustomization for Environment Overlays

**Base Kustomization:**

```yaml
# apps/base/monitoring/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - prometheus.yaml
  - grafana.yaml
  - loki.yaml
  - promtail.yaml
```

**Production Overlay:**

```yaml
# apps/overlays/production/monitoring/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../base/monitoring

patches:
  - target:
      kind: HelmRelease
      name: prometheus
    patch: |
      - op: replace
        path: /spec/values/persistence/size
        value: 100Gi
      - op: replace
        path: /spec/values/resources/limits/memory
        value: 8Gi
```

### 4. Flux Kustomization Controller

```yaml
# clusters/prod-cluster/monitoring.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: monitoring
  namespace: flux-system
spec:
  interval: 10m
  targetNamespace: monitoring
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/overlays/production/monitoring
  prune: true
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: prometheus
      namespace: monitoring
    - apiVersion: apps/v1
      kind: Deployment
      name: grafana
      namespace: monitoring
```

### 5. Complete Observability Stack

```yaml
# apps/base/monitoring/observability-stack.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: prometheus
  namespace: monitoring
spec:
  interval: 30m
  chart:
    spec:
      chart: prometheus
      version: "0.3.0"
      sourceRef:
        kind: HelmRepository
        name: sb-charts
        namespace: flux-system
  values:
    persistence:
      enabled: true
      size: 50Gi
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: loki
  namespace: monitoring
spec:
  interval: 30m
  chart:
    spec:
      chart: loki
      version: "0.3.0"
      sourceRef:
        kind: HelmRepository
        name: sb-charts
        namespace: flux-system
  values:
    persistence:
      enabled: true
      size: 50Gi
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: grafana
  namespace: monitoring
spec:
  interval: 30m
  dependsOn:
    - name: prometheus
    - name: loki
  chart:
    spec:
      chart: grafana
      version: "0.3.0"
      sourceRef:
        kind: HelmRepository
        name: sb-charts
        namespace: flux-system
  values:
    persistence:
      enabled: true
      size: 10Gi
```

## Secrets Management

### Option 1: SOPS (Recommended)

**Encrypt secrets with SOPS:**

```bash
# Create age key
age-keygen -o age.agekey

# Configure SOPS
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: .*\.enc\.yaml$
    age: age1...
EOF

# Encrypt secret
sops --encrypt secrets/keycloak-db.yaml > secrets/keycloak-db.enc.yaml
```

**Flux SOPS Integration:**

```yaml
# clusters/prod-cluster/flux-system/gotk-sync.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

### Option 2: Sealed Secrets

```bash
# Seal a secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml
```

```yaml
# infrastructure/secrets/keycloak-db.yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: keycloak-db-credentials
  namespace: auth
spec:
  encryptedData:
    password: AgBy8hCF...encrypted...
```

### Option 3: External Secrets Operator

```yaml
# infrastructure/secrets/keycloak-db.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: keycloak-db-credentials
  namespace: auth
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: keycloak-db-credentials
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: secret/data/keycloak
        property: db_password
```

## Multi-Environment Setup

### Environment Values Structure

```
values/
├── dev/
│   ├── monitoring/
│   │   ├── prometheus.yaml
│   │   └── grafana.yaml
│   └── apps/
│       └── keycloak.yaml
├── staging/
│   └── ...
└── production/
    └── ...
```

### Dev Environment Values

```yaml
# values/dev/monitoring/prometheus.yaml
persistence:
  size: 10Gi

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 1Gi

retention: "7d"
```

### Production Environment Values

```yaml
# values/production/monitoring/prometheus.yaml
persistence:
  size: 100Gi
  storageClass: fast-ssd

resources:
  requests:
    cpu: 1000m
    memory: 4Gi
  limits:
    cpu: 4000m
    memory: 16Gi

retention: "90d"

podDisruptionBudget:
  enabled: true
  minAvailable: 1

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: prometheus
        topologyKey: kubernetes.io/hostname
```

## Best Practices

### 1. Version Pinning

Always pin chart versions:

```yaml
# Good
chart:
  spec:
    chart: prometheus
    version: "0.3.0"

# Bad - uses latest
chart:
  spec:
    chart: prometheus
```

### 2. Health Checks

Add health checks for critical deployments:

```yaml
# Flux
healthChecks:
  - apiVersion: apps/v1
    kind: Deployment
    name: prometheus
    namespace: monitoring
```

### 3. Sync Waves (ArgoCD)

Control deployment order:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Deploy infrastructure first
```

### 4. Dependency Management (Flux)

```yaml
spec:
  dependsOn:
    - name: prometheus
    - name: postgresql
```

### 5. Notifications

**ArgoCD Notifications:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: monitoring-alerts
```

**Flux Alerts:**

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: slack-alert
  namespace: flux-system
spec:
  providerRef:
    name: slack
  eventSeverity: error
  eventSources:
    - kind: HelmRelease
      namespace: monitoring
      name: "*"
```

### 6. Rollback Strategy

**ArgoCD:**
- Manual: `argocd app rollback <app-name>`
- Automatic: Configure sync policy

**Flux:**
```yaml
spec:
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
  rollback:
    cleanupOnFail: true
```

## Troubleshooting

### ArgoCD

```bash
# Check application status
argocd app get prometheus

# Force sync
argocd app sync prometheus --force

# View logs
argocd app logs prometheus
```

### Flux

```bash
# Check HelmRelease status
flux get helmrelease -n monitoring

# Reconcile immediately
flux reconcile helmrelease prometheus -n monitoring

# View events
kubectl describe helmrelease prometheus -n monitoring
```

## Related Documentation

- [Observability Stack Guide](OBSERVABILITY_STACK_GUIDE.md)
- [Production Checklist](PRODUCTION_CHECKLIST.md)
- [Chart Development Guide](CHART_DEVELOPMENT_GUIDE.md)
- [Grafana Dashboards](../dashboards/)

## External Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Flux Documentation](https://fluxcd.io/docs/)
- [SOPS Documentation](https://github.com/getsops/sops)
- [External Secrets Operator](https://external-secrets.io/)
