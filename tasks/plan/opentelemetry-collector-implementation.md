# OpenTelemetry Collector Chart 구현 계획

**우선순위**: High
**복잡도**: Complex
**예상 소요**: 2-3시간

## 개요

OpenTelemetry Collector는 벤더 중립적인 텔레메트리 데이터 수집기로, traces, metrics, logs를 통합 수집하여 다양한 백엔드로 전송합니다.

## 구현 목표

### 지원 기능

```yaml
Receivers:
  - otlp (gRPC: 4317, HTTP: 4318)
  - prometheus (scrape 설정)
  - jaeger (옵션)
  - zipkin (옵션)

Processors:
  - batch
  - memory_limiter
  - resourcedetection (kubernetes)
  - k8sattributes

Exporters:
  - prometheusremotewrite (Prometheus/Mimir)
  - loki (로그)
  - otlp (Tempo)
  - debug (개발용)

Extensions:
  - health_check
  - zpages
```

## 파일 구조

```
charts/opentelemetry-collector/
├── Chart.yaml
├── values.yaml
├── values-example.yaml
├── README.md
├── templates/
│   ├── _helpers.tpl
│   ├── configmap.yaml          # collector config
│   ├── deployment.yaml         # 또는 daemonset.yaml
│   ├── service.yaml
│   ├── serviceaccount.yaml
│   ├── clusterrole.yaml        # k8s metadata 수집용
│   ├── clusterrolebinding.yaml
│   ├── servicemonitor.yaml     # 옵션
│   ├── pdb.yaml                # 옵션
│   ├── hpa.yaml                # 옵션
│   ├── NOTES.txt
│   └── tests/
│       └── test-connection.yaml
```

## Chart.yaml

```yaml
apiVersion: v2
name: opentelemetry-collector
description: OpenTelemetry Collector for unified telemetry collection
type: application
version: 0.3.0
appVersion: "0.96.0"
keywords:
  - opentelemetry
  - otel
  - telemetry
  - tracing
  - metrics
  - logging
  - observability
maintainers:
  - name: ScriptonBasestar
home: https://opentelemetry.io/
sources:
  - https://github.com/open-telemetry/opentelemetry-collector
```

## values.yaml 구조

```yaml
replicaCount: 1

image:
  repository: otel/opentelemetry-collector-contrib
  tag: ""  # defaults to appVersion
  pullPolicy: IfNotPresent

mode: deployment  # deployment 또는 daemonset

config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

  processors:
    batch:
      timeout: 5s
      send_batch_size: 10000
    memory_limiter:
      check_interval: 1s
      limit_percentage: 80
      spike_limit_percentage: 25

  exporters:
    debug:
      verbosity: basic
    # 사용자가 설정
    prometheusremotewrite: {}
    otlp/tempo: {}
    loki: {}

  extensions:
    health_check:
      endpoint: 0.0.0.0:13133

  service:
    extensions: [health_check]
    pipelines:
      traces:
        receivers: [otlp]
        processors: [batch]
        exporters: [debug]
      metrics:
        receivers: [otlp]
        processors: [batch]
        exporters: [debug]
      logs:
        receivers: [otlp]
        processors: [batch]
        exporters: [debug]

# Kubernetes RBAC (k8sattributes processor용)
rbac:
  create: true
  clusterRole: true

serviceAccount:
  create: true
  name: ""

service:
  type: ClusterIP
  ports:
    otlp-grpc: 4317
    otlp-http: 4318
    metrics: 8888

resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 200m
    memory: 400Mi

# ServiceMonitor for Prometheus Operator
serviceMonitor:
  enabled: false
  namespace: ""
  labels: {}

# Pod Disruption Budget
podDisruptionBudget:
  enabled: false
  minAvailable: 1

# Autoscaling
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
```

## values-example.yaml (프로덕션)

```yaml
# Production configuration with Prometheus, Loki, Tempo backends
replicaCount: 2

config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

  processors:
    batch:
      timeout: 5s
      send_batch_size: 10000
    memory_limiter:
      check_interval: 1s
      limit_percentage: 80
      spike_limit_percentage: 25
    resourcedetection:
      detectors: [env, system, k8snode]
    k8sattributes:
      extract:
        metadata:
          - k8s.namespace.name
          - k8s.deployment.name
          - k8s.pod.name
          - k8s.node.name

  exporters:
    prometheusremotewrite:
      endpoint: http://mimir:8080/api/v1/push
      tls:
        insecure: true
    otlp/tempo:
      endpoint: tempo:4317
      tls:
        insecure: true
    loki:
      endpoint: http://loki:3100/loki/api/v1/push

  service:
    extensions: [health_check]
    pipelines:
      traces:
        receivers: [otlp]
        processors: [memory_limiter, k8sattributes, batch]
        exporters: [otlp/tempo]
      metrics:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [prometheusremotewrite]
      logs:
        receivers: [otlp]
        processors: [memory_limiter, k8sattributes, batch]
        exporters: [loki]

resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 500m
    memory: 1Gi

serviceMonitor:
  enabled: true
  labels:
    release: prometheus

podDisruptionBudget:
  enabled: true
  minAvailable: 1

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
```

## ConfigMap 템플릿 핵심

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "otel-collector.fullname" . }}
  labels:
    {{- include "otel-collector.labels" . | nindent 4 }}
data:
  config.yaml: |
    {{- toYaml .Values.config | nindent 4 }}
```

## 검증 체크리스트

- [ ] `helm lint charts/opentelemetry-collector`
- [ ] `helm template` 출력 확인
- [ ] ConfigMap YAML 유효성
- [ ] RBAC 권한 검토
- [ ] Service 포트 매핑 확인
- [ ] README.md 완성도
- [ ] charts-metadata.yaml 업데이트

## 참고 자료

- [OTel Collector Contrib](https://github.com/open-telemetry/opentelemetry-collector-contrib)
- [Official Helm Chart](https://github.com/open-telemetry/opentelemetry-helm-charts)
- [Configuration Reference](https://opentelemetry.io/docs/collector/configuration/)
- [Kubernetes Receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/k8sclusterreceiver)
