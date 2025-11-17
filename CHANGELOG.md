# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- **Redis v0.3.1** (2025-11-17): Fixed password exposure in readiness probe using REDISCLI_AUTH environment variable
- **Redis v0.3.1** (2025-11-17): Fixed password exposure in metrics exporter command-line arguments

### Fixed
- **Redis v0.3.1** (2025-11-17): Fixed `persistence.existingClaim` support - now properly mounts existing PVCs

### Added
- **Documentation** (2025-11-17): Comprehensive Testing Guide (docs/TESTING_GUIDE.md) with scenarios for all charts
- **Documentation** (2025-11-17): Chart Analysis Report (docs/05-chart-analysis-2025-11.md) documenting production readiness
- **CI/CD** (2025-11-17): Metadata validation job in GitHub Actions workflow
- **Memcached v0.3.2** (2025-11-17): Application-level health probe using stats command validation
- **READMEs** (2025-11-17): Recent Changes sections added to Redis, Memcached, and RabbitMQ

### Changed
- **Memcached v0.3.1→0.3.2** (2025-11-17): Improved readinessProbe from TCP socket check to memcached stats validation
- **Memcached v0.3.1** (2025-11-17): Clarified architecture documentation in prod-master-replica values file
- **RabbitMQ v0.3.1** (2025-11-17): Clarified single-instance architecture in prod-master-replica values file
- **RabbitMQ v0.3.1** (2025-11-17): Added documentation for production clustering alternatives (Operator, Bitnami)
- **Redis v0.3.1** (2025-11-17): Added clear warnings to Sentinel/Cluster values files (modes not implemented)
- **CI/CD** (2025-11-17): Enhanced lint-test workflow with metadata consistency validation

### Added

#### Nextcloud 0.3.0 - File Sync and Collaboration Platform
- **Mature Status** (0.2.0 → 0.3.0)
  - Promoted to Mature status with production-ready features
  - 3 PVC architecture for data isolation
  - External PostgreSQL 16 and Redis 8 integration
- **3 PVC Architecture** (Data Isolation)
  - Data PVC: User files, photos, and documents storage
  - Config PVC: Nextcloud configuration and settings
  - Apps PVC: Custom apps and extensions
  - Independent size configuration per PVC
  - Flexible storage class assignment
- **External Service Integration**
  - PostgreSQL 16 for database with connection pooling
  - Redis 8 for session management and memory cache
  - Existing secret support for credentials
  - Flexible connection configuration
- **Apache-based Deployment**
  - Official Nextcloud image with Apache HTTP Server
  - CalDAV and CardDAV support for calendar and contacts
  - WebDAV protocol for file access
  - .htaccess configuration for security
- **occ Command Integration** (Nextcloud CLI)
  - `nextcloud-init`: Initialize Nextcloud installation
  - `nextcloud-setup`: Run maintenance and repair tasks
  - Database management via occ
  - User and group management
  - App installation and configuration
- **Background Jobs**
  - Kubernetes CronJob for Nextcloud background tasks
  - Scheduled maintenance operations
  - File scanning and indexing
  - Activity notifications
- **Collaboration Features**
  - File sharing with users and groups
  - Public link sharing with expiration
  - Calendar and contacts synchronization
  - Real-time document editing (with apps)
  - Comments and activity streams
- **Makefile Operational Commands** (`make/ops/nextcloud.mk`)
  - `nextcloud-init`: Initialize Nextcloud
  - `nextcloud-setup`: Maintenance and repair
- **Deployment Scenarios** (4 values files)
  - `values-home-single.yaml`: Home server (100-500m CPU, 256-512Mi RAM, 10Gi)
  - `values-startup-single.yaml`: Startup environment (250m-1000m CPU, 512Mi-1Gi RAM, 20Gi)
  - `values-prod-master-replica.yaml`: Production HA (500m-2000m CPU, 1-2Gi RAM, 50Gi, 3 replicas)
  - `values-example.yaml`: Production template
