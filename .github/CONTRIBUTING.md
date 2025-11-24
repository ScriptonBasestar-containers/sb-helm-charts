# Contributing to ScriptonBasestar Helm Charts

Thank you for your interest in contributing to sb-helm-charts! This document provides guidelines for contributing charts, bug fixes, and improvements.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Chart Development Guidelines](#chart-development-guidelines)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Documentation Standards](#documentation-standards)

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you are expected to uphold this code.

## Getting Started

### Prerequisites

- Kubernetes cluster (local or remote)
  - [minikube](https://minikube.sigs.k8s.io/docs/) (recommended for local testing)
  - [kind](https://kind.sigs.k8s.io/) (included in this repo: `make kind-create`)
- [Helm](https://helm.sh/docs/intro/install/) 3.x
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [chart-testing (ct)](https://github.com/helm/chart-testing) 3.x
- Make

### Repository Setup

1. Fork the repository on GitHub
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/sb-helm-charts.git
   cd sb-helm-charts
   ```
3. Add upstream remote:
   ```bash
   git remote add upstream https://github.com/scriptonbasestar-container/sb-helm-charts.git
   ```
4. Create a feature branch:
   ```bash
   git checkout -b feature/my-new-chart
   ```

## Development Workflow

### 1. Creating a New Chart

Follow the [Chart Development Guide](../docs/CHART_DEVELOPMENT_GUIDE.md) for detailed standards.

**Quick Start:**
```bash
# Create chart structure
helm create charts/my-app

# Follow the standard structure
charts/my-app/
├── Chart.yaml
├── values.yaml
├── values-home-single.yaml
├── values-startup-single.yaml
├── values-prod-master-replica.yaml
├── README.md
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── configmap.yaml
    ├── secret.yaml
    ├── pvc.yaml
    ├── serviceaccount.yaml
    ├── NOTES.txt
    ├── _helpers.tpl
    └── tests/
```

**IMPORTANT: Update Chart Metadata**

When creating a new chart or modifying an existing one, you MUST update `charts/charts-metadata.yaml`:

```yaml
charts:
  my-app:
    name: My Application
    path: charts/my-app
    category: application  # or 'infrastructure'
    tags: [Web, CMS, Publishing]
    keywords: [my-app, web, cms, content-management]
    description: Brief description of the application
    production_note: "Optional production warning"  # For infrastructure charts
```

This metadata is used for:
- Chart discovery and search
- Documentation generation
- Artifact Hub keywords
- Consistent categorization

See [CLAUDE.md](../CLAUDE.md#chart-metadata) for complete metadata requirements.

**Syncing Keywords:**

After updating `charts/charts-metadata.yaml`, you can automatically sync keywords to `Chart.yaml`:

```bash
# Preview changes (dry-run)
make sync-keywords-dry-run

# Apply changes
make sync-keywords

# Sync specific chart only
python3 scripts/sync-chart-keywords.py --chart my-app
```

The sync tool ensures `Chart.yaml` keywords match `charts/charts-metadata.yaml`, maintaining consistency across all charts.

### 2. Modifying Existing Charts

- Always increment chart version following [Semantic Versioning](../docs/CHART_VERSION_POLICY.md)
- Update `CHANGELOG.md` with your changes
- Update `charts/charts-metadata.yaml` if keywords or description changed
- Test all scenario values files

### 3. Local Testing

```bash
# Lint your chart
helm lint charts/my-app

# Validate chart metadata consistency
make validate-metadata

# Test with scenario values
helm install my-app-test charts/my-app \
  -f charts/my-app/values-home-single.yaml \
  --dry-run --debug

# Install locally
helm install my-app charts/my-app \
  -f charts/my-app/values-home-single.yaml

# Run tests
helm test my-app
```

### 4. Chart Metadata Workflow

When working with chart metadata, follow this workflow:

1. **Update metadata first** in `charts/charts-metadata.yaml`:
   ```bash
   # Edit charts/charts-metadata.yaml
   vim charts/charts-metadata.yaml
   ```

2. **Sync keywords to Chart.yaml**:
   ```bash
   # Preview changes
   make sync-keywords-dry-run

   # Apply if changes look correct
   make sync-keywords
   ```

3. **Validate consistency**:
   ```bash
   make validate-metadata
   ```

4. **Regenerate documentation** (optional but recommended):
   ```bash
   make generate-catalog
   make generate-artifacthub-dashboard
   ```

5. **Commit changes**:
   ```bash
   git add charts/charts-metadata.yaml charts/my-app/Chart.yaml docs/CHARTS.md docs/ARTIFACTHUB_DASHBOARD.md
   git commit -m "feat(my-app): Update chart keywords and regenerate catalog"
   ```

The pre-commit hook will automatically validate metadata before allowing the commit.

**Note**: Regenerating the catalog ensures that the [Chart Catalog](../docs/CHARTS.md) stays up-to-date with the latest metadata changes.

## Chart Development Guidelines

### Core Principles

1. **Configuration Files First**: Prefer ConfigMaps with full configuration files over environment variables
2. **External Dependencies**: NEVER include databases as subcharts - always use external references
3. **Simplicity**: Keep Helm templates simple - don't abstract away application complexity
4. **Production-Ready**: Include all three scenario values files (home-single, startup-single, prod-master-replica)

### values.yaml Structure

All charts MUST follow this structure:

```yaml
# 1. Application-specific Configuration
{appname}:
  adminUser: ""
  adminPassword: ""
  config: |
    # Full configuration file

# 2. External Dependencies (ALWAYS disabled)
postgresql:
  enabled: false  # MANDATORY
  external:
    enabled: false
    host: ""
    database: ""
    username: ""
    password: ""

# 3. Persistence
persistence:
  enabled: true
  storageClass: ""
  size: "10Gi"

# 4. Kubernetes Resources
replicaCount: 1
image:
  repository: ""
  tag: ""

# 5. Service
service:
  type: ClusterIP
  port: 80

# 6. Ingress
ingress:
  enabled: false

# 7. Resources
resources:
  limits:
    cpu: "1000m"
    memory: "1Gi"
  requests:
    cpu: "100m"
    memory: "128Mi"

# 8. Production Features (Optional)
autoscaling:
  enabled: false
networkPolicy:
  enabled: false
serviceMonitor:
  enabled: false
```

### Database Strategy

**CRITICAL**: The `postgresql.enabled: false` pattern is a core project value.

- ✅ DO: Use external database references
- ❌ DON'T: Include database charts as dependencies
- ✅ DO: Document external database requirements in README
- ✅ DO: Provide InitContainers for database health checks

### Scenario Values Files

All charts MUST include three scenario files:

1. **values-home-single.yaml**: Minimal resources (50-500m CPU, 128Mi-512Mi RAM)
2. **values-startup-single.yaml**: Balanced (100m-1000m CPU, 256Mi-1Gi RAM)
3. **values-prod-master-replica.yaml**: Production HA (250m-2000m CPU, 512Mi-2Gi RAM)

See [Scenario Values Guide](../docs/SCENARIO_VALUES_GUIDE.md) for detailed specifications.

## Pull Request Process

### Before Submitting

1. **Lint your changes:**
   ```bash
   helm lint charts/my-app
   ```

2. **Validate metadata consistency:**
   ```bash
   make validate-metadata
   ```

3. **Regenerate chart catalog** (if metadata changed):
   ```bash
   make generate-catalog
   ```

4. **Test all scenarios:**
   ```bash
   make -f make/ops/my-app.mk install  # Test default values
   make install-home                    # Test home scenario
   make install-startup                 # Test startup scenario
   make install-prod                    # Test production scenario
   ```

5. **Update documentation:**
   - Chart `README.md` with deployment examples
   - Main `CHANGELOG.md` with your changes
   - Chart `Chart.yaml` annotations for Artifact Hub
   - `charts/charts-metadata.yaml` if keywords or description changed
   - `docs/CHARTS.md` (auto-generated, run `make generate-catalog`)

6. **Commit message format:**
   ```
   <type>(<scope>): <subject>

   <body>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: <Your Name> <your.email@example.com>
   ```

   Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

### Submitting a Pull Request

1. Push to your fork:
   ```bash
   git push origin feature/my-new-chart
   ```

2. Open a Pull Request on GitHub with:
   - Clear title describing the change
   - Description of what changed and why
   - Links to related issues
   - Screenshots (if UI/config changes)

3. PR Checklist:
   - [ ] Chart version incremented according to [version policy](../docs/CHART_VERSION_POLICY.md)
   - [ ] `CHANGELOG.md` updated
   - [ ] `charts/charts-metadata.yaml` updated (for new/modified charts)
   - [ ] All three scenario values files included
   - [ ] README.md includes deployment scenarios section
   - [ ] `helm lint` passes with 0 errors
   - [ ] Tested in local Kubernetes cluster
   - [ ] Artifact Hub metadata added to `Chart.yaml`
   - [ ] No subcharts for databases

### Review Process

- Maintainers will review your PR within 3-5 business days
- Address review comments by pushing to the same branch
- Once approved, maintainers will merge your PR
- Charts are automatically released via GitHub Actions

## Coding Standards

### Helm Templates

```yaml
# Use consistent indentation (2 spaces)
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "chart.fullname" . }}
  labels:
    {{- include "chart.labels" . | nindent 4 }}
data:
  config.yaml: |
    {{- .Values.app.config | nindent 4 }}
```

### Helper Functions

All charts should include standard helpers in `_helpers.tpl`:

```yaml
{{- define "chart.fullname" -}}
{{- define "chart.name" -}}
{{- define "chart.labels" -}}
{{- define "chart.selectorLabels" -}}
{{- define "chart.serviceAccountName" -}}
```

### NOTES.txt Pattern

Post-install notes should include:

1. Access information (Ingress URLs, port-forward commands)
2. Credential retrieval commands
3. Feature-specific guidance
4. Production warnings

## Testing Requirements

### Required Tests

1. **Lint Test:**
   ```bash
   helm lint charts/my-app
   ```

2. **Template Rendering:**
   ```bash
   helm template my-app charts/my-app --dry-run --debug
   ```

3. **Install Test (all scenarios):**
   ```bash
   helm install my-app-test charts/my-app -f charts/my-app/values-home-single.yaml
   helm test my-app-test
   helm uninstall my-app-test
   ```

4. **Upgrade Test:**
   ```bash
   helm upgrade my-app-test charts/my-app
   ```

### Test Files

Include test pods in `templates/tests/`:

```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "chart.fullname" . }}-test-connection"
  annotations:
    "helm.sh/hook": test
spec:
  containers:
    - name: wget
      image: busybox
      command: ['wget']
      args: ['{{ include "chart.fullname" . }}:{{ .Values.service.port }}']
  restartPolicy: Never
```

## Documentation Standards

### Chart README.md

All chart READMEs MUST include:

1. **Overview**: What the application does
2. **Prerequisites**: External dependencies (databases, etc.)
3. **Deployment Scenarios**: Three scenario examples
4. **Installation**: Helm install commands
5. **Configuration**: Important values.yaml parameters
6. **Upgrading**: Version-specific upgrade notes
7. **Uninstallation**: Clean uninstall process

### CHANGELOG.md Format

Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format:

```markdown
## [0.3.0] - 2025-11-16

### Added
- New feature description

### Changed
- Modified behavior description

### Fixed
- Bug fix description
```

### Chart.yaml Annotations

Include Artifact Hub metadata:

```yaml
annotations:
  artifacthub.io/license: BSD-3-Clause
  artifacthub.io/changes: |
    - kind: added
      description: New feature description
  artifacthub.io/prerelease: "false"
  artifacthub.io/recommendations: |
    - url: https://github.com/.../SCENARIO_VALUES_GUIDE.md
  artifacthub.io/links: |
    - name: Chart Source
      url: https://github.com/.../charts/my-app
```

## Getting Help

- **Questions**: Open a [GitHub Discussion](https://github.com/scriptonbasestar-container/sb-helm-charts/discussions)
- **Bugs**: Open a [GitHub Issue](https://github.com/scriptonbasestar-container/sb-helm-charts/issues)
- **Security**: Email maintainers directly (see README.md)

## License

By contributing, you agree that your contributions will be licensed under the BSD 3-Clause License (chart license). Note that applications may have different licenses - see individual chart READMEs.

---

Thank you for contributing to sb-helm-charts!
