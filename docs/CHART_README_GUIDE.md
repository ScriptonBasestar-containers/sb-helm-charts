# Chart README Template Guide

This guide explains how to use the chart README template to create consistent documentation for all charts.

## Template Location

- **Template File**: `docs/CHART_README_TEMPLATE.md`
- **Purpose**: Standardize chart documentation across the repository

## Using the Template

### 1. Copy Template

```bash
cp docs/CHART_README_TEMPLATE.md charts/my-app/README.md
```

### 2. Replace Placeholders

Replace all placeholders (wrapped in `{}`) with actual values:

| Placeholder | Example | Description |
|-------------|---------|-------------|
| `{CHART_NAME}` | `Keycloak` | Human-readable chart name |
| `{VERSION}` | `0.3.0` | Current chart version from Chart.yaml |
| `{APP_VERSION}` | `26.0.6` | Application version from Chart.yaml |
| `{APP_URL}` | `https://www.keycloak.org/` | Official application homepage |
| `{BRIEF_DESCRIPTION}` | `Open Source Identity and Access Management` | One-line description |
| `{APPLICATION_NAME}` | `Keycloak` | Application name |
| `{FEATURE_1}` | `Single Sign-On (SSO)` | Key feature |
| `{ADDITIONAL_PREREQUISITES}` | `PV provisioner support` | Additional requirements |
| `{DATABASE_TYPE}` | `PostgreSQL` | Required database type |
| `{CACHE_TYPE}` | `Redis` | Required cache type |
| `{chart-name}` | `keycloak` | Lowercase chart name for commands |
| `{IMAGE_REPO}` | `quay.io/keycloak/keycloak` | Docker image repository |
| `{DEFAULT_SIZE}` | `10Gi` | Default storage size |
| `{MOUNT_PATH}` | `/opt/keycloak/data` | Volume mount path |
| `{SERVICE_PORT}` | `8080` | Service port |
| `{SAMPLE_CONFIG}` | `# Sample configuration` | Example config file |
| `{NEW_VERSION}` | `26.1.0` | Example upgrade version |
| `{DOCS_URL}` | `https://www.keycloak.org/documentation` | Docs URL |

### 3. Customize Sections

After replacing placeholders, customize these sections:

#### Introduction

- Add specific application details
- Highlight unique chart features
- Mention integration points

#### Prerequisites

- List exact version requirements
- Add cloud-specific requirements
- Note special capabilities needed

#### Configuration

- Add chart-specific parameters
- Document important configuration patterns
- Include real-world examples

#### Troubleshooting

- Add known issues
- Document common error patterns
- Provide specific solutions

## Section Guidelines

### TL;DR

- Keep it ultra-simple
- 3-5 commands maximum
- Focus on quickest path to running

### Introduction

- Explain what the application does
- List 3-5 key features
- Mention ScriptonBasestar chart philosophy

### Prerequisites

- Minimum Kubernetes version
- Helm version
- External dependencies
- Special requirements (GPU, capabilities, etc.)

### Installing the Chart

Include all three deployment scenarios:
1. Home Server (minimal resources)
2. Startup (balanced)
3. Production (HA)

### Configuration

Split into logical subsections:
- Database Strategy
- Common Configuration Options
- Using Configuration Files
- Advanced Configuration

### Database Strategy

**CRITICAL**: Always emphasize external database pattern:
- ✅ External database required
- ❌ No subcharts included
- Provide clear setup instructions

### Persistence

- Explain what data is persisted
- Document volume mount paths
- Provide sizing guidance

### Networking

- Service configuration
- Ingress examples with TLS
- LoadBalancer notes if applicable

### Security

- Network policies
- Pod security contexts
- RBAC requirements
- Secret management

### High Availability

- HPA configuration
- PDB settings
- Multi-replica setup
- Clustering (if applicable)

### Monitoring

- Prometheus metrics
- ServiceMonitor configuration
- Health check endpoints
- Logging integration

### Upgrading

- Version-specific upgrade paths
- Breaking changes
- Data migration steps
- Rollback procedures

### Uninstalling

- Clean uninstall steps
- PVC cleanup warnings
- Data backup reminders

### Troubleshooting

Include:
- Common issues and solutions
- Debug commands
- Log locations
- Support resources

## Best Practices

### Do's ✅

- Use actual commands that can be copy-pasted
- Include realistic examples
- Document defaults from values.yaml
- Provide troubleshooting for common issues
- Keep formatting consistent
- Use badges for visual appeal (including Artifact Hub badge)
- Link to related documentation

### Don'ts ❌

- Don't use placeholder values in examples
- Don't document every single value (link to values.yaml)
- Don't include subchart database installation
- Don't assume users know Kubernetes internals
- Don't forget to update version numbers

## Validation Checklist

Before committing your README:

- [ ] All placeholders replaced
- [ ] Version numbers match Chart.yaml
- [ ] All links work
- [ ] Commands are copy-pasteable
- [ ] Three deployment scenarios included
- [ ] External database pattern emphasized
- [ ] Troubleshooting section completed
- [ ] License information correct
- [ ] Badges point to correct URLs (including Artifact Hub badge)
- [ ] Artifact Hub badge uses correct chart name

## Automation

### Extract Metadata

You can reference `charts-metadata.yaml` for consistent descriptions:

```bash
# Get chart keywords
yq '.charts.keycloak.keywords' charts-metadata.yaml

# Get chart description
yq '.charts.keycloak.description' charts-metadata.yaml
```

### Version Sync

Extract versions from Chart.yaml:

```bash
# Get chart version
yq '.version' charts/keycloak/Chart.yaml

# Get app version
yq '.appVersion' charts/keycloak/Chart.yaml
```

## Examples

### Good README

See existing charts with complete READMEs:
- `charts/keycloak/README.md`
- `charts/redis/README.md`
- `charts/nextcloud/README.md`

### Minimal README

For simple charts, you can omit:
- High Availability section (if not applicable)
- Monitoring section (if no metrics)
- Complex troubleshooting (if straightforward)

But NEVER omit:
- TL;DR
- Prerequisites
- Database Strategy (if uses database)
- Installation examples
- Basic configuration

## Updating Template

When updating the template:

1. Update `docs/CHART_README_TEMPLATE.md`
2. Document changes in this guide
3. Update example READMEs
4. Notify in CHANGELOG.md

## Related Documentation

- [Chart Catalog](CHARTS.md) - Browse all available charts
- [Chart Development Guide](CHART_DEVELOPMENT_GUIDE.md)
- [Scenario Values Guide](SCENARIO_VALUES_GUIDE.md)
- [Chart Version Policy](CHART_VERSION_POLICY.md)
- [Contributing Guide](../.github/CONTRIBUTING.md)

---

**Questions?** Open an issue or discussion on GitHub.