- **Comprehensive Documentation** (`README.md`)
  - CalDAV/CardDAV configuration
  - PostgreSQL and Redis setup guide
  - Background jobs configuration
  - Deployment scenarios with resource specifications
  - Operational commands reference

#### WordPress 0.3.0 - Content Management System
- **Mature Status** (0.2.0 → 0.3.0)
  - Promoted to Mature status with production-ready features
  - wp-cli integration for command-line management
  - External MySQL/MariaDB database support
- **wp-cli Integration**
  - Core management: Install, update, and configure WordPress via command line
  - Plugin management: Install, activate, update, and remove plugins
  - Theme management: Install, activate, update themes
  - User management: Create, update, delete users
  - Database operations: Export, import, optimize database
- **External Database Support**
  - MySQL/MariaDB external service integration
  - Flexible connection configuration (host, port, database, credentials)
  - Existing secret support for credentials
  - SSL/TLS connection support
- **Apache-based Deployment**
  - Official WordPress image with Apache HTTP Server
  - mod_rewrite enabled for permalinks
  - PHP-FPM optimizations
  - Production-ready .htaccess configuration
- **Makefile Operational Commands** (`make/ops/wordpress.mk`)
  - `wp-cli`: Run any wp-cli command
  - `wp-install`: Install WordPress (URL, title, admin credentials)
  - `wp-update`: Update WordPress core, plugins, and themes
- **Configuration Management**
  - WordPress salts and keys auto-generation
  - Table prefix customization
  - Debug mode toggle
  - Site URL and home URL configuration
  - Plugin and theme auto-installation on deploy
- **Deployment Scenarios** (4 values files)
  - `values-home-single.yaml`: Home server (100-500m CPU, 256-512Mi RAM, 5Gi)
  - `values-startup-single.yaml`: Startup environment (250m-1000m CPU, 512Mi-1Gi RAM, 10Gi)
  - `values-prod-master-replica.yaml`: Production HA (500m-2000m CPU, 1-2Gi RAM, 20Gi, 3 replicas)
  - `values-example.yaml`: Production template
- **Comprehensive Documentation** (`README.md`)
  - wp-cli usage examples
  - MySQL/MariaDB configuration guide
  - Plugin and theme management
  - Deployment scenarios with resource specifications
  - Operational commands reference

#### RustFS 0.3.0 - S3-Compatible Object Storage
- **Mature Status** (0.2.0 → 0.3.0)
  - Promoted to Mature status with production-ready features
  - Full S3 API compatibility for MinIO/Ceph migration
  - StatefulSet-based clustering with HA support
- **S3 API Compatibility**
  - Full AWS S3 API implementation
  - Seamless migration from MinIO or Ceph
  - S3-compatible client support (aws-cli, mc, s3cmd, boto3)
  - Bucket operations, object operations, multipart uploads
  - Pre-signed URLs and access control
- **StatefulSet Clustering**
  - 4+ replica HA deployment for production
  - Multi-drive support per pod (configurable dataDirs)
  - Automatic pod discovery and coordination
  - StatefulSet DNS for stable network identities
  - Headless service for direct pod access
- **Tiered Storage Support** (Hot/Cold Architecture)
  - Hot tier: SSD storage for frequently accessed objects
  - Cold tier: HDD storage for archival and backup
  - Automatic tier selection based on storage class
  - Mixed storage configuration per pod
  - Independent size configuration per tier
- **Performance**
  - 2.3x faster than MinIO for 4K small files
  - Rust-based implementation for memory safety and speed
  - Optimized for high-concurrency workloads
- **Makefile Operational Commands** (`make/ops/rustfs.mk`)
  - Credentials: `rustfs-get-credentials`
  - Port forwarding: `rustfs-port-forward-api`, `rustfs-port-forward-console`
  - S3 testing: `rustfs-test-s3` (MinIO Client integration)
  - Health monitoring: `rustfs-health`, `rustfs-metrics`
  - Operations: `rustfs-scale`, `rustfs-restart`, `rustfs-backup`
  - Logging: `rustfs-logs`, `rustfs-logs-all`
  - Status: `rustfs-status`, `rustfs-all`
  - Utilities: `rustfs-shell`
