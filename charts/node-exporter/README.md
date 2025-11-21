# Node Exporter Helm Chart

![Version: 0.3.0](https://img.shields.io/badge/Version-0.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.7.0](https://img.shields.io/badge/AppVersion-1.7.0-informational?style=flat-square)

Prometheus Node Exporter for hardware and OS metrics with Kubernetes integration

## Features

- **DaemonSet Deployment**: Runs on all nodes including masters
- **Host Metrics Access**: Uses hostNetwork and hostPID for accurate metrics
- **Comprehensive Metrics**: CPU, memory, disk, network, filesystem, load average
- **Configurable Collectors**: Enable/disable specific metric collectors
- **ServiceMonitor Support**: Integration with Prometheus Operator
- **Security**: Runs as non-root, read-only root filesystem
- **Operational Tools**: 20+ Makefile commands

## TL;DR

```bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with default configuration
helm install my-node-exporter scripton-charts/node-exporter

# Install with ServiceMonitor for Prometheus Operator
helm install my-node-exporter scripton-charts/node-exporter \
  --set serviceMonitor.enabled=true
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Prometheus for metrics collection

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `hostNetwork` | Use host network namespace | `true` |
| `hostPID` | Use host PID namespace | `true` |
| `collectors.enabled` | Enable collector configuration | `true` |
| `collectors.disable` | Collectors to disable | `[ipvs]` |
| `service.port` | Metrics port | `9100` |
| `serviceMonitor.enabled` | Enable ServiceMonitor | `false` |

## Operational Commands

```bash
# View logs
make -f make/ops/node-exporter.mk ne-logs

# View logs from specific node
make -f make/ops/node-exporter.mk ne-logs-node NODE=node-1

# Check DaemonSet status
make -f make/ops/node-exporter.mk ne-status

# Get metrics
make -f make/ops/node-exporter.mk ne-metrics

# Get CPU metrics
make -f make/ops/node-exporter.mk ne-cpu-metrics

# Get memory metrics
make -f make/ops/node-exporter.mk ne-memory-metrics

# Port forward
make -f make/ops/node-exporter.mk ne-port-forward

# List nodes
make -f make/ops/node-exporter.mk ne-list-nodes
```

## Metrics Collected

### CPU Metrics

```promql
# CPU usage by mode
node_cpu_seconds_total

# CPU frequency
node_cpu_frequency_hertz

# Thermal metrics
node_hwmon_temp_celsius
```

### Memory Metrics

```promql
# Total memory
node_memory_MemTotal_bytes

# Available memory
node_memory_MemAvailable_bytes

# Used memory
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes

# Memory usage percentage
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100
```

### Disk Metrics

```promql
# Disk I/O
node_disk_read_bytes_total
node_disk_written_bytes_total

# Filesystem usage
node_filesystem_avail_bytes
node_filesystem_size_bytes

# Filesystem usage percentage
(1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100
```

### Network Metrics

```promql
# Network traffic
node_network_receive_bytes_total
node_network_transmit_bytes_total

# Network errors
node_network_receive_errs_total
node_network_transmit_errs_total
```

### Load Average

```promql
# Load average (1, 5, 15 minutes)
node_load1
node_load5
node_load15
```

## Integration with Prometheus

### Method 1: ServiceMonitor (Prometheus Operator)

```yaml
serviceMonitor:
  enabled: true
  interval: 30s
  labels:
    prometheus: kube-prometheus
```

### Method 2: Prometheus Scrape Config

```yaml
scrape_configs:
  - job_name: 'node-exporter'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
        action: keep
        regex: node-exporter
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: node
```

### Method 3: Annotation-based Discovery

Already configured in default values:

```yaml
service:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9100"
```

## Grafana Dashboards

Import these popular dashboards:

1. **Node Exporter Full** (ID: 1860)
   ```
   https://grafana.com/grafana/dashboards/1860
   ```

2. **Node Exporter for Prometheus** (ID: 11074)
   ```
   https://grafana.com/grafana/dashboards/11074
   ```

3. **Kubernetes Node Exporter** (ID: 13978)
   ```
   https://grafana.com/grafana/dashboards/13978
   ```

## PromQL Query Examples

### CPU Usage

```promql
# CPU usage per node (%)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# CPU usage by mode
rate(node_cpu_seconds_total[5m])
```

### Memory Usage

```promql
# Memory usage (%)
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Memory available (GB)
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024
```

### Disk Usage

```promql
# Disk usage (%)
(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100

# Disk I/O rate (MB/s)
rate(node_disk_read_bytes_total[5m]) / 1024 / 1024
```

### Network Traffic

```promql
# Network receive rate (MB/s)
rate(node_network_receive_bytes_total[5m]) / 1024 / 1024

# Network transmit rate (MB/s)
rate(node_network_transmit_bytes_total[5m]) / 1024 / 1024
```

## Collectors

### Default Enabled Collectors

- `cpu` - CPU metrics
- `diskstats` - Disk I/O metrics
- `filesystem` - Filesystem metrics
- `loadavg` - Load average
- `meminfo` - Memory metrics
- `netdev` - Network device metrics
- `stat` - System statistics
- `time` - System time
- `uname` - System information

### Optional Collectors

Enable additional collectors:

```yaml
collectors:
  enable:
    - processes  # Process metrics
    - systemd    # Systemd service metrics
    - tcpstat    # TCP connection statistics
```

### Disable Collectors

```yaml
collectors:
  disable:
    - ipvs       # IPVS metrics (disabled by default)
    - wifi       # WiFi metrics
```

## Production Setup

```yaml
# values-prod.yaml
hostNetwork: true
hostPID: true

collectors:
  enabled: true
  enable:
    - processes
  disable:
    - ipvs

extraArgs:
  - --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+)($|/)
  - --collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$

serviceMonitor:
  enabled: true
  interval: 30s
  labels:
    prometheus: kube-prometheus

resources:
  limits:
    cpu: 500m
    memory: 256Mi
  requests:
    cpu: 200m
    memory: 128Mi

priorityClassName: "system-node-critical"
```

## Troubleshooting

### Check Node Exporter Status

```bash
make -f make/ops/node-exporter.mk ne-status
```

### View Metrics

```bash
make -f make/ops/node-exporter.mk ne-port-forward
curl http://localhost:9100/metrics
```

### Check Specific Node

```bash
make -f make/ops/node-exporter.mk ne-metrics-node NODE=node-1
```

### Common Issues

**Issue**: No metrics for specific node

**Solution**:
```bash
# Check if pod is running on the node
make -f make/ops/node-exporter.mk ne-list-nodes

# Check pod logs
make -f make/ops/node-exporter.mk ne-logs-node NODE=node-1
```

**Issue**: Permission denied errors

**Solution**:
- Ensure `hostNetwork: true` and `hostPID: true`
- Check pod security policies allow privileged access

## License

- Chart: BSD 3-Clause License
- Node Exporter: Apache License 2.0

## Additional Resources

- [Node Exporter Documentation](https://github.com/prometheus/node_exporter)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.3.0
**Node Exporter Version**: 1.7.0
