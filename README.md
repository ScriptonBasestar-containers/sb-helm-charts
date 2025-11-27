# Helm Chart - ScriptonBasestar

## Installation

### Add Helm Repository

**GitHub Pages (Traditional)**
```bash
helm repo add sb-charts https://scriptonbasestar-containers.github.io/sb-helm-charts
helm repo update
```

**GHCR OCI Registry (Recommended)**
```bash
# No repository add needed - use OCI directly
helm install keycloak oci://ghcr.io/scriptonbasestar-containers/charts/keycloak --version 0.3.0
```

### Usage Examples

**Install from GitHub Pages**
```bash
helm install keycloak sb-charts/keycloak --version 0.3.0 -f values.yaml
```

**Install from OCI Registry**
```bash
helm install keycloak oci://ghcr.io/scriptonbasestar-containers/charts/keycloak --version 0.3.0 -f values.yaml
```

**Pull Chart**
```bash
# GitHub Pages
helm pull sb-charts/keycloak --version 0.3.0

# OCI Registry
helm pull oci://ghcr.io/scriptonbasestar-containers/charts/keycloak --version 0.3.0
```

### Deployment Scenarios

All charts include pre-configured values files for three deployment scenarios:

- **Home Server** (`values-home-single.yaml`): Minimal resources for personal/home lab use
- **Startup** (`values-startup-single.yaml`): Balanced configuration for small teams
- **Production** (`values-prod-master-replica.yaml`): High availability deployment with clustering

**Usage Example:**
```bash
# Home Server deployment
helm install nextcloud ./charts/nextcloud -f charts/nextcloud/values-home-single.yaml

# Startup deployment
helm install nextcloud ./charts/nextcloud -f charts/nextcloud/values-startup-single.yaml

# Production deployment with HA
helm install nextcloud ./charts/nextcloud -f charts/nextcloud/values-prod-master-replica.yaml
```

**Override specific values:**
```bash
helm install nextcloud ./charts/nextcloud \
  -f charts/nextcloud/values-home-single.yaml \
  --set postgresql.external.host=postgres.default.svc.cluster.local \
  --set postgresql.external.password=secure-password
```

For detailed scenario documentation, see [Scenario Values Guide](docs/SCENARIO_VALUES_GUIDE.md).

## Available Charts

Browse the complete chart catalog with detailed information:

**📚 [View Full Chart Catalog](docs/CHARTS.md)**
**🏷️ [Artifact Hub Dashboard](docs/ARTIFACTHUB_DASHBOARD.md)** - Publishing status and badges

The catalog includes:
- **37 charts** organized by category (Application/Infrastructure)
- Version badges, descriptions, and installation examples
- Searchable by tags and keywords
- Auto-generated from `charts/charts-metadata.yaml`

**Quick Overview:**
- **Application Charts** (20): airflow, browserless-chrome, devpi, grafana, harbor, immich, jellyfin, keycloak, loki, mlflow, nextcloud, paperless-ngx, pgadmin, phpmyadmin, rsshub, rustfs, uptime-kuma, vaultwarden, wireguard, wordpress
- **Infrastructure Charts** (17): alertmanager, blackbox-exporter, elasticsearch, kafka, kube-state-metrics, memcached, minio, mongodb, mysql, node-exporter, postgresql, prometheus, promtail, pushgateway, rabbitmq, redis, tempo

For comprehensive chart documentation, deployment scenarios, and configuration options, see the [full catalog](docs/CHARTS.md).

### Artifact Hub

Charts are available on Artifact Hub for easy discovery and security scanning:

- **Browse on Artifact Hub**: [scriptonbasestar-charts](https://artifacthub.io/) (Coming soon - pending GitHub Pages setup)
- **Automated Security Scanning**: Container images are scanned for vulnerabilities
- **Publishing Status**: See [Artifact Hub Dashboard](docs/ARTIFACTHUB_DASHBOARD.md) for badges and statistics

The repository includes `artifacthub-repo.yml` with metadata for all 37 charts, enabling:
- Automatic chart discovery
- Container image security scanning
- Rich chart documentation with badges and links
- Integration with the Artifact Hub ecosystem

## 🏢 Enterprise-Ready Features

**6 charts** now include comprehensive operational capabilities for production deployments:

### Enhanced Charts with Full Operational Support

| Chart | RBAC | Backup/Recovery | Upgrade Strategies | Documentation |
|-------|------|-----------------|-------------------|---------------|
| **Keycloak** | ✅ | ✅ 4-component | ✅ 3 strategies | [Backup](docs/keycloak-backup-guide.md) • [Upgrade](docs/keycloak-upgrade-guide.md) |
| **Airflow** | ✅ | ✅ 3-component | ✅ 3 strategies | [Backup](docs/airflow-backup-guide.md) • [Upgrade](docs/airflow-upgrade-guide.md) |
| **Harbor** | ✅ | ✅ 3-component | ✅ 3 strategies | [Backup](docs/harbor-backup-guide.md) • [Upgrade](docs/harbor-upgrade-guide.md) |
| **MLflow** | ✅ | ✅ 3-component | ✅ 3 strategies | [Backup](docs/mlflow-backup-guide.md) • [Upgrade](docs/mlflow-upgrade-guide.md) |
| **Kafka** | ✅ | ✅ 5-component | ✅ 3 strategies | [Backup](docs/kafka-backup-guide.md) • [Upgrade](docs/kafka-upgrade-guide.md) |
| **Elasticsearch** | ✅ | ✅ 4-component | ✅ 3 strategies | [Backup](docs/elasticsearch-backup-guide.md) • [Upgrade](docs/elasticsearch-upgrade-guide.md) |

### Features Include

**🔐 RBAC (Role-Based Access Control)**
- Namespace-scoped Roles with read access to ConfigMaps, Secrets, Pods, PVCs
- Configurable RoleBindings for ServiceAccounts
- Production-ready security defaults

**💾 Backup & Recovery**
- Multi-component backup strategies (3-5 components per chart)
- Makefile-driven operations (no automated CronJobs)
- Comprehensive recovery procedures with RTO/RPO targets
- Support for snapshot repositories, database dumps, and PVC snapshots

**⬆️ Zero-Downtime Upgrades**
- Multiple upgrade strategies (Rolling, Blue-Green, Maintenance Window)
- Pre/post-upgrade validation checks
- Automated rollback procedures
- Version-specific upgrade notes

**📚 Comprehensive Documentation**
- Detailed backup guides (500-600 lines each)
- Detailed upgrade guides (600-700 lines each)
- README sections with quick-start examples
- RTO/RPO targets: < 1-2 hours recovery time, 1-24 hours data loss

### Operational Commands

All enhanced charts include standardized Makefile targets:

```bash
# Backup operations
make -f make/ops/keycloak.mk kc-backup-all-realms
make -f make/ops/airflow.mk airflow-full-backup
make -f make/ops/kafka.mk kafka-full-backup

# Pre-upgrade checks
make -f make/ops/elasticsearch.mk es-pre-upgrade-check

# Post-upgrade validation
make -f make/ops/harbor.mk harbor-post-upgrade-check

# Rollback procedures
make -f make/ops/mlflow.mk mlflow-upgrade-rollback
```

**See [CLAUDE.md](CLAUDE.md#enhanced-operational-features)** for complete feature documentation and usage examples.

## Recent Changes

**Latest Release: v1.1.0** (2025-11-25)

### v1.1.0 Highlights - Documentation & Observability
- **37 Production-Ready Charts**: All charts at v0.3.x (Harbor promoted to production-ready)
- **Complete Observability Stack**: Prometheus + Loki + **Tempo** (NEW) for metrics, logs, and traces
- **6 Operator Migration Guides**: PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ, Kafka
- **Deployment Automation**: Quick-start script for one-command stack deployments
- **Chart Generator**: Automated chart scaffolding following project conventions
- **Comprehensive Guides**: Homeserver optimization, multi-tenancy patterns

### New in v1.1.0
- **New Chart**: tempo (v0.3.0) - Distributed tracing backend
- **New Guides**: [Observability Stack](docs/OBSERVABILITY_STACK_GUIDE.md), [Homeserver Optimization](docs/HOMESERVER_OPTIMIZATION.md), [Multi-Tenancy](docs/MULTI_TENANCY_GUIDE.md)
- **New Scripts**: `scripts/quick-start.sh`, `scripts/generate-chart.sh`
- **New Examples**: `examples/mlops-stack/` - MLflow + MinIO + PostgreSQL

For full details, see [Release Notes v1.1.0](docs/RELEASE_NOTES_v1.1.0.md).

### v1.0.0 Previous Release (2025-11-21)
- **36 Production-Ready Charts**: First stable release
- **Complete Monitoring Stack**: 9 charts (Prometheus, Alertmanager, etc.)
- **Database Admin Tools**: pgAdmin and phpMyAdmin with multi-server support
- **Full Database Support**: PostgreSQL, MySQL, MongoDB, Redis, Elasticsearch

### v0.3.0
- **Deployment Scenarios**: Pre-configured values files for Home Server, Startup, and Production environments
- **Documentation**: Comprehensive [Scenario Values Guide](docs/SCENARIO_VALUES_GUIDE.md)
- **9 charts promoted**: keycloak, redis, memcached, rabbitmq, wireguard, browserless-chrome, devpi, rsshub, rustfs

### Full Changelog
See [CHANGELOG.md](CHANGELOG.md) for complete release notes and version history.

## 프로젝트 목표 (NO_AI_SECTION)

개인 서버 및 간단한 서버 운영을 위한 차트

helm의 설정값만 가지고 소프트웨어를 설치할 수 있게 만든다는 컨셉은 잘못됐다.

`helm install {app_name} {repo_name}/{chart_name} --values simplevalue.yaml`
기본 value.yaml에서 몇가지 값만 오버라이드 해서 쓰라는 컨셉인데... 사실 그렇게 쓸 수는 없다.
표준 ingress에 대한 value도 차트마다 제각각인 것도 문제...

IaC에서 설치가 쉬운건 잠깐이고 유지보수가 용이하고 사용시에 오류가 없어야 하는데 helm의 복잡한 설정은 다음과 같은 이유로 지속적으로 오류를 발생시킨다.
- 앱의 업데이트에 따른 설정값의 변경
- docker 설정값의 변경
- helm 차트의 업데이트에 따른 설정값의 변경
이렇게 각각의 단계 끝에 있는 helm은 복잡성이 더 높아진다.

편하게 만들려고 하면 할 수록 점점 더 복잡해지고 앱에서 대규모의 변경이 발생했을 때 따라갈 수 없게 된다.
app-docker-helm 3단계로 복잡성이 꼬이게 된다.

하지만... docker에서 app의 설정값을 거의 그대로 사용하고 helm에서도 그대로 쓴다면? 복잡성 전파가 거의 사라진다.

어차피 장기적&안정적으로 서버를 운영하려면 소프트웨어를 이해하고 설정값을 수정해야한다. 쉬운 설치는 도움이 안 된다.

오래된 오픈소스는 대부분 설정파일을 기반으로 개발되어 있고 환경변수를 지원하더라도 싱글서버에서는 설정파일을 관리하는편이 더 오류가 적다.
만능헬름차트는 홈서버 나스용으로도 거의 못 쓰고 결국 커스텀을 해야한다.
그럴바에는... 환경변수를 config나 values에 포함시키는 편이 낫다.

도커에서 env를 기반으로 설정파일을 생성하도록 만들어놓은 경우가 많은데... 시키는대로 쓰면 편한데 특별한 상황이나 오류발생시 대처가 불가능하다.

helm의 가장 잘못된 설계는 config파일을 values에 대입하는 기능을 안 만든 부분이다.
하지만 이게 표준이 돼 버렸으니... 그 부분을 감안하고 써야한다. 아니면 커스텀 코드로 헬름차트를 덮어쓰도록 해 줘야한다(대부분 이렇게 쓰고 있을듯??)

## 다른차트와 차별점 (NO_AI_SECTION)
- 설정파일 그대로 활용, 환경변수 사용은 지양
    - 대부분의 오래된 오픈소스는 설정파일 기반으로 개발되어 있다.
    - 설정파일 위주 소프트웨어를 환경변수 기반인 도커로 변환하면서 문제가 발생한다.
- 서브차트 최대한 배제
    - 필수적으로 함께 사용되는 것들만 함께 설치
    - 일반적으로 별도 설치하는 db 등은 분리
    - 디비는 각 사이트마다 자신들이 원하는 옵션이 있어서 차트로 포함 해 봐야 실 배포에서 한번도 쓴 적이 없다.
- 심플한 도커이미지가 있는경우 사용하지만 없으면 도커부터 만들어 사용

## Contributing

We welcome contributions! Please see our [Contributing Guide](.github/CONTRIBUTING.md) for details on:

- Code of Conduct
- Development workflow
- Pull request process
- Coding standards
- Testing requirements

### Quick Start for Contributors

1. **Fork and clone** the repository
2. **Install pre-commit hooks** for code quality:
   ```bash
   pip install pre-commit
   pre-commit install
   ```
3. **Create a feature branch** from `develop`
4. **Make your changes** following our [Chart Development Guide](docs/CHART_DEVELOPMENT_GUIDE.md)
5. **Test your charts**:
   ```bash
   helm lint charts/your-chart
   helm install test-release charts/your-chart --dry-run --debug
   ```
6. **Commit with conventional commits**: `feat:`, `fix:`, `docs:`, etc.
7. **Submit a pull request** to the `develop` branch

### Pre-commit Hooks

This project uses pre-commit hooks to maintain code quality:

```bash
# Install pre-commit (one-time setup)
pip install pre-commit

# Install hooks to your local repository
pre-commit install

# Run hooks manually on all files
pre-commit run --all-files
```

The hooks will automatically check:
- YAML syntax and formatting
- Helm chart linting
- Chart metadata consistency (keywords, tags)
- Markdown formatting
- Shell script linting
- Trailing whitespace and EOF
- Conventional commit messages

## Development

### Local Testing with Kind

```bash
# Create local Kubernetes cluster
make kind-create

# Test chart installation
helm install my-test charts/my-chart

# Delete cluster
make kind-delete
```

### Chart Testing

```bash
# Lint specific chart
helm lint charts/my-chart

# Validate chart metadata consistency
make validate-metadata

# Test all scenario values
helm install test-home charts/my-chart -f charts/my-chart/values-home-single.yaml --dry-run
helm install test-startup charts/my-chart -f charts/my-chart/values-startup-single.yaml --dry-run
helm install test-prod charts/my-chart -f charts/my-chart/values-prod-master-replica.yaml --dry-run
```

### Chart Metadata Management

All chart metadata (keywords, tags, descriptions) is centrally managed in `charts/charts-metadata.yaml`. When adding or modifying charts:

1. **Update metadata** in `charts/charts-metadata.yaml`
2. **Ensure Chart.yaml keywords match** the metadata file
3. **Validate consistency**:
   ```bash
   # Install Python dependencies (one-time)
   pip install -r scripts/requirements.txt

   # Run validation
   make validate-metadata
   # or
   python3 scripts/validate-chart-metadata.py
   ```
4. **Regenerate catalog** (optional):
   ```bash
   make generate-catalog
   ```

The validation ensures:
- ✅ All charts have metadata entries
- ✅ Keywords in `Chart.yaml` match `charts/charts-metadata.yaml`
- ✅ Consistent categorization across all charts

The metadata is also used to auto-generate the [Chart Catalog](docs/CHARTS.md).

For more details, see:
- [Chart Catalog](docs/CHARTS.md) - Browse all available charts
- [Chart Development Guide](docs/CHART_DEVELOPMENT_GUIDE.md) - Comprehensive development patterns and standards
- [Chart Version Policy](docs/CHART_VERSION_POLICY.md) - Semantic versioning and release process
- [Scenario Values Guide](docs/SCENARIO_VALUES_GUIDE.md) - Deployment scenarios explained

**Operational Guides:**
- [Testing Guide](docs/TESTING_GUIDE.md) - Comprehensive testing procedures for all deployment scenarios
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md) - Common issues and solutions for production deployments
- [Production Checklist](docs/PRODUCTION_CHECKLIST.md) - Production readiness validation and deployment checklist
- [Chart Analysis Report](docs/05-chart-analysis-2025-11.md) - November 2025 comprehensive analysis of all 16 charts