- **Deployment Scenarios** (4 values files)
  - `values-home-single.yaml`: Home server (100-500m CPU, 256-512Mi RAM, 10Gi)
  - `values-startup-single.yaml`: Startup environment (250m-1000m CPU, 512Mi-1Gi RAM, 50Gi)
  - `values-prod-master-replica.yaml`: Production HA (500m-2000m CPU, 1-2Gi RAM, 100Gi per pod, 4 replicas)
  - `values-example.yaml`: Production template
- **Comprehensive Documentation** (`README.md`)
  - S3 API usage examples
  - MinIO/Ceph migration guide
  - Tiered storage configuration
  - Clustering and HA setup
  - Deployment scenarios with resource specifications
  - Operational commands reference

#### Uptime Kuma 0.3.0 - Self-Hosted Monitoring Tool
- **Mature Status** (0.2.0 → 0.3.0)
  - Promoted to Mature status with production-ready features
  - 90+ notification services integration
  - Multi-protocol monitoring support
- **Notification Services** (90+ Integrations)
  - Chat platforms: Telegram, Discord, Slack, Microsoft Teams, Mattermost
  - Email: SMTP, SendGrid, Mailgun, AWS SES
  - SMS: Twilio, Nexmo, Clickatell
  - VoIP: Skype, Teams Call
  - Push notifications: Pushbullet, Pushover, Pushy, Apprise
  - Incident management: PagerDuty, Opsgenie, Alertmanager
  - And 70+ more services
- **Multi-Protocol Monitoring**
  - HTTP/HTTPS: GET, POST, keyword matching, status codes
  - TCP: Port connectivity checks
  - Ping: ICMP ping monitoring
  - DNS: DNS query and record validation
  - SMTP: Email server monitoring
  - WebSocket: Real-time connection monitoring
  - Database: MongoDB, MySQL, PostgreSQL health checks
- **Database Support**
  - SQLite: Zero-configuration embedded database (default)
  - MariaDB/MySQL: External database for production HA
  - Flexible database type switching via configuration
  - Automatic database migrations
- **Makefile Operational Commands** (`make/ops/uptime-kuma.mk`)
  - Basic operations: `uk-logs`, `uk-shell`, `uk-port-forward`
  - Health checks: `uk-check-db`, `uk-check-storage`
  - Data management: `uk-backup-sqlite`, `uk-restore-sqlite`
  - User management: `uk-reset-password`
  - System info: `uk-version`, `uk-node-info`, `uk-get-settings`
  - Operations: `uk-restart`, `uk-scale`
  - API access: `uk-list-monitors`, `uk-status-pages`
- **Additional Features**
  - Beautiful web UI with modern design
  - Public status pages for services
  - Multi-user support with 2FA
  - Multi-language support (25+ languages)
  - Customizable monitoring intervals
  - SSL/TLS certificate monitoring
- **Deployment Scenarios** (4 values files)
  - `values-home-single.yaml`: Home server (50-250m CPU, 128-256Mi RAM, 2Gi)
  - `values-startup-single.yaml`: Startup environment (100-500m CPU, 256-512Mi RAM, 5Gi)
  - `values-prod-master-replica.yaml`: Production (250m-1000m CPU, 512Mi-1Gi RAM, 10Gi)
  - `values-example.yaml`: Production template
- **Comprehensive Documentation** (`README.md`)
  - Database configuration guide (SQLite vs MariaDB)
  - Notification service setup examples
  - Monitoring protocol configuration
  - Status page creation guide
  - Deployment scenarios with resource specifications
  - Operational commands reference

#### Paperless-ngx 0.3.0 - Document Management System
- **Mature Status** (0.2.0 → 0.3.0)
  - Promoted to Mature status with production-ready features
  - 4 PVC architecture for document lifecycle management
  - PostgreSQL and Redis external service integration
