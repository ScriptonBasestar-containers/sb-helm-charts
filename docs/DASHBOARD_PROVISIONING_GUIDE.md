# Dashboard Provisioning Guide

Comprehensive guide for provisioning Grafana dashboards in Kubernetes environments.

## Overview

This guide covers multiple approaches to dashboard provisioning:

1. **ConfigMap-based**: Kubernetes-native, GitOps-friendly
2. **Sidecar injection**: Auto-discovery with label selectors
3. **Dashboard providers**: Grafana-native file-based loading
4. **API provisioning**: Programmatic deployment

## Quick Start

### Basic ConfigMap Provisioning

```bash
# Create ConfigMap from dashboard files
kubectl create configmap grafana-dashboards \
  --from-file=dashboards/ \
  -n monitoring

# Add label for Grafana sidecar discovery
kubectl label configmap grafana-dashboards grafana_dashboard=1 -n monitoring
```

## Provisioning Methods

### Method 1: Grafana Sidecar (Recommended)

The Grafana sidecar automatically watches for ConfigMaps with specific labels and loads dashboards.

**Grafana Helm Values:**

```yaml
grafana:
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      folder: /tmp/dashboards
      folderAnnotation: grafana_folder
      provider:
        name: sidecarProvider
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        allowUiUpdates: true
```

**Dashboard ConfigMap:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
  annotations:
    grafana_folder: "Observability"
data:
  prometheus-overview.json: |
    {
      "annotations": { ... },
      "title": "Prometheus Overview",
      ...
    }
```

**Benefits:**
- Auto-reload on ConfigMap changes
- GitOps-friendly (store ConfigMaps in Git)
- No Grafana restart required
- Folder organization via annotations

### Method 2: Dashboard Providers

Use Grafana's built-in dashboard provisioning with file providers.

**Dashboard Provider ConfigMap:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-providers
  namespace: monitoring
data:
  providers.yaml: |
    apiVersion: 1
    providers:
      - name: 'observability'
        orgId: 1
        folder: 'Observability'
        folderUid: 'observability'
        type: file
        disableDeletion: false
        editable: true
        updateIntervalSeconds: 30
        allowUiUpdates: true
        options:
          path: /var/lib/grafana/dashboards/observability

      - name: 'kubernetes'
        orgId: 1
        folder: 'Kubernetes'
        folderUid: 'kubernetes'
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/kubernetes
```

**Grafana Helm Values:**

```yaml
grafana:
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: 'Default'
          type: file
          disableDeletion: false
          options:
            path: /var/lib/grafana/dashboards

  dashboardsConfigMaps:
    default: grafana-dashboards-default
    observability: grafana-dashboards-observability
```

### Method 3: Kustomize Integration

Organize dashboards with Kustomize for GitOps workflows.

**Directory Structure:**

```
dashboards/
├── base/
│   ├── kustomization.yaml
│   ├── prometheus-overview.json
│   ├── loki-overview.json
│   └── configmap.yaml
├── overlays/
│   ├── production/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   │       └── add-prod-annotations.yaml
│   └── staging/
│       └── kustomization.yaml
```

**base/kustomization.yaml:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

configMapGenerator:
  - name: grafana-dashboards
    namespace: monitoring
    files:
      - prometheus-overview.json
      - loki-overview.json
    options:
      labels:
        grafana_dashboard: "1"

generatorOptions:
  disableNameSuffixHash: true
```

**overlays/production/kustomization.yaml:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patches:
  - target:
      kind: ConfigMap
      name: grafana-dashboards
    patch: |
      - op: add
        path: /metadata/annotations
        value:
          grafana_folder: "Production"
```

### Method 4: Helm Chart Integration

Include dashboards directly in Helm chart deployment.

**Chart Structure:**

```
charts/my-app/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment.yaml
│   └── grafana-dashboard.yaml
└── dashboards/
    └── my-app-dashboard.json
```

**templates/grafana-dashboard.yaml:**

```yaml
{{- if .Values.monitoring.dashboard.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "my-app.fullname" . }}-dashboard
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
    grafana_dashboard: "1"
  annotations:
    grafana_folder: {{ .Values.monitoring.dashboard.folder | quote }}
data:
  {{ .Release.Name }}-dashboard.json: |-
{{ .Files.Get "dashboards/my-app-dashboard.json" | indent 4 }}
{{- end }}
```

**values.yaml:**

```yaml
monitoring:
  dashboard:
    enabled: true
    folder: "Applications"
```

### Method 5: ArgoCD with Dashboard Sync

Use ArgoCD to sync dashboards from Git.

**ArgoCD Application:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: grafana-dashboards
  namespace: argocd
spec:
  project: monitoring
  source:
    repoURL: https://github.com/org/dashboards.git
    targetRevision: main
    path: dashboards/kubernetes
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Method 6: Grafana API Provisioning

Programmatically deploy dashboards using the Grafana API.

**Bash Script:**

```bash
#!/bin/bash
GRAFANA_URL="http://grafana.monitoring.svc.cluster.local:3000"
GRAFANA_API_KEY="${GRAFANA_API_KEY}"

for dashboard in dashboards/*.json; do
  filename=$(basename "$dashboard")

  # Wrap dashboard JSON for API
  payload=$(jq -n --slurpfile dash "$dashboard" '{
    "dashboard": $dash[0],
    "overwrite": true,
    "folderId": 0
  }')

  curl -X POST "${GRAFANA_URL}/api/dashboards/db" \
    -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload"

  echo "Deployed: $filename"
done
```

