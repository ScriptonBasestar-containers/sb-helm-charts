# Service Mesh Integration Guide

**Version**: v1.4.0
**Last Updated**: 2025-12-09
**Scope**: Service mesh integration patterns for Helm chart deployments

## Table of Contents

1. [Overview](#overview)
2. [Istio Integration](#istio-integration)
3. [Linkerd Integration](#linkerd-integration)
4. [mTLS Configuration](#mtls-configuration)
5. [Traffic Management](#traffic-management)
6. [Observability](#observability)
7. [Security Policies](#security-policies)
8. [Multi-Cluster Setup](#multi-cluster-setup)
9. [Chart-Specific Configurations](#chart-specific-configurations)
10. [Best Practices](#best-practices)
11. [Troubleshooting](#troubleshooting)

---

## Overview

### Purpose

This guide provides comprehensive service mesh integration patterns for ScriptonBasestar Helm charts, covering Istio and Linkerd configurations for mTLS, traffic management, observability, and security.

### Service Mesh Comparison

| Feature | Istio | Linkerd |
|---------|-------|---------|
| **Complexity** | High | Low |
| **Resource Overhead** | Higher (100-200MB/sidecar) | Lower (10-20MB/proxy) |
| **mTLS** | Yes (automatic) | Yes (automatic) |
| **Traffic Management** | Advanced (VirtualService, DestinationRule) | Basic (ServiceProfile, TrafficSplit) |
| **Observability** | Built-in (Kiali, Jaeger, Prometheus) | Built-in (Linkerd Dashboard, Prometheus) |
| **Multi-Cluster** | Yes (complex setup) | Yes (simpler with multicluster extension) |
| **Best For** | Enterprise, complex routing needs | Simplicity, resource-constrained environments |

### Service Mesh Decision Matrix

| Chart Category | Recommended Mesh | Reason |
|----------------|------------------|--------|
| **Databases** (PostgreSQL, MySQL, MongoDB) | Optional | Direct TCP, consider performance impact |
| **Message Brokers** (Kafka, RabbitMQ) | Istio | Complex routing, observability needs |
| **Monitoring** (Prometheus, Grafana, Loki) | Linkerd | Lightweight, less overhead |
| **Applications** (Keycloak, Nextcloud, etc.) | Istio/Linkerd | mTLS, traffic management |
| **Caching** (Redis, Memcached) | Optional | Performance-critical, consider bypass |

---

## Istio Integration

### Installation

**Istio with Helm**:

```bash
# Add Istio Helm repository
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

# Create namespace
kubectl create namespace istio-system

# Install Istio base (CRDs)
helm install istio-base istio/base -n istio-system

# Install Istiod (control plane)
helm install istiod istio/istiod -n istio-system --wait

# Install Istio ingress gateway (optional)
kubectl create namespace istio-ingress
helm install istio-ingress istio/gateway -n istio-ingress
```

**Verify Installation**:

```bash
kubectl get pods -n istio-system
istioctl version
istioctl analyze
```

### Enable Sidecar Injection

**Namespace-Level Injection**:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    istio-injection: enabled
```

**Pod-Level Control**:

```yaml
# Enable injection for specific pod
metadata:
  annotations:
    sidecar.istio.io/inject: "true"

# Disable injection for specific pod (e.g., databases)
metadata:
  annotations:
    sidecar.istio.io/inject: "false"
```

### Istio Gateway Configuration

**Gateway for Ingress Traffic**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: main-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
    # HTTPS
    - port:
        number: 443
        name: https
        protocol: HTTPS
      hosts:
        - "*.example.com"
      tls:
        mode: SIMPLE
        credentialName: wildcard-cert

    # HTTP (redirect to HTTPS)
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "*.example.com"
      tls:
        httpsRedirect: true
```

### VirtualService for Routing

**Route to Grafana**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: grafana
  namespace: monitoring
spec:
  hosts:
    - "grafana.example.com"
  gateways:
    - istio-system/main-gateway
  http:
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: grafana
            port:
              number: 3000
      headers:
        response:
          set:
            strict-transport-security: "max-age=31536000; includeSubDomains"
```

**Route to Keycloak**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: keycloak
  namespace: auth
spec:
  hosts:
    - "auth.example.com"
  gateways:
    - istio-system/main-gateway
  http:
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: keycloak
            port:
              number: 8080
      timeout: 60s
      retries:
        attempts: 3
        perTryTimeout: 20s
        retryOn: gateway-error,connect-failure,refused-stream
```

### DestinationRule for Load Balancing

**PostgreSQL Connection Pooling**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: postgresql
  namespace: databases
spec:
  host: postgresql
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
        connectTimeout: 30s
      http:
        h2UpgradePolicy: DO_NOT_UPGRADE
    loadBalancer:
      simple: LEAST_REQUEST
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

**Redis with Circuit Breaker**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: redis
  namespace: caching
spec:
  host: redis
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1000
        connectTimeout: 10s
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
      minHealthPercent: 0
```

---

## Linkerd Integration

### Installation

**Linkerd with CLI**:

```bash
# Install Linkerd CLI
curl -fsL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# Validate cluster
linkerd check --pre

# Install Linkerd CRDs
linkerd install --crds | kubectl apply -f -

# Install Linkerd control plane
linkerd install | kubectl apply -f -

# Verify installation
linkerd check

# Install Linkerd Viz extension (dashboard)
linkerd viz install | kubectl apply -f -
linkerd viz check
```

**Access Dashboard**:

```bash
linkerd viz dashboard &
```

### Enable Proxy Injection

**Namespace-Level Injection**:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  annotations:
    linkerd.io/inject: enabled
```

**Pod-Level Control**:

```yaml
# Enable injection
metadata:
  annotations:
    linkerd.io/inject: enabled

# Disable injection (e.g., databases)
metadata:
  annotations:
    linkerd.io/inject: disabled
```

### ServiceProfile for Retries

**Grafana ServiceProfile**:

```yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: grafana.monitoring.svc.cluster.local
  namespace: monitoring
spec:
  routes:
    - name: GET /api/health
      condition:
        method: GET
        pathRegex: /api/health
      isRetryable: true
      timeout: 5s

    - name: GET /api/dashboards
      condition:
        method: GET
        pathRegex: /api/dashboards/.*
      isRetryable: true
      timeout: 30s
      responseClasses:
        - condition:
            status:
              min: 500
              max: 599
          isFailure: true

    - name: POST /api/dashboards
      condition:
        method: POST
        pathRegex: /api/dashboards/.*
      isRetryable: false
      timeout: 60s
```

### TrafficSplit for Canary Deployments

**Grafana Canary**:

```yaml
apiVersion: split.smi-spec.io/v1alpha4
kind: TrafficSplit
metadata:
  name: grafana-canary
  namespace: monitoring
spec:
  service: grafana
  backends:
    - service: grafana-stable
      weight: 90
    - service: grafana-canary
      weight: 10
```

---

## mTLS Configuration

### Istio mTLS

**Strict mTLS for Namespace**:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
```

**Permissive mTLS (Migration Period)**:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: PERMISSIVE
```

**Disable mTLS for Specific Service (e.g., External Database)**:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: postgresql-external
  namespace: databases
spec:
  selector:
    matchLabels:
      app: postgresql-client
  mtls:
    mode: DISABLE
```

**DestinationRule for mTLS**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: default
  namespace: production
spec:
  host: "*.production.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
```

### Linkerd mTLS

**Linkerd enables mTLS automatically** for all meshed traffic. No additional configuration needed.

**Verify mTLS**:

```bash
# Check if connections are encrypted
linkerd viz edges deployment -n production

# Sample output:
# SRC                  DST                  SRC_NS       DST_NS       SECURED
# api-server           postgresql           production   databases    √
# api-server           redis                production   caching      √
```

**Skip mTLS for External Services**:

```yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: external-api.example.com
  namespace: production
spec:
  opaquePorts:
    - 443  # Skip proxy for this port
```

---

## Traffic Management

### Canary Deployments

**Istio Canary with Weighted Routing**:

```yaml
# VirtualService for weighted routing
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: grafana
  namespace: monitoring
spec:
  hosts:
    - grafana
  http:
    - route:
        - destination:
            host: grafana
            subset: stable
          weight: 90
        - destination:
            host: grafana
            subset: canary
          weight: 10

---
# DestinationRule with subsets
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: grafana
  namespace: monitoring
spec:
  host: grafana
  subsets:
    - name: stable
      labels:
        version: v10.0.0
    - name: canary
      labels:
        version: v10.1.0
```

**Progressive Canary Rollout Script**:

```bash
#!/bin/bash
# Progressive canary rollout
# Usage: ./scripts/canary-rollout.sh <service> <namespace>

SERVICE="$1"
NAMESPACE="$2"

# Canary weights: 10% -> 25% -> 50% -> 75% -> 100%
WEIGHTS=(10 25 50 75 100)

for weight in "${WEIGHTS[@]}"; do
    echo "Setting canary weight to ${weight}%..."

    kubectl patch virtualservice ${SERVICE} -n ${NAMESPACE} --type='json' -p="[
      {\"op\": \"replace\", \"path\": \"/spec/http/0/route/0/weight\", \"value\": $((100 - weight))},
      {\"op\": \"replace\", \"path\": \"/spec/http/0/route/1/weight\", \"value\": ${weight}}
    ]"

    echo "Waiting 5 minutes to observe metrics..."
    sleep 300

    # Check error rate
    ERROR_RATE=$(curl -s "http://prometheus:9090/api/v1/query" \
      --data-urlencode "query=rate(istio_requests_total{destination_service_name=\"${SERVICE}\",response_code=~\"5.*\",destination_version=\"canary\"}[5m]) / rate(istio_requests_total{destination_service_name=\"${SERVICE}\",destination_version=\"canary\"}[5m])" \
      | jq -r '.data.result[0].value[1]')

    if (( $(echo "${ERROR_RATE} > 0.05" | bc -l) )); then
        echo "ERROR: Canary error rate ${ERROR_RATE} exceeds 5%. Rolling back..."
        kubectl patch virtualservice ${SERVICE} -n ${NAMESPACE} --type='json' -p="[
          {\"op\": \"replace\", \"path\": \"/spec/http/0/route/0/weight\", \"value\": 100},
          {\"op\": \"replace\", \"path\": \"/spec/http/0/route/1/weight\", \"value\": 0}
        ]"
        exit 1
    fi

    echo "Canary at ${weight}% - Error rate: ${ERROR_RATE}"
done

echo "Canary rollout complete. Promoting canary to stable..."
```

### Circuit Breaker

**Istio Circuit Breaker**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: keycloak
  namespace: auth
spec:
  host: keycloak
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: DO_NOT_UPGRADE
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
        maxRequestsPerConnection: 10
        maxRetries: 3
    outlierDetection:
      # Consecutive errors before ejection
      consecutive5xxErrors: 5
      consecutiveGatewayErrors: 5

      # How often to check
      interval: 10s

      # How long to eject
      baseEjectionTime: 30s

      # Max percentage of hosts to eject
      maxEjectionPercent: 50

      # Minimum healthy hosts
      minHealthPercent: 30
```

**Linkerd Circuit Breaker** (via ServiceProfile):

```yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: keycloak.auth.svc.cluster.local
  namespace: auth
spec:
  routes:
    - name: POST /auth/realms
      condition:
        method: POST
        pathRegex: /auth/realms/.*
      timeout: 30s
      isRetryable: false  # Don't retry on failure (circuit breaker behavior)
```

### Retry Policies

**Istio Retries**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-server
  namespace: production
spec:
  hosts:
    - api-server
  http:
    - route:
        - destination:
            host: api-server
      retries:
        attempts: 3
        perTryTimeout: 10s
        retryOn: gateway-error,connect-failure,refused-stream,retriable-4xx,retriable-status-codes
        retryRemoteLocalities: true
```

### Rate Limiting

**Istio Rate Limiting with EnvoyFilter**:

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: rate-limit-filter
  namespace: istio-system
spec:
  workloadSelector:
    labels:
      istio: ingressgateway
  configPatches:
    - applyTo: HTTP_FILTER
      match:
        context: GATEWAY
        listener:
          filterChain:
            filter:
              name: envoy.filters.network.http_connection_manager
              subFilter:
                name: envoy.filters.http.router
      patch:
        operation: INSERT_BEFORE
        value:
          name: envoy.filters.http.local_ratelimit
          typed_config:
            "@type": type.googleapis.com/udpa.type.v1.TypedStruct
            type_url: type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
            value:
              stat_prefix: http_local_rate_limiter
              token_bucket:
                max_tokens: 1000
                tokens_per_fill: 100
                fill_interval: 1s
              filter_enabled:
                runtime_key: local_rate_limit_enabled
                default_value:
                  numerator: 100
                  denominator: HUNDRED
              filter_enforced:
                runtime_key: local_rate_limit_enforced
                default_value:
                  numerator: 100
                  denominator: HUNDRED
              response_headers_to_add:
                - append: false
                  header:
                    key: x-local-rate-limit
                    value: "true"
```

### Timeout Configuration

**Istio Timeouts**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: slow-service
  namespace: production
spec:
  hosts:
    - slow-service
  http:
    - route:
        - destination:
            host: slow-service
      timeout: 60s  # Request timeout
```

**Per-Route Timeouts**:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-server
  namespace: production
spec:
  hosts:
    - api-server
  http:
    # Fast health checks
    - match:
        - uri:
            prefix: /health
      route:
        - destination:
            host: api-server
      timeout: 5s

    # Long-running exports
    - match:
        - uri:
            prefix: /api/export
      route:
        - destination:
            host: api-server
      timeout: 300s

    # Default
    - route:
        - destination:
            host: api-server
      timeout: 30s
```

---

## Observability

### Istio Observability Stack

**Kiali Dashboard**:

```bash
# Install Kiali
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml

# Access Kiali
kubectl port-forward svc/kiali -n istio-system 20001:20001
```

**Jaeger Tracing**:

```bash
# Install Jaeger
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml

# Access Jaeger UI
kubectl port-forward svc/tracing -n istio-system 16686:80
```

**Prometheus Metrics**:

```yaml
# Istio metrics scraping
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: istio-mesh
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: istiod
  namespaceSelector:
    matchNames:
      - istio-system
  endpoints:
    - port: http-monitoring
      interval: 15s
```

### Linkerd Observability

**Linkerd Viz Dashboard**:

```bash
# Install Linkerd Viz
linkerd viz install | kubectl apply -f -

# Access dashboard
linkerd viz dashboard
```

**Prometheus Integration**:

```yaml
# ServiceMonitor for Linkerd
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: linkerd-proxy
  namespace: monitoring
spec:
  selector:
    matchLabels:
      linkerd.io/control-plane-component: proxy
  namespaceSelector:
    any: true
  endpoints:
    - port: linkerd-admin
      path: /metrics
      interval: 30s
```

### Key Metrics to Monitor

**Istio Metrics**:

```promql
# Request rate by service
sum(rate(istio_requests_total[5m])) by (destination_service_name)

# Error rate by service (5xx)
sum(rate(istio_requests_total{response_code=~"5.*"}[5m])) by (destination_service_name) /
sum(rate(istio_requests_total[5m])) by (destination_service_name)

# P99 latency by service
histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket[5m])) by (le, destination_service_name))

# TCP connections
sum(istio_tcp_connections_opened_total) by (destination_service_name)

# mTLS status
sum(istio_requests_total{connection_security_policy="mutual_tls"}) by (destination_service_name) /
sum(istio_requests_total) by (destination_service_name)
```

**Linkerd Metrics**:

```promql
# Request rate by deployment
sum(rate(request_total[5m])) by (deployment)

# Success rate by deployment
sum(rate(request_total{classification="success"}[5m])) by (deployment) /
sum(rate(request_total[5m])) by (deployment)

# P99 latency
histogram_quantile(0.99, sum(rate(response_latency_ms_bucket[5m])) by (le, deployment))

# TCP connections
sum(tcp_open_total) by (deployment)
```

### Grafana Dashboards

**Istio Dashboards**:

- Istio Mesh Dashboard: `7639`
- Istio Service Dashboard: `7636`
- Istio Workload Dashboard: `7630`
- Istio Performance Dashboard: `11829`

**Linkerd Dashboards**:

- Linkerd Top Line: `15474`
- Linkerd Deployment: `15475`
- Linkerd Pod: `15478`

---

## Security Policies

### Istio Authorization Policies

**Deny All by Default**:

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: production
spec:
  {}  # Empty spec = deny all
```

**Allow Specific Services**:

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-grafana
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: grafana
  action: ALLOW
  rules:
    # Allow from istio-ingress
    - from:
        - source:
            namespaces: ["istio-ingress"]
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/api/*", "/login", "/logout"]

    # Allow from Prometheus (scraping)
    - from:
        - source:
            principals: ["cluster.local/ns/monitoring/sa/prometheus"]
      to:
        - operation:
            methods: ["GET"]
            paths: ["/metrics"]
```

**Keycloak Authorization Policy**:

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: keycloak-auth
  namespace: auth
spec:
  selector:
    matchLabels:
      app: keycloak
  action: ALLOW
  rules:
    # Allow from ingress for user authentication
    - from:
        - source:
            namespaces: ["istio-ingress"]
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/auth/*", "/realms/*"]

    # Allow admin access from admin namespace
    - from:
        - source:
            namespaces: ["admin"]
      to:
        - operation:
            methods: ["*"]
            paths: ["/auth/admin/*"]
```

**PostgreSQL Authorization Policy** (TCP):

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: postgresql-auth
  namespace: databases
spec:
  selector:
    matchLabels:
      app: postgresql
  action: ALLOW
  rules:
    # Allow from production namespace
    - from:
        - source:
            namespaces: ["production"]
      to:
        - operation:
            ports: ["5432"]

    # Allow from backup jobs
    - from:
        - source:
            principals: ["cluster.local/ns/backup/sa/backup-operator"]
      to:
        - operation:
            ports: ["5432"]
```

### Linkerd Authorization Policies

**Server Authorization**:

```yaml
apiVersion: policy.linkerd.io/v1beta1
kind: Server
metadata:
  name: grafana
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app: grafana
  port: 3000
  proxyProtocol: HTTP/1

---
apiVersion: policy.linkerd.io/v1beta1
kind: ServerAuthorization
metadata:
  name: grafana-auth
  namespace: monitoring
spec:
  server:
    name: grafana
  client:
    meshTLS:
      serviceAccounts:
        - name: prometheus
          namespace: monitoring
        - name: ingress-nginx
          namespace: ingress-nginx
```

---

## Multi-Cluster Setup

### Istio Multi-Cluster

**Primary-Remote Configuration**:

```yaml
# Primary cluster
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: istio-primary
spec:
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster1
      network: network1

---
# Remote cluster
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: istio-remote
spec:
  profile: remote
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster2
      network: network2
      remotePilotAddress: istiod.istio-system.svc.cluster1.example.com
```

**Cross-Cluster Service Discovery**:

```bash
# Create remote secret for cluster2 on cluster1
istioctl x create-remote-secret --context=cluster2 --name=cluster2 | kubectl apply -f - --context=cluster1

# Create remote secret for cluster1 on cluster2
istioctl x create-remote-secret --context=cluster1 --name=cluster1 | kubectl apply -f - --context=cluster2
```

### Linkerd Multi-Cluster

**Install Multi-Cluster Extension**:

```bash
# On both clusters
linkerd multicluster install | kubectl apply -f -
linkerd multicluster check

# Link clusters
linkerd multicluster link --cluster-name cluster2 | kubectl apply -f - --context=cluster1
```

**Export Services**:

```yaml
# Export Grafana to other clusters
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
  labels:
    mirror.linkerd.io/exported: "true"
spec:
  selector:
    app: grafana
  ports:
    - port: 3000
```

---

## Chart-Specific Configurations

### PostgreSQL

```yaml
# values-istio.yaml for PostgreSQL
podAnnotations:
  # Enable Istio sidecar for PostgreSQL
  sidecar.istio.io/inject: "true"

  # Hold application start until proxy is ready
  proxy.istio.io/config: '{"holdApplicationUntilProxyStarts": true}'

  # Exclude PostgreSQL port from sidecar (performance)
  traffic.sidecar.istio.io/excludeInboundPorts: "5432"

# Or disable sidecar entirely for maximum performance
# podAnnotations:
#   sidecar.istio.io/inject: "false"
```

### Grafana

```yaml
# values-istio.yaml for Grafana
podAnnotations:
  sidecar.istio.io/inject: "true"
  proxy.istio.io/config: '{"holdApplicationUntilProxyStarts": true}'

# Istio VirtualService
virtualService:
  enabled: true
  hosts:
    - grafana.example.com
  gateways:
    - istio-system/main-gateway
```

### Keycloak

```yaml
# values-istio.yaml for Keycloak
podAnnotations:
  sidecar.istio.io/inject: "true"
  proxy.istio.io/config: |
    holdApplicationUntilProxyStarts: true
    proxyStatsMatcher:
      inclusionPrefixes:
        - "cluster.outbound"
        - "listener"

# Keycloak-specific headers
extraEnv:
  - name: KC_PROXY
    value: "edge"  # Keycloak behind Istio ingress
  - name: KC_HOSTNAME_STRICT
    value: "false"
```

### Prometheus

```yaml
# values-istio.yaml for Prometheus
podAnnotations:
  sidecar.istio.io/inject: "true"

  # Prometheus needs to scrape Istio metrics
  traffic.sidecar.istio.io/includeOutboundPorts: "15014,15090"

# Add Istio scrape configs
prometheus:
  additionalScrapeConfigs:
    - job_name: 'istio-mesh'
      kubernetes_sd_configs:
        - role: endpoints
          namespaces:
            names:
              - istio-system
      relabel_configs:
        - source_labels: [__meta_kubernetes_service_name]
          action: keep
          regex: istiod
```

### Redis/Memcached

```yaml
# values-istio.yaml for Redis (disable sidecar for performance)
podAnnotations:
  sidecar.istio.io/inject: "false"

# OR enable with TCP metrics only
# podAnnotations:
#   sidecar.istio.io/inject: "true"
#   sidecar.istio.io/statsInclusionPrefixes: "tcp"
```

### Kafka

```yaml
# values-istio.yaml for Kafka
podAnnotations:
  sidecar.istio.io/inject: "true"

  # Kafka uses multiple ports
  traffic.sidecar.istio.io/includeInboundPorts: "9092,9093,9094"

  # Enable protocol sniffing
  sidecar.istio.io/enableProtocolSniffing: "true"
```

---

## Best Practices

### 1. Gradual Rollout

```bash
# Phase 1: Enable permissive mTLS (no breaking changes)
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: PERMISSIVE
EOF

# Phase 2: Monitor for issues (2-4 weeks)
istioctl analyze -n production

# Phase 3: Enable strict mTLS
kubectl patch peerauthentication default -n production --type='json' \
  -p='[{"op": "replace", "path": "/spec/mtls/mode", "value": "STRICT"}]'
```

### 2. Resource Optimization

```yaml
# Optimize sidecar resources
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio-sidecar-injector
  namespace: istio-system
data:
  values: |
    global:
      proxy:
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 500m
            memory: 256Mi
```

### 3. Exclude High-Performance Services

```yaml
# Exclude databases from service mesh
podAnnotations:
  sidecar.istio.io/inject: "false"

# OR exclude specific ports
podAnnotations:
  traffic.sidecar.istio.io/excludeInboundPorts: "5432,3306,6379"
```

### 4. Use Headless Services for StatefulSets

```yaml
# For PostgreSQL, MySQL, etc.
apiVersion: v1
kind: Service
metadata:
  name: postgresql-headless
spec:
  clusterIP: None
  selector:
    app: postgresql
  ports:
    - port: 5432
```

### 5. Configure Proper Timeouts

```yaml
# Set realistic timeouts
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: slow-api
spec:
  hosts:
    - slow-api
  http:
    - route:
        - destination:
            host: slow-api
      timeout: 60s  # Allow 60s for slow operations
      retries:
        attempts: 2
        perTryTimeout: 25s  # Each attempt can take 25s
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Connection Refused After Enabling mTLS

**Symptom**: Services can't connect after enabling strict mTLS

**Solution**:

```bash
# Check mTLS status
istioctl authn tls-check <pod> <service>

# Ensure DestinationRule matches PeerAuthentication
kubectl get peerauthentication,destinationrule -A

# Fix: Add DestinationRule for mTLS
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: default-mtls
  namespace: production
spec:
  host: "*.production.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF
```

#### Issue 2: Sidecar Not Injected

**Symptom**: Pods don't have sidecar containers

**Solution**:

```bash
# Check namespace labels
kubectl get namespace production --show-labels

# Add injection label
kubectl label namespace production istio-injection=enabled

# Check pod annotations
kubectl get pod <pod> -o jsonpath='{.metadata.annotations}'

# Restart pods to inject sidecar
kubectl rollout restart deployment -n production
```

#### Issue 3: High Latency with Service Mesh

**Symptom**: Increased latency after enabling service mesh

**Solution**:

```bash
# 1. Check sidecar resource usage
kubectl top pods -n production --containers

# 2. Increase sidecar resources if needed
kubectl patch deployment <deployment> -n production --type='json' -p='[
  {"op": "add", "path": "/spec/template/metadata/annotations/sidecar.istio.io~1proxyCPU", "value": "500m"},
  {"op": "add", "path": "/spec/template/metadata/annotations/sidecar.istio.io~1proxyMemory", "value": "256Mi"}
]'

# 3. For performance-critical services, consider excluding from mesh
kubectl patch deployment <deployment> -n production --type='json' -p='[
  {"op": "add", "path": "/spec/template/metadata/annotations/sidecar.istio.io~1inject", "value": "false"}
]'
```

#### Issue 4: Circuit Breaker Tripping Too Often

**Symptom**: OutlierDetection ejecting too many hosts

**Solution**:

```yaml
# Adjust outlier detection thresholds
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: service-outlier
spec:
  host: my-service
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 10       # Increase from 5
      consecutiveGatewayErrors: 10   # Increase from 5
      interval: 30s                  # Increase from 10s
      baseEjectionTime: 60s          # Increase from 30s
      maxEjectionPercent: 30         # Decrease from 50
      minHealthPercent: 50           # Increase from 30
```

#### Issue 5: Linkerd Proxy Injection Failing

**Symptom**: Pods stuck in Init:0/1 state

**Solution**:

```bash
# Check proxy-injector logs
kubectl logs -n linkerd deployments/linkerd-proxy-injector

# Check webhook configuration
kubectl get mutatingwebhookconfigurations

# Restart proxy-injector
kubectl rollout restart deployment/linkerd-proxy-injector -n linkerd
```

### Debugging Commands

**Istio Debugging**:

```bash
# Analyze configuration
istioctl analyze -n production

# Check proxy status
istioctl proxy-status

# Check proxy configuration
istioctl proxy-config cluster <pod> -n production
istioctl proxy-config listener <pod> -n production
istioctl proxy-config route <pod> -n production

# Check Envoy logs
kubectl logs <pod> -c istio-proxy -n production

# Enable debug logging
istioctl proxy-config log <pod> --level debug
```

**Linkerd Debugging**:

```bash
# Check overall health
linkerd check

# Check proxy status
linkerd viz stat deployment -n production

# Check tap (live traffic)
linkerd viz tap deployment/<deployment> -n production

# Check edges (service-to-service connections)
linkerd viz edges deployment -n production

# Check routes
linkerd viz routes deployment/<deployment> -n production
```

---

**Document Version**: 1.0
**Last Updated**: 2025-12-09
**Maintained By**: Platform Team
**Review Cycle**: Quarterly