- **4 PVC Architecture** (Unique Document Lifecycle)
  - Consume PVC (10Gi): Incoming documents directory for auto-import
  - Data PVC (10Gi): Application data and search index
  - Media PVC (50Gi): Processed and archived documents (largest storage)
  - Export PVC (10Gi): Document exports and backups
  - Each PVC independently configurable (size, storageClass, existingClaim)
- **OCR and Document Processing**
  - Multi-language OCR support (100+ languages)
  - Configurable OCR modes: skip, redo, force
  - Automatic document consumption with inotify or polling
  - Configurable source document deletion after processing
  - Subdirectories as tags for automatic organization
- **External Service Integration**
  - PostgreSQL 13+ with SSL/TLS support
  - Redis 6+ for caching and session management
  - Email integration for document import
  - SMTP configuration for notifications
- **Makefile Operational Commands** (`make/ops/paperless-ngx.mk`)
  - Basic operations: `paperless-logs`, `paperless-shell`, `paperless-port-forward`
  - Health checks: `paperless-check-db`, `paperless-check-redis`, `paperless-check-storage`
  - Database: `paperless-migrate`, `paperless-create-superuser`
  - Documents: `paperless-document-exporter`, `paperless-consume-list`, `paperless-process-status`
  - Operations: `paperless-restart`
- **Deployment Scenarios** (4 values files)
  - `values-home-single.yaml`: Home server (100-500m CPU, 256-512Mi RAM, 15Gi total)
  - `values-startup-single.yaml`: Startup environment (250m-1000m CPU, 512Mi-1Gi RAM, 50Gi total)
  - `values-prod-master-replica.yaml`: Production (500m-2000m CPU, 1-2Gi RAM, 200Gi total)
  - `values-example.yaml`: Production template
- **Comprehensive Documentation** (`README.md`)
  - 4 PVC architecture explanation
  - OCR configuration and language support
  - Deployment scenarios with resource specifications
  - External service setup guide
  - Document import and processing workflow
  - Operational commands reference

#### Redis 0.3.0 - In-Memory Data Store
- **Mature Status** (0.2.0 → 0.3.0)
  - Promoted to Mature status with production-ready features
  - Master-Slave replication support (1 master + N read-only replicas)
  - Full redis.conf configuration file support
- **Master-Slave Replication**
  - Automatic master-replica setup via StatefulSet
  - Read-only replicas with automatic replication lag monitoring
  - DNS-based service discovery for master and replicas
  - Individual replica access via StatefulSet DNS
- **Configuration Management**
  - Full redis.conf file support (no environment variable abstraction)
  - Customizable persistence (RDB snapshots, AOF)
  - Memory management (maxmemory, eviction policies)
  - Security settings (password, protected-mode)
  - Slow log and client limits configuration
- **Makefile Operational Commands** (`make/ops/redis.mk`)
  - Data management: `redis-backup`, `redis-restore`, `redis-bgsave`, `redis-flushall`
  - Analysis: `redis-slowlog`, `redis-bigkeys`, `redis-config-get`, `redis-info`
  - Replication: `redis-replication-info`, `redis-master-info`, `redis-replica-lag`, `redis-role`
  - Monitoring: `redis-memory`, `redis-stats`, `redis-clients`, `redis-monitor`
  - Utilities: `redis-cli`, `redis-ping`, `redis-shell`, `redis-logs`, `redis-metrics`
- **Deployment Scenarios** (6 values files)
  - `values-home-single.yaml`: Home server (50-250m CPU, 128-512Mi RAM, 5Gi)
  - `values-startup-single.yaml`: Startup environment (100-500m CPU, 256Mi-1Gi RAM, 10Gi)
  - `values-prod-master-replica.yaml`: HA with replication (250m-2000m CPU, 512Mi-2Gi RAM, 20Gi)
  - `values-prod-cluster.yaml`: Redis cluster mode
  - `values-prod-sentinel.yaml`: Sentinel-based HA
  - `values-example.yaml`: Production template