**Kubernetes Job:**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: dashboard-provisioner
  namespace: monitoring
spec:
  template:
    spec:
      containers:
        - name: provisioner
          image: curlimages/curl:8.5.0
          command: ["/bin/sh", "-c"]
          args:
            - |
              for f in /dashboards/*.json; do
                curl -X POST "http://grafana:3000/api/dashboards/db" \
                  -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
                  -H "Content-Type: application/json" \
                  -d "{\"dashboard\": $(cat $f), \"overwrite\": true}"
              done
          env:
            - name: GRAFANA_API_KEY
              valueFrom:
                secretKeyRef:
                  name: grafana-api-key
                  key: api-key
          volumeMounts:
            - name: dashboards
              mountPath: /dashboards
      restartPolicy: OnFailure
      volumes:
        - name: dashboards
          configMap:
            name: grafana-dashboards
```

## Dashboard Organization

### Folder Structure

Organize dashboards by category:

```
Grafana Folders:
├── Observability/
│   ├── Prometheus Overview
│   ├── Loki Overview
│   └── Tempo Overview
├── Kubernetes/
│   ├── Cluster Overview
│   ├── Node Metrics
│   └── Pod Metrics
├── Applications/
│   ├── App Service A
│   └── App Service B
└── Infrastructure/
    ├── Database Metrics
    └── Message Queue Metrics
```

### Folder Annotations

Use annotations to specify target folders:

```yaml
metadata:
  annotations:
    grafana_folder: "Observability"
    # Or use folder UID for consistency
    k8s-sidecar-target-directory: "/tmp/dashboards/observability"
```

## Dashboard Versioning

### Git-based Versioning

Store dashboards in Git with version tags:

```bash
# Tag dashboard versions
git tag -a "dashboards-v1.0.0" -m "Initial dashboard release"

# Reference specific versions in ArgoCD
targetRevision: dashboards-v1.0.0
```

### Dashboard UID Management

Use consistent UIDs for stable references:

```json
{
  "uid": "prometheus-overview",
  "title": "Prometheus Overview",
  "version": 1
}
```

**Benefits:**
- Stable URLs for bookmarks
- Consistent cross-references
- Predictable API endpoints

## Multi-Cluster Provisioning

### Centralized Dashboard Repository

```
dashboards-repo/
├── shared/                    # Dashboards for all clusters
│   ├── kubernetes-cluster.json
│   └── prometheus-overview.json
├── production/               # Production-specific
│   └── slo-dashboard.json
└── staging/                  # Staging-specific
    └── debug-dashboard.json
```

### Cluster-Specific Datasources

Use variables for multi-cluster support:

```json
{
  "templating": {
    "list": [
      {
        "name": "datasource",
        "type": "datasource",
        "query": "prometheus",
        "current": {}
      },
      {
        "name": "cluster",
        "type": "custom",
        "query": "production,staging,development",
        "current": {
          "value": "production"
        }
      }
    ]
  }
}
```

## Troubleshooting

### Dashboard Not Loading

1. **Check ConfigMap labels:**
   ```bash
   kubectl get configmap -n monitoring -l grafana_dashboard=1
   ```

2. **Verify sidecar logs:**
   ```bash
   kubectl logs -n monitoring deploy/grafana -c grafana-sc-dashboard
   ```

3. **Check dashboard JSON validity:**
   ```bash
   jq . dashboards/prometheus-overview.json > /dev/null && echo "Valid"
   ```

### Sidecar Not Detecting Changes

1. **Check label selector:**
   ```bash
   kubectl get configmap grafana-dashboards -n monitoring -o yaml | grep grafana_dashboard
   ```

2. **Force sidecar reload:**
   ```bash
   kubectl rollout restart deploy/grafana -n monitoring
   ```

### Dashboard UID Conflicts

1. **Check for duplicate UIDs:**
   ```bash
   grep -r '"uid":' dashboards/ | awk -F'"uid":' '{print $2}' | sort | uniq -d
   ```

2. **Generate unique UIDs:**
   ```bash
   uuidgen | tr -d '-' | head -c 12
   ```

### Folder Not Created

1. **Verify folder annotation:**
   ```yaml
   annotations:
     grafana_folder: "MyFolder"
   ```

2. **Check Grafana folder permissions:**
   ```bash
   curl -s http://grafana:3000/api/folders \
     -H "Authorization: Bearer $API_KEY" | jq '.[] | .title'
   ```

## Best Practices

### DO:
- ✅ Use consistent dashboard UIDs
- ✅ Store dashboards in Git
- ✅ Use template variables for flexibility
- ✅ Organize by logical folders
- ✅ Include datasource variables
- ✅ Document dashboard dependencies

### DON'T:
- ❌ Hardcode datasource names
- ❌ Use auto-generated UIDs in production
- ❌ Mix different schema versions
- ❌ Store credentials in dashboards
- ❌ Ignore JSON validation

## Related Documentation

- [Dashboards README](../dashboards/README.md)
- [Grafana Chart](../charts/grafana/)
- [GitOps Guide](GITOPS_GUIDE.md)
- [Alerting Rules](../alerting-rules/)
