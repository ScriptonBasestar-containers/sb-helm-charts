# Chart Version Policy

This document defines the versioning policy for all Helm charts in this repository.

## Version Format

All charts follow [Semantic Versioning 2.0.0](https://semver.org/):

```
MAJOR.MINOR.PATCH
```

- **MAJOR**: Breaking changes (incompatible API/configuration changes)
- **MINOR**: New features (backward-compatible functionality)
- **PATCH**: Bug fixes (backward-compatible fixes)

## Version Increment Rules

### MAJOR Version (X.0.0)

Increment when making **breaking changes** that require user action:

#### Configuration Breaking Changes
- Renaming or removing `values.yaml` parameters
- Changing default values that affect existing deployments
- Restructuring configuration hierarchy
- Removing support for deprecated features

**Examples:**
```yaml
# Breaking: Parameter renamed
# Before (0.x.x):
redis.host: "redis-service"

# After (1.0.0):
redis.external.host: "redis-service"
```

#### Template Breaking Changes
- Changing resource names (StatefulSet, Deployment, Service)
- Modifying label selectors
- Changing PVC naming patterns
- Altering Secret/ConfigMap structure

**Examples:**
- Renaming `{{ .Release.Name }}-redis` → `{{ include "chart.fullname" . }}-cache`
- Changing app label from `app: keycloak` → `app.kubernetes.io/name: keycloak`

#### API/CRD Changes
- Updating to Kubernetes API versions that drop old APIs (e.g., `apps/v1beta1` → `apps/v1`)
- Removing support for older Kubernetes versions

#### Upgrade Path Requirements
- Must provide migration guide in `CHANGELOG.md`
- Must document manual steps required
- Should provide upgrade helper scripts if possible

### MINOR Version (0.X.0)

Increment when adding **new features** without breaking existing functionality:

#### New Features
- Adding new optional configuration parameters
- Introducing new chart features (autoscaling, monitoring, etc.)
- Adding support for new deployment patterns
- Implementing new helper functions

**Examples:**
```yaml
# Non-breaking: New optional feature
autoscaling:
  enabled: false  # Disabled by default
  minReplicas: 2
  maxReplicas: 10
```

#### Enhanced Functionality
- Adding new Makefile operational commands
- Implementing additional health checks
- Supporting new storage classes or volume types
- Adding new init containers (optional)

#### Backward-Compatible Changes
- Adding new template files (e.g., `networkpolicy.yaml`)
- Extending existing resources with optional fields
- Adding new service endpoints (while keeping existing ones)

**Important:** New features must be **disabled by default** to maintain backward compatibility.

### PATCH Version (0.0.X)

Increment for **bug fixes** and non-functional changes:

#### Bug Fixes
- Fixing template rendering errors
- Correcting misconfigured probes
- Fixing resource limit calculations
- Resolving RBAC permission issues

#### Documentation Updates
- Updating README.md
- Fixing typos in NOTES.txt
- Improving inline template comments
- Adding usage examples

**Note:** Documentation-only changes may skip PATCH increment if part of ongoing development (0.1.0-dev).

#### Non-Functional Improvements
- Code formatting and cleanup
- Refactoring helpers without changing behavior
- Improving error messages
- Optimizing template logic

## Pre-Release Versions

### Development Phase (0.1.0)

Charts start at `0.1.0` during initial development:

- Rapid iteration allowed
- Breaking changes permitted without MAJOR increment
- Focus on stabilization and feature completion

### Release Candidates (1.0.0-rc.1)

Before first stable release:

```yaml
version: 1.0.0-rc.1
version: 1.0.0-rc.2
```

- Feature-complete
- Breaking changes frozen
- Only bug fixes and documentation updates

### Stable Release (1.0.0)

First production-ready version:

- All core features implemented
- Comprehensive documentation
- Tested in production-like environment
- Migration path from development versions documented

## Chart vs Application Version

### Chart Version (`version`)

Version of the **Helm chart itself**:

```yaml
# Chart.yaml
version: 0.2.0  # Chart version
```

- Incremented based on chart changes (templates, values, docs)
- Independent of application version
- Follows semantic versioning strictly

### Application Version (`appVersion`)

Version of the **application** being deployed:

```yaml
# Chart.yaml
appVersion: "26.0.7"  # Keycloak version
```

- Matches upstream application version
- Updated when upgrading application image
- May use upstream versioning scheme (which may not be semver)

### Example Scenarios

#### Scenario 1: Application Upgrade (PATCH)
```yaml
# Before
version: 0.2.0
appVersion: "7.4.0"

# After (bug fix in Redis upstream)
version: 0.2.1
appVersion: "7.4.1"
```

#### Scenario 2: Chart Feature Addition (MINOR)
```yaml
# Before
version: 0.2.1
appVersion: "7.4.1"

# After (added monitoring support)
version: 0.3.0
appVersion: "7.4.1"  # App version unchanged
```

#### Scenario 3: Breaking Configuration Change (MAJOR)
```yaml
# Before
version: 0.3.0
appVersion: "7.4.1"

# After (restructured values.yaml)
version: 1.0.0
appVersion: "7.4.1"  # App version unchanged
```

## Current Repository Status

### Mature Charts (0.3.x)

Production-ready charts with advanced features and stable APIs:

| Chart | Version | Status | Notes |
|-------|---------|--------|-------|
| keycloak | 0.3.0 | Mature | PostgreSQL SSL, Redis SSL, clustering |
| wireguard | 0.3.0 | Mature | No database, NET_ADMIN capabilities |
| memcached | 0.3.0 | Mature | Simple cache, production-ready |
| rabbitmq | 0.3.0 | Mature | Message broker with management UI |
| browserless-chrome | 0.3.0 | Mature | Headless browser service |
| devpi | 0.3.0 | Mature | Python package index |
| rsshub | 0.3.0 | Mature | RSS aggregator |

### Stable Charts (0.2.x)

Charts with established patterns, ready for production use:

| Chart | Version | Status | Path to 0.3.0 |
|-------|---------|--------|---------------|
| redis | 0.2.0 | Stable | Master-slave replication, needs HA testing |
| rustfs | 0.2.0 | Stable | S3-compatible storage, needs clustering validation |
| wordpress | 0.2.0 | Stable | CMS with MySQL, needs advanced features |
| nextcloud | 0.2.0 | Stable | Cloud storage, needs production validation |
| uptime-kuma | 0.2.0 | Stable | Monitoring tool, needs HA testing |
| paperless-ngx | 0.2.0 | Stable | Document management, needs backup automation |
| immich | 0.2.0 | Stable | Photo management, needs ML worker optimization |
| jellyfin | 0.2.0 | Stable | Media server, needs GPU acceleration validation |
| vaultwarden | 0.2.0 | Stable | Password manager, needs security audit |

## Version Increment Checklist

### Before Incrementing Version

- [ ] Review all changes since last version
- [ ] Classify changes (MAJOR/MINOR/PATCH)
- [ ] Update `Chart.yaml` version field
- [ ] Update `CHANGELOG.md` with changes
- [ ] Update `appVersion` if application upgraded
- [ ] Run `helm lint charts/<chart-name>`
- [ ] Test installation with `helm template`
- [ ] Verify upgrade path from previous version

### MAJOR Version Checklist (Additional)

- [ ] Write migration guide in `docs/`
- [ ] Document breaking changes in README.md
- [ ] Provide example upgrade commands
- [ ] Test upgrade from previous MAJOR version
- [ ] Update NOTES.txt with upgrade warnings

### Release Process

1. **Commit Version Bump**
   ```bash
   git add charts/<chart>/Chart.yaml
   git commit -m "chore(claude-sonnet): Bump <chart> version to X.Y.Z"
   ```

2. **Update Changelog**
   ```bash
   # Add entry to CHANGELOG.md
   git add CHANGELOG.md
   git commit -m "docs(claude-sonnet): Update CHANGELOG for <chart> X.Y.Z"
   ```

3. **Tag Release** (automated by CI/CD)
   - GitHub Actions automatically creates Git tags
   - Format: `<chart-name>-X.Y.Z`
   - Example: `redis-0.2.1`, `keycloak-0.3.0`

4. **Verify Release**
   - Check GitHub Releases page
   - Verify chart package uploaded
   - Test installation from Helm repository

## Helm Repository Updates

Charts are automatically published to Helm repository on push to `master`:

```bash
# Add repository
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts

# Update repository
helm repo update

# Install chart
helm install my-redis scripton-charts/redis --version 0.2.0
```

Repository URL: https://scriptonbasestar-container.github.io/sb-helm-charts

## Deprecation Policy

### Marking Features as Deprecated

Add deprecation notice in chart version N:

```yaml
# values.yaml (version 0.3.0)
oldFeature:
  enabled: false
  # DEPRECATED: This feature will be removed in 1.0.0
  # Use newFeature instead
```

### Removing Deprecated Features

- Must be deprecated for at least one MINOR version
- Removal constitutes a MAJOR version bump
- Provide migration guide

**Example Timeline:**
- v0.3.0: Feature deprecated (warning added)
- v0.4.0: Still supported (warning remains)
- v1.0.0: Feature removed (breaking change)

## Version History

### Notable Version Milestones

- **0.1.0**: Initial chart development
- **0.2.0**: Production-ready features (monitoring, HA, security)
- **0.3.0**: Advanced features (SSL/TLS, operators, clustering)
- **1.0.0**: Stable API, production-tested, comprehensive docs

## References

- [Semantic Versioning 2.0.0](https://semver.org/)
- [Helm Chart Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Helm Chart Versioning](https://helm.sh/docs/topics/charts/#the-chartyaml-file)
- [Chart Development Guide](./CHART_DEVELOPMENT_GUIDE.md)
- [Chart Catalog](CHARTS.md) - Browse all available charts with version information
- [Artifact Hub Dashboard](ARTIFACTHUB_DASHBOARD.md) - Artifact Hub publishing status

## Questions?

For version policy questions or exceptions:
1. Check [CHART_DEVELOPMENT_GUIDE.md](./CHART_DEVELOPMENT_GUIDE.md)
2. Review similar charts in this repository
3. Open an issue for discussion