- **Comprehensive Documentation** (`README.md`)
  - Production operator comparison (Spotahome Redis Operator)
  - Migration guide to operator for HA requirements
  - Deployment scenarios with resource specifications
  - Replication configuration and service discovery
  - Operational commands reference
  - Use case recommendations (dev/test vs production)

#### Immich 0.3.0 - AI-Powered Photo Management
- **Mature Status** (0.2.0 → 0.3.0)
  - Promoted to Mature status with production-ready features
  - Microservices architecture (separate server and machine-learning deployments)
  - External PostgreSQL with pgvecto.rs extension and Redis support
- **Microservices Architecture**
  - Independent server deployment for web UI and API
  - Separate machine-learning deployment for AI features
  - Shared model cache persistence between ML workers
  - Independent resource allocation and scaling
- **Hardware Acceleration Support**
  - CUDA: NVIDIA GPU acceleration for machine learning
  - ROCm: AMD GPU acceleration for machine learning
  - OpenVINO: Intel GPU/CPU acceleration
  - ARMNN: ARM neural network acceleration
  - Configurable device mapping for GPU access
- **External Service Integration**
  - PostgreSQL with pgvecto.rs extension for vector search
  - Redis for caching and session management
  - Automatic database connection health checks
  - Typesense support for advanced search capabilities
- **Model Cache Management**
  - Persistent volume for machine learning models
  - Shared cache across ML worker replicas
  - Configurable storage size (default 10Gi)
- **Makefile Operational Commands** (`make/ops/immich.mk`)
  - `immich-logs-server`: View server logs
  - `immich-logs-ml`: View machine-learning logs
  - `immich-shell-server`: Open shell in server pod
  - `immich-shell-ml`: Open shell in ML pod
  - `immich-restart-server`: Restart server deployment
  - `immich-restart-ml`: Restart ML deployment
  - `immich-port-forward`: Port forward to localhost:2283
  - `immich-check-db`: Test PostgreSQL connection
  - `immich-check-redis`: Test Redis connection
- **Deployment Scenarios** (values files)
  - `values-home-single.yaml`: Home server configuration
  - `values-startup-single.yaml`: Startup/small business setup
  - `values-prod-master-replica.yaml`: Production HA configuration
- **Comprehensive Documentation** (`README.md`)
  - Microservices architecture explanation
  - Hardware acceleration guide for all platforms
  - External service integration guide
  - Deployment scenarios with examples
  - Operational commands reference

#### Vaultwarden 0.3.0 - Production-Ready Password Manager
- **Mature Status** (0.2.0 → 0.3.0)
  - Promoted to Mature status with production-ready features
  - Auto-switching workload type (StatefulSet for SQLite, Deployment for external DB)
  - Complete Makefile operational commands
- **Backup & Restore** (`make/ops/vaultwarden.mk`)
  - `vw-backup-db`: Backup SQLite database to tmp/vaultwarden-backups/
  - `vw-restore-db`: Restore SQLite database from backup
  - `vw-db-test`: Test external database connection (PostgreSQL/MySQL)
- **Admin Panel Management**
  - `vw-get-admin-token`: Retrieve admin panel token
  - `vw-admin`: Open admin panel in browser
  - `vw-get-config`: Show current configuration
- **Database Mode Support**
  - SQLite (embedded) mode: StatefulSet with PVC
  - PostgreSQL/MySQL mode: Deployment (stateless)
  - Automatic workload type selection based on database configuration
- **Security Features**
  - Admin token management
  - SMTP password retrieval (vw-get-smtp-password)
  - Database URL encryption
- **Comprehensive Documentation** (`README.md`)
  - Bitwarden feature comparison
  - Deployment scenarios (home server, startup, production)
  - Database mode switching guide
  - Admin panel security guide
  - Operational commands reference

#### Jellyfin 0.3.0 - Complete GPU Acceleration Support
- **AMD VAAPI GPU Support** (New)
  - Added AMD VAAPI hardware acceleration alongside Intel QSV and NVIDIA NVENC
  - Automatic `/dev/dri` device mounting for AMD GPUs
  - Automatic supplementalGroups (44, 109) for AMD VAAPI
  - Updated deployment.yaml, _helpers.tpl, and values.yaml
