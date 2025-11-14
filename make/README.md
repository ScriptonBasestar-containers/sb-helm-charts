# make/ - Makefile Organization

This directory contains all Makefiles for chart operations and common targets.

## Directory Structure

```
make/
├── README.md           # This file
├── common.mk          # Common targets (lint, build, install, etc.)
└── ops/               # Chart-specific operational commands
    ├── browserless-chrome.mk
    ├── devpi.mk
    ├── keycloak.mk
    ├── memcached.mk
    ├── nextcloud.mk
    ├── rabbitmq.mk
    ├── redis.mk
    ├── rsshub.mk
    ├── wireguard.mk
    └── wordpress.mk
```

## Usage

### Common Operations (All Charts)

From project root:

```bash
make lint              # Lint all charts
make build             # Build/package all charts
make template          # Generate templates for all charts
make install           # Install all charts
make upgrade           # Upgrade all charts
make uninstall         # Uninstall all charts
```

### Chart-Specific Operations

Each chart has its own operational Makefile in `make/ops/`:

```bash
# General pattern
make -f make/ops/{chart-name}.mk {command}

# Examples
make -f make/ops/rabbitmq.mk rmq-stats
make -f make/ops/wireguard.mk wg-show
make -f make/ops/memcached.mk mc-stats
make -f make/ops/redis.mk redis-info
```

### Get Help for Specific Chart

```bash
make -f make/ops/rabbitmq.mk help
make -f make/ops/wireguard.mk help
make -f make/ops/memcached.mk help
```

## File Responsibilities

### `common.mk`

Common targets shared across all charts:
- `lint` - Helm lint
- `build` - Package chart
- `template` - Generate templates
- `install` - Install to Kubernetes
- `upgrade` - Upgrade existing installation
- `uninstall` - Remove from Kubernetes
- `dependency-update` - Update chart dependencies

### `ops/*.mk`

Chart-specific operational commands:
- Database operations (backup, restore, migrations)
- Service-specific diagnostics (stats, health checks)
- Admin commands (user management, configuration)
- Troubleshooting helpers (logs, shell access, port forwarding)

## Why This Structure?

1. **Cleaner Root Directory**: Only 1 Makefile in project root instead of 12
2. **Logical Grouping**: Common targets vs operational commands
3. **Scalability**: Easy to add new charts
4. **Discoverability**: All operational tools in one place
5. **Standard Convention**: Following industry best practices (`make/`, `scripts/`, `docs/`)

## Adding a New Chart

1. Create `make/ops/{new-chart}.mk`
2. Include common.mk:
   ```makefile
   include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

   CHART_NAME := new-chart
   CHART_DIR := charts/$(CHART_NAME)
   ```
3. Add chart-specific targets
4. Update `CLAUDE.md` with usage examples

## Migration Notes

**Old structure:**
```
Makefile.{chart}.mk  # 10 files in root
```

**New structure:**
```
make/ops/{chart}.mk  # Organized under make/
```

**Command changes:**
```bash
# Old
make -f Makefile.rabbitmq.mk rmq-stats

# New
make -f make/ops/rabbitmq.mk rmq-stats
```
