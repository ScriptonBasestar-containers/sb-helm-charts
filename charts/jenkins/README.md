# Jenkins Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/sb-helm-charts)](https://artifacthub.io/packages/helm/sb-helm-charts/jenkins)

Jenkins CI/CD server with a pre-built custom controller image, persistent storage, and JCasC support.

## Features

- Custom controller image support (plugins baked in)
- JCasC (Configuration as Code) via ConfigMap
- Persistent Jenkins home (PVC)
- Optional Ingress, RBAC, NetworkPolicy, HPA, PDB, ServiceMonitor

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- PersistentVolume provisioner

## Quick Start

```bash
helm install jenkins ./charts/jenkins
```

Access Jenkins:

```bash
kubectl port-forward svc/jenkins 8080:8080
# Visit http://localhost:8080
```

## Configuration

### Admin Credentials

- Default username: `admin`
- Password is generated if `controller.admin.password` is empty
- You can supply an existing secret via `controller.admin.existingSecret`

```yaml
controller:
  admin:
    username: admin
    password: ""
    existingSecret: ""
    passwordKey: jenkins-admin-password
```

### JCasC Configuration

Enable JCasC and provide config scripts:

```yaml
controller:
  jcasc:
    enabled: true
    defaultConfig: true
    configScripts:
      welcome-message: |
        jenkins:
          systemMessage: "Managed by Helm"
```

### Ingress

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: jenkins.example.com
      paths:
        - path: /
          pathType: Prefix
```

### ServiceMonitor

```yaml
serviceMonitor:
  enabled: true
  path: /prometheus
  interval: 30s
  scrapeTimeout: 10s
```

## Deployment Scenarios

- `values-home-single.yaml`: minimal resources for home labs
- `values-prod-master-replica.yaml`: production-oriented defaults (monitoring, policy, ingress)

## Values Reference

See `charts/jenkins/values.yaml` for all configuration options.