- **Home Server Configuration** (`values-home-single.yaml`)
  - Optimized for Raspberry Pi 4, Intel NUC, and Mini PCs
  - Minimal resources: 2 CPU cores, 2Gi RAM
  - Reduced storage: 2Gi config, 5Gi cache
  - hostPath media directories with NAS mount examples
  - Intel QSV GPU acceleration examples
  - Relaxed health checks for home server use
- **Comprehensive Documentation** (`README.md`)
  - Complete GPU acceleration guide for all vendors (Intel QSV, NVIDIA NVENC, AMD VAAPI)
  - Media library configuration guide (hostPath, PVC, existing claims)
  - Deployment scenarios (home server, startup, production)
  - Operational commands reference
  - Troubleshooting guide for GPU and media library issues
- **Enhanced Makefile Operations** (`make/ops/jellyfin.mk`)
  - Updated `jellyfin-check-gpu` command to support AMD VAAPI
  - Added renderD* device listing for debugging
  - Consolidated Intel/AMD GPU check logic

#### Chart Metadata Management System
- **Centralized Metadata** (`charts-metadata.yaml`)
  - Single source of truth for chart keywords, tags, descriptions
  - 16 charts documented with complete metadata
  - Categories: `application` and `infrastructure`
  - Searchable keywords for Artifact Hub integration
- **Automation Scripts**
  - `scripts/validate-chart-metadata.py` - Validates keywords consistency
  - `scripts/sync-chart-keywords.py` - Syncs Chart.yaml keywords from metadata
  - `scripts/generate-chart-catalog.py` - Generates comprehensive chart catalog
  - `scripts/generate-artifacthub-dashboard.py` - Generates Artifact Hub statistics dashboard
  - `scripts/requirements.txt` - Python dependencies (PyYAML>=6.0)
- **Makefile Targets**
  - `make validate-metadata` - Validate metadata consistency
  - `make sync-keywords` - Sync Chart.yaml keywords
  - `make sync-keywords-dry-run` - Preview sync changes
  - `make generate-catalog` - Generate docs/CHARTS.md from metadata
  - `make generate-artifacthub-dashboard` - Generate Artifact Hub dashboard
- **Pre-commit Hooks** (Enhanced)
  - Automatic metadata validation before commits
  - Validates Chart.yaml and charts-metadata.yaml consistency
  - Fixed configuration (removed unsupported additional_dependencies from system language hook)
  - Trailing whitespace and end-of-file auto-fixes applied
  - Conventional commits enforcement
  - YAML, Markdown, and Shell script linting
- **CI/CD Automation** (Ready for deployment)
  - Metadata validation job for GitHub Actions (manual application pending)
  - Catalog verification to ensure docs/CHARTS.md is up-to-date
  - Workflow triggers for metadata and scripts changes
  - See `WORKFLOW_MANUAL_APPLY.md` for deployment instructions
- **Artifact Hub Integration**
  - `artifacthub-repo.yml` - Repository metadata for Artifact Hub
  - Container image security scanning configuration
  - Repository links and maintainer information
  - Ready for Artifact Hub publishing (requires GitHub Pages)
- **Documentation**
  - [Chart Catalog](docs/CHARTS.md) - Auto-generated catalog of all 16 charts with badges and examples
  - [Artifact Hub Dashboard](docs/ARTIFACTHUB_DASHBOARD.md) - Artifact Hub statistics and publishing guide
  - [Chart README Template](docs/CHART_README_TEMPLATE.md) - Standard chart README structure
  - [Chart README Guide](docs/CHART_README_GUIDE.md) - Template usage guide
  - [Workflow Update Instructions](docs/WORKFLOW_UPDATE_INSTRUCTIONS.md) - CI workflow manual update
  - `WORKFLOW_MANUAL_APPLY.md` - Step-by-step guide for workflow deployment
  - Updated CLAUDE.md with metadata management workflow and catalog generation
  - Updated CONTRIBUTING.md with metadata workflow steps
  - Updated README.md with Available Charts section and catalog links

