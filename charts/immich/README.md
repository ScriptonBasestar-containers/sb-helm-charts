# Immich Helm Chart

[Immich](https://immich.app/) is a high-performance self-hosted photo and video management solution with AI-powered features including facial recognition, object detection, and smart search.

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm install my-immich scripton-charts/immich \
  --set postgresql.external.host=postgres.default.svc \
  --set postgresql.external.password=strongpass \
  --set redis.external.host=redis.default.svc
```

## Introduction

This chart bootstraps an Immich deployment on a Kubernetes cluster using microservices architecture.

**Key Features:**
- 🎯 Microservices architecture (server + machine-learning)
- 🤖 AI-powered features (facial recognition, object detection, CLIP search)
- 📦 External PostgreSQL + Redis (pgvecto.rs extension required)
- 🚀 Hardware acceleration support (CUDA, ROCm, OpenVINO, ARMNN)
- 📱 Mobile app support (iOS & Android)
- 🔒 Production-ready with HPA, PDB, NetworkPolicy

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- **External PostgreSQL 14+** with [pgvecto.rs](https://github.com/tensorchord/pgvecto.rs) extension
- **External Redis/Valkey 6+**
- PV provisioner support

## Versioning

| Chart Version | App Version | Kubernetes | Helm | Notes |
|---------------|-------------|------------|------|-------|
| 0.1.0         | v1.122.3    | 1.19+      | 3.0+ | Initial release with microservices |

## Architecture

Immich consists of two main services:

1. **Server** (immich-server)
   - REST API backend
   - Web UI serving
   - Database & Redis coordination
   - Photo/video upload handling

2. **Machine Learning** (immich-ml)
   - Facial recognition
   - Object detection (CLIP)
   - Smart search indexing
   - Hardware acceleration (optional)

## Installing the Chart

### Basic Installation

```bash
helm install my-immich scripton-charts/immich \
  --set postgresql.external.host=postgres-host \
  --set postgresql.external.password=dbpass \
  --set redis.external.host=redis-host
```

### Production Installation with GPU

```bash
helm install my-immich scripton-charts/immich \
  -f values-example.yaml \
  --set postgresql.external.password=strongpass \
  --set redis.external.password=redispass
```

## Configuration

### Core Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `immich.server.enabled` | Enable server service | `true` |
| `immich.server.replicaCount` | Server replicas | `1` |
| `immich.machineLearning.enabled` | Enable ML service | `true` |
| `immich.machineLearning.acceleration` | Hardware acceleration (`none`, `cuda`, `rocm`, `openvino`) | `none` |

### External Services (REQUIRED)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.external.host` | PostgreSQL hostname | `""` (REQUIRED) |
| `postgresql.external.password` | PostgreSQL password | `""` (REQUIRED) |
| `redis.external.host` | Redis hostname | `""` (REQUIRED) |

### Persistence

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.library.size` | Photo library size | `100Gi` |
| `immich.machineLearning.modelCache.size` | ML model cache | `10Gi` |

## Hardware Acceleration

Enable GPU acceleration for ML workloads:

### NVIDIA CUDA

```yaml
immich:
  machineLearning:
    acceleration: "cuda"
    resources:
      limits:
        nvidia.com/gpu: 1
```

### AMD ROCm

```yaml
immich:
  machineLearning:
    acceleration: "rocm"
```

### Intel OpenVINO

```yaml
immich:
  machineLearning:
    acceleration: "openvino"
```

## Operational Commands

```bash
# Port forward to localhost
make -f make/ops/immich.mk immich-port-forward

# View logs
make -f make/ops/immich.mk immich-logs-server
make -f make/ops/immich.mk immich-logs-ml

# Check connectivity
make -f make/ops/immich.mk immich-check-db
make -f make/ops/immich.mk immich-check-redis

# Get version
make -f make/ops/immich.mk immich-get-version
```

## PostgreSQL Setup

Immich requires **pgvecto.rs** extension. Install it on your PostgreSQL:

```sql
CREATE EXTENSION IF NOT EXISTS vectors;
```

Or use PostgreSQL with extension pre-installed:
```yaml
postgresql:
  image: tensorchord/pgvecto-rs:pg17-v0.3.0
```

## Mobile App Setup

1. Install mobile app: [Immich Mobile](https://immich.app/docs/install/mobile)
2. Configure server URL in app settings
3. Use HTTPS for production deployments

## Troubleshooting

### PostgreSQL Extension Missing

**Error**: `extension "vectors" does not exist`

**Solution**: Install pgvecto.rs extension on PostgreSQL server.

### ML Service Not Processing

Check ML logs:
```bash
make -f make/ops/immich.mk immich-logs-ml
```

Verify model cache:
```bash
make -f make/ops/immich.mk immich-check-ml-cache
```

## Project Philosophy

Follows [ScriptonBasestar Helm Charts](https://github.com/scriptonbasestar-container/sb-helm-charts) principles:

- ✅ External databases (PostgreSQL + Redis)
- ✅ Microservices architecture
- ✅ Production-ready defaults
- ✅ No complex subcharts

## License

- **Chart License:** BSD-3-Clause
- **Immich License:** AGPL-3.0

## Links

- **Immich Official:** https://immich.app
- **Documentation:** https://docs.immich.app
- **Docker Hub:** https://github.com/immich-app/immich/pkgs/container/immich-server
- **Chart Repository:** https://github.com/scriptonbasestar-container/sb-helm-charts

## Support

For issues: https://github.com/scriptonbasestar-container/sb-helm-charts/issues
