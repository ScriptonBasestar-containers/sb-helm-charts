# Blackbox Exporter Helm Chart

![Version: 0.3.0](https://img.shields.io/badge/Version-0.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.24.0](https://img.shields.io/badge/AppVersion-0.24.0-informational?style=flat-square)

Blackbox Exporter for probing endpoints over HTTP, HTTPS, DNS, TCP, and ICMP

## Features

- **Multi-Protocol Probing**: HTTP, HTTPS, TCP, DNS, ICMP
- **SSL/TLS Verification**: Certificate validation and expiry monitoring
- **Flexible Configuration**: Custom probe modules
- **ServiceMonitor**: Prometheus Operator integration
- **Operational Tools**: 15+ Makefile commands

## TL;DR

\`\`\`bash
helm repo add scripton-charts https://scriptonbasestar-container.github.io/sb-helm-charts
helm repo update

# Install with default configuration
helm install my-bbe scripton-charts/blackbox-exporter

# Install with production configuration
helm install my-bbe scripton-charts/blackbox-exporter -f values-small-prod.yaml
\`\`\`

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- (Optional) Prometheus Operator for ServiceMonitor

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| \`replicaCount\` | Number of replicas | \`1\` |
| \`config.modules\` | Probe module configurations | 7 modules |
| \`serviceMonitor.enabled\` | Enable ServiceMonitor | \`false\` |

### Available Modules

- **http_2xx**: Basic HTTP probe
- **http_post_2xx**: HTTP POST probe
- **https_2xx**: HTTPS with SSL verification
- **tcp_connect**: TCP connection probe
- **icmp**: ICMP ping probe
- **dns_udp**: DNS probe over UDP
- **dns_tcp**: DNS probe over TCP

## Operational Commands

### Probe Testing

\`\`\`bash
# Test HTTP probe
make -f make/ops/blackbox-exporter.mk bbe-probe-http TARGET=https://example.com

# Test HTTPS probe
make -f make/ops/blackbox-exporter.mk bbe-probe-https TARGET=https://example.com

# Test TCP probe
make -f make/ops/blackbox-exporter.mk bbe-probe-tcp TARGET=example.com:443

# Test DNS probe
make -f make/ops/blackbox-exporter.mk bbe-probe-dns TARGET=8.8.8.8

# Test custom module
make -f make/ops/blackbox-exporter.mk bbe-probe-custom TARGET=https://api.example.com MODULE=http_2xx
\`\`\`

### Module Management

\`\`\`bash
# List all modules
make -f make/ops/blackbox-exporter.mk bbe-list-modules

# View module configuration
make -f make/ops/blackbox-exporter.mk bbe-test-module MODULE=http_2xx
\`\`\`

### Basic Operations

\`\`\`bash
# View logs
make -f make/ops/blackbox-exporter.mk bbe-logs

# Check status
make -f make/ops/blackbox-exporter.mk bbe-status

# View config
make -f make/ops/blackbox-exporter.mk bbe-config

# Port forward
make -f make/ops/blackbox-exporter.mk bbe-port-forward
\`\`\`

## Prometheus Integration

### Static Config

\`\`\`yaml
scrape_configs:
  - job_name: 'blackbox-http'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - https://example.com
        - https://prometheus.io
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
\`\`\`

### ServiceMonitor (Prometheus Operator)

\`\`\`yaml
serviceMonitor:
  enabled: true
  interval: 60s
\`\`\`

Then create Probe CRDs:

\`\`\`yaml
apiVersion: monitoring.coreos.com/v1
kind: Probe
metadata:
  name: example-website
spec:
  prober:
    url: blackbox-exporter:9115
  module: http_2xx
  targets:
    staticConfig:
      static:
        - https://example.com
\`\`\`

## Custom Module Examples

### HTTP with Authentication

\`\`\`yaml
config:
  modules:
    http_auth:
      prober: http
      http:
        method: GET
        headers:
          Authorization: "Bearer token123"
\`\`\`

### HTTPS with Client Certificate

\`\`\`yaml
config:
  modules:
    https_mtls:
      prober: http
      http:
        tls_config:
          cert_file: /etc/certs/client.crt
          key_file: /etc/certs/client.key
          ca_file: /etc/certs/ca.crt
\`\`\`

### TCP with Custom Query

\`\`\`yaml
config:
  modules:
    ssh_banner:
      prober: tcp
      tcp:
        query_response:
          - expect: "^SSH-2.0-"
\`\`\`

## PromQL Examples

\`\`\`promql
# Probe success
probe_success{job="blackbox"}

# HTTP status code
probe_http_status_code{job="blackbox"}

# SSL certificate expiry (days)
(probe_ssl_earliest_cert_expiry - time()) / 86400

# Probe duration
probe_duration_seconds{job="blackbox"}

# Alert if probe fails
probe_success == 0
\`\`\`

## Alerting Examples

\`\`\`yaml
groups:
  - name: blackbox
    rules:
      - alert: EndpointDown
        expr: probe_success == 0
        for: 5m
        annotations:
          summary: "Endpoint {{ $labels.instance }} is down"

      - alert: SSLCertExpiringSoon
        expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 30
        annotations:
          summary: "SSL cert for {{ $labels.instance }} expires in {{ $value }} days"

      - alert: SlowResponse
        expr: probe_duration_seconds > 5
        annotations:
          summary: "{{ $labels.instance }} response time: {{ $value }}s"
\`\`\`

## Production Setup

\`\`\`yaml
# values-prod.yaml
replicaCount: 2

config:
  modules:
    http_2xx:
      prober: http
      timeout: 10s
      http:
        valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
        follow_redirects: true
    
    https_2xx:
      prober: http
      timeout: 10s
      http:
        tls_config:
          insecure_skip_verify: false

serviceMonitor:
  enabled: true
  interval: 60s

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - blackbox-exporter
          topologyKey: kubernetes.io/hostname

priorityClassName: "system-cluster-critical"
\`\`\`

## Troubleshooting

### Probe Fails with Timeout

Increase timeout in module configuration:

\`\`\`yaml
config:
  modules:
    http_2xx:
      prober: http
      timeout: 15s  # Increased from 5s
\`\`\`

### SSL Verification Fails

For development/testing with self-signed certificates:

\`\`\`yaml
config:
  modules:
    https_insecure:
      prober: http
      http:
        tls_config:
          insecure_skip_verify: true
\`\`\`

### DNS Probe Issues

Check DNS server is accessible:

\`\`\`bash
make -f make/ops/blackbox-exporter.mk bbe-probe-dns TARGET=8.8.8.8
\`\`\`

## License

- Chart: BSD 3-Clause License
- Blackbox Exporter: Apache License 2.0

## Additional Resources

- [Blackbox Exporter Documentation](https://github.com/prometheus/blackbox_exporter)
- [Configuration Guide](https://github.com/prometheus/blackbox_exporter/blob/master/CONFIGURATION.md)
- [Chart Repository](https://github.com/scriptonbasestar-container/sb-helm-charts)

---

**Maintained by**: ScriptonBasestar
**Chart Version**: 0.3.0
**Blackbox Exporter Version**: 0.24.0