#### Development Tools
- Deployment Scenarios sections to all 16 chart READMEs
  - Home Server scenario (minimal resources)
  - Startup Environment scenario (balanced configuration)
  - Production HA scenario (high availability with monitoring)
- Artifact Hub metadata to all charts (16 charts total)
  - v0.3.0 charts (7 charts): keycloak, wireguard, memcached, rabbitmq, browserless-chrome, devpi, rsshub
  - v0.2.0 charts (9 charts): redis, rustfs, immich, jellyfin, vaultwarden, nextcloud, wordpress, paperless-ngx, uptime-kuma
  - Detailed changelog entries (`artifacthub.io/changes`)
  - Recommendations to Scenario Values Guide and Chart Development Guide
  - Links to chart source and upstream documentation
- Recent Changes section in main README.md
  - Highlights v0.3.0 release features
  - Links to CHANGELOG.md for complete version history
- `.gitattributes` file for Git optimization
  - Normalized line endings (LF)
  - Enhanced diff drivers for YAML, JSON, Markdown
  - Export-ignore for development files
- `.pre-commit-config.yaml` for code quality automation
  - General file checks (trailing whitespace, EOF, YAML validation)
  - YAML linting with yamllint (line-length: 120)
  - Helm chart linting for all charts
  - Chart metadata validation (NEW)
  - Markdown linting with markdownlint
  - Shell script linting with shellcheck
  - Conventional commits enforcement
  - CI auto-fix and auto-update configuration
- `.github/CONTRIBUTING.md` comprehensive contribution guide
  - Code of Conduct and Getting Started
  - Chart Development Guidelines (core principles, values.yaml structure, database strategy)
  - Chart Metadata Workflow (4-step process with sync and validation)
  - Pull Request Process and checklist
  - Coding Standards (Helm templates, helper functions, NOTES.txt pattern)
  - Testing Requirements (lint, template rendering, install/upgrade tests)
  - Documentation Standards (README, CHANGELOG, Artifact Hub annotations)

## [0.3.0] - 2025-11-16

### Added
- **Scenario Values Files**: Pre-configured deployment scenarios for all charts
  - `values-home-single.yaml` - Minimal resources for personal servers (Raspberry Pi, NUC, home labs)
  - `values-startup-single.yaml` - Balanced configuration for small teams and startups
  - `values-prod-master-replica.yaml` - High availability with clustering, monitoring, and auto-scaling
- **Documentation**:
  - Comprehensive [Scenario Values Guide](docs/SCENARIO_VALUES_GUIDE.md) with deployment examples
  - [Chart Development Guide](docs/CHART_DEVELOPMENT_GUIDE.md) scenario testing section
  - Deployment Scenarios section in main README.md
- **CI/CD**:
  - Scenario file validation in GitHub Actions workflow
  - Automated linting for all scenario values files
- **Makefile Targets**:
  - `install-home`, `install-startup`, `install-prod` for scenario-based deployments
  - `validate-scenarios` and `list-scenarios` for scenario management

### Changed
- **Chart Versions** (MINOR bump for new features):
  - keycloak: 0.2.0 → 0.3.0
  - redis: 0.2.0 → 0.3.0
  - memcached: 0.2.0 → 0.3.0
  - rabbitmq: 0.2.0 → 0.3.0
  - wireguard: 0.2.0 → 0.3.0
  - browserless-chrome: 0.2.0 → 0.3.0
  - devpi: 0.2.0 → 0.3.0
  - rsshub: 0.2.0 → 0.3.0
  - rustfs: 0.2.0 → 0.3.0

### Details

**Charts with Scenario Files (Total: 18 scenario files across 16 charts)**:

| Chart | home-single | startup-single | prod-master-replica |
|-------|-------------|----------------|---------------------|
| browserless-chrome | ✅ | ✅ | ✅ |
| devpi | ✅ | ✅ | ✅ |
| immich | ✅ | ✅ | ✅ |
| jellyfin | ✅ | ✅ | ✅ |
| keycloak | ✅ | ✅ | ✅ |
| memcached | ✅ | ✅ | ✅ |
| nextcloud | ✅ | ✅ | ✅ |
| paperless-ngx | ✅ | ✅ | ✅ |
| rabbitmq | ✅ | ✅ | ✅ |
| redis | ✅ | ✅ | ✅ |
| rsshub | ✅ | ✅ | ✅ |
| rustfs | ✅ | ✅ | ✅ |
| uptime-kuma | ✅ | ✅ | ✅ |
| vaultwarden | ✅ | ✅ | ✅ |
| wireguard | ✅ | ✅ | ✅ |
| wordpress | ✅ | ✅ | ✅ |

**Resource Allocation Philosophy**:
- **Home Server**: 50-500m CPU, 128Mi-512Mi RAM - Optimized for edge devices
- **Startup Environment**: 100m-1000m CPU, 256Mi-1Gi RAM - Balanced for teams
- **Production HA**: 250m-2000m CPU, 512Mi-2Gi RAM - Enterprise-ready with scaling

## [0.2.0] - 2025-11-16

### Added
- Version bumps for charts transitioning from development (0.1.0) to beta (0.2.0)
  - nextcloud: 0.1.0 → 0.2.0
  - paperless-ngx: 0.1.0 → 0.2.0
  - uptime-kuma: 0.1.0 → 0.2.0
  - wordpress: 0.1.0 → 0.2.0

### Changed
- Aligned chart versions to reflect feature completeness and scenario values support

## [0.1.0] - Initial Releases

### Charts in Development (0.1.0)
- immich
- jellyfin
- vaultwarden

### Stable Charts (0.2.0+)
- keycloak: 0.3.0 (Keycloak 26.0.6, PostgreSQL 13+, Redis support, clustering)
- redis: 0.3.0 (Redis 7.4.1, master-replica replication, Prometheus metrics)
- wireguard: 0.3.0 (WireGuard VPN, no external dependencies)
- memcached: 0.3.0 (Memcached 1.6.32, HPA support)
- rabbitmq: 0.3.0 (RabbitMQ 4.0.4, management UI, Prometheus metrics)
- browserless-chrome: 0.3.0 (Headless Chrome for automation)
- devpi: 0.3.0 (Python package index, SQLite/PostgreSQL support)
- rsshub: 0.3.0 (RSS aggregator)
- rustfs: 0.3.0 (S3-compatible object storage, clustering)
- nextcloud: 0.2.0 (Nextcloud 31.0.10, PostgreSQL 16, Redis 8)
- paperless-ngx: 0.2.0 (Document management with OCR, 4 PVC architecture)
- uptime-kuma: 0.2.0 (Uptime monitoring, SQLite database)
- wordpress: 0.2.0 (WordPress 6.4.3, MySQL/MariaDB support)

---

## Version Policy

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (X.0.0): Breaking changes requiring user action
- **MINOR** (0.X.0): New features, backward-compatible
- **PATCH** (0.0.X): Bug fixes, documentation updates

See [Chart Version Policy](docs/CHART_VERSION_POLICY.md) for detailed versioning rules.

---

## Links

- **Repository**: https://github.com/scriptonbasestar-container/sb-helm-charts
- **Helm Repository**: https://scriptonbasestar-container.github.io/sb-helm-charts
- **Documentation**: https://github.com/scriptonbasestar-container/sb-helm-charts/tree/master/docs
- **Issues**: https://github.com/scriptonbasestar-container/sb-helm-charts/issues

[Unreleased]: https://github.com/scriptonbasestar-container/sb-helm-charts/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/scriptonbasestar-container/sb-helm-charts/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/scriptonbasestar-container/sb-helm-charts/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/scriptonbasestar-container/sb-helm-charts/releases/tag/v0.1.0
