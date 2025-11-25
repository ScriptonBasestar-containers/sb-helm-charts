# Advanced High Availability Guide

Comprehensive guide for deploying sb-helm-charts in highly available, multi-region, and disaster recovery configurations.

## Overview

This guide covers advanced HA patterns beyond basic replication:

1. **Multi-Zone Deployment**: Cross-AZ pod distribution
2. **Multi-Region Setup**: Active-active and active-passive patterns
3. **Disaster Recovery**: Backup, restore, and failover procedures
4. **Data Replication**: Cross-region data synchronization
5. **Traffic Management**: Global load balancing and failover

## Architecture Patterns

### Pattern 1: Single-Region Multi-Zone HA

**Use Case**: Protect against zone failures within a region

```
Region: us-east-1
├── Zone A (Availability Zone 1)
│   ├── App Pod 1
│   ├── Database Primary
│   └── Storage Volume 1
├── Zone B (Availability Zone 2)
│   ├── App Pod 2
│   ├── Database Replica
│   └── Storage Volume 2
└── Zone C (Availability Zone 3)
    ├── App Pod 3
    └── Storage Volume 3
```

**Implementation:**

```yaml
# Anti-affinity for cross-zone distribution
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
                - myapp
        topologyKey: topology.kubernetes.io/zone

# Topology spread constraints
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: myapp
```

### Pattern 2: Multi-Region Active-Passive

**Use Case**: DR site ready for failover

```
Primary Region (us-east-1)     Standby Region (us-west-2)
├── Active Traffic             ├── Standby (no traffic)
├── Database Primary           ├── Database Replica (async)
└── Object Storage (S3)        └── Object Storage (replicated)
```

**Implementation:**

```yaml
# Primary region values.yaml
replicaCount: 3

database:
  replication:
    enabled: true
    role: primary

backup:
  enabled: true
  destination: s3://backup-bucket-west/
  schedule: "0 */6 * * *"

# Standby region values.yaml
replicaCount: 1  # Minimal standby

database:
  replication:
    enabled: true
    role: replica
    primaryHost: db.us-east-1.example.com

backup:
  enabled: true
  restore:
    enabled: true
    source: s3://backup-bucket-west/
```

### Pattern 3: Multi-Region Active-Active

**Use Case**: Geo-distributed load, local latency

```
Region 1 (us-east-1)          Region 2 (eu-west-1)
├── Active Traffic (50%)      ├── Active Traffic (50%)
├── Database (multi-master)   ├── Database (multi-master)
└── Object Storage (sync)     └── Object Storage (sync)
```

**Implementation:**

```yaml
# Global traffic manager (external DNS + geo-routing)
apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: global-app
spec:
  endpoints:
    - dnsName: app.example.com
      recordType: A
      targets:
        - us-east-1-lb.example.com
        - eu-west-1-lb.example.com
      providerSpecific:
        - name: routing-policy
          value: geoproximity
        - name: health-check
          value: enabled
```

## Multi-Zone Deployment

### Pod Distribution

**Topology Spread Constraints:**

```yaml
# Spread evenly across zones
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: myapp

  - maxSkew: 2
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: myapp
```

**Pod Anti-Affinity:**

```yaml
# Required anti-affinity (hard constraint)
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: myapp
        topologyKey: topology.kubernetes.io/zone

# Preferred anti-affinity (soft constraint)
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: myapp
          topologyKey: kubernetes.io/hostname
```

### Storage Considerations

**Regional vs Zonal Storage:**

```yaml
# Zonal storage (default)
persistence:
  storageClass: gp3  # AWS EBS
  accessModes:
    - ReadWriteOnce

# Regional storage (for cross-zone access)
persistence:
  storageClass: efs-sc  # AWS EFS
  accessModes:
    - ReadWriteMany
```

**Volume Snapshot for DR:**

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: myapp-snapshot
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: myapp-data
```

### PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
spec:
  minAvailable: 2  # Ensure 2 pods always available
  selector:
    matchLabels:
      app.kubernetes.io/name: myapp

# Alternative: maxUnavailable
spec:
  maxUnavailable: 1  # Only 1 pod can be down
```

## Database High Availability

### PostgreSQL HA Patterns

**Primary-Replica Setup:**

```yaml
# Primary database
postgresql:
  replication:
    enabled: true
    numSynchronousReplicas: 1
    synchronousCommit: "on"

  resources:
    limits:
      cpu: 4000m
      memory: 8Gi

# Replica configuration
postgresql:
  replica:
    enabled: true
    replicaCount: 2
    resources:
      limits:
        cpu: 2000m
        memory: 4Gi
```

**Automated Failover (Patroni/Stolon):**

For production HA, use operators:

```bash
# CloudNativePG Operator
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml

# PostgreSQL Cluster CRD
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-ha
spec:
  instances: 3
  primaryUpdateStrategy: unsupervised
  storage:
    size: 100Gi
  backup:
    barmanObjectStore:
      destinationPath: s3://backups/
      s3Credentials:
        accessKeyId:
          name: s3-creds
          key: ACCESS_KEY_ID
```

### MySQL/MariaDB HA

**Galera Cluster:**

```yaml
# 3-node Galera cluster
mysql:
  architecture: replication
  replication:
    enabled: true

  primary:
    persistence:
      size: 100Gi

  secondary:
    replicaCount: 2
    persistence:
      size: 100Gi
```

### Redis HA with Sentinel

```yaml
# Redis with Sentinel for failover
redis:
  sentinel:
    enabled: true
    quorum: 2

  master:
    persistence:
      enabled: true
      size: 10Gi

  replica:
    replicaCount: 2
    persistence:
      enabled: true
      size: 10Gi
```

## Cross-Region Data Replication

### Object Storage Replication

**S3 Cross-Region Replication:**

```yaml
# MinIO site-to-site replication
apiVersion: v1
kind: ConfigMap
metadata:
  name: minio-replication
data:
  config.json: |
    {
      "version": "1",
      "remote": {
        "us-west": {
          "endpoint": "https://minio.us-west-2.example.com",
          "credentials": {
            "accessKey": "ACCESS_KEY",
            "secretKey": "SECRET_KEY"
          }
        }
      }
    }
```

**Rclone-based Replication:**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: s3-replication
spec:
  schedule: "*/30 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: rclone
              image: rclone/rclone:1.65
              command:
                - rclone
                - sync
                - s3-primary:bucket
                - s3-replica:bucket
                - --config=/config/rclone.conf
              volumeMounts:
                - name: config
                  mountPath: /config
          restartPolicy: OnFailure
```

### Database Replication

**PostgreSQL Logical Replication:**

```sql
-- Primary database
CREATE PUBLICATION my_publication FOR ALL TABLES;

-- Replica database
CREATE SUBSCRIPTION my_subscription
CONNECTION 'host=primary.us-east-1 dbname=mydb user=replicator'
PUBLICATION my_publication;
```

**MySQL Binary Log Replication:**

```yaml
# Primary
mysql:
  configuration: |
    [mysqld]
    server-id=1
    log-bin=mysql-bin
    binlog-format=ROW
    gtid-mode=ON
    enforce-gtid-consistency=ON

# Replica
mysql:
  configuration: |
    [mysqld]
    server-id=2
    relay-log=mysql-relay
    log-slave-updates=ON
    read-only=ON
    gtid-mode=ON
```

## Disaster Recovery Procedures

### Backup Strategies

**PostgreSQL Backups:**

```yaml
# WAL-G for continuous archiving
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: wal-g
              image: wal-g/wal-g:latest
              command:
                - wal-g
                - backup-push
                - /var/lib/postgresql/data
              env:
                - name: WALG_S3_PREFIX
                  value: s3://backups/postgres
                - name: PGHOST
                  value: postgres
                - name: PGDATABASE
                  value: mydb
```

**Application Data Backups:**

```yaml
# Velero for Kubernetes resource backup
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
spec:
  schedule: "0 1 * * *"
  template:
    includedNamespaces:
      - production
    snapshotVolumes: true
    ttl: 720h  # 30 days
```

### Restore Procedures

**PostgreSQL Restore:**

```bash
# Restore from WAL-G backup
kubectl exec -it postgres-0 -- bash
wal-g backup-fetch /var/lib/postgresql/data LATEST

# Start PostgreSQL in recovery mode
cat > /var/lib/postgresql/data/recovery.signal <<EOF
restore_command = 'wal-g wal-fetch %f %p'
recovery_target_time = '2024-01-01 12:00:00'
EOF

pg_ctl start
```

**Velero Restore:**

```bash
# List backups
velero backup get

# Restore specific backup
velero restore create --from-backup daily-backup-20240101

# Restore to different namespace
velero restore create --from-backup daily-backup-20240101 \
  --namespace-mappings production:production-restore
```

### Failover Procedures

**Manual Failover Checklist:**

1. **Verify standby region readiness:**
   ```bash
   kubectl --context=us-west-2 get pods
   kubectl --context=us-west-2 exec postgres-0 -- pg_isready
   ```

2. **Stop primary region traffic:**
   ```bash
   kubectl --context=us-east-1 scale deploy/myapp --replicas=0
   ```

3. **Promote standby database:**
   ```bash
   kubectl --context=us-west-2 exec postgres-0 -- \
     psql -c "SELECT pg_promote();"
   ```

4. **Update DNS to standby region:**
   ```bash
   kubectl apply -f dns-failover.yaml
   ```

5. **Scale up standby region:**
   ```bash
   kubectl --context=us-west-2 scale deploy/myapp --replicas=3
   ```

**Automated Failover with ExternalDNS:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  annotations:
    external-dns.alpha.kubernetes.io/hostname: app.example.com
    external-dns.alpha.kubernetes.io/healthcheck-id: myapp-health
    external-dns.alpha.kubernetes.io/failover: "true"
    external-dns.alpha.kubernetes.io/set-identifier: us-east-1
spec:
  type: LoadBalancer
  selector:
    app: myapp
```

## Traffic Management

### Global Load Balancing

**AWS Global Accelerator:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-global
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
spec:
  type: LoadBalancer
  selector:
    app: myapp
```

**CloudFlare Load Balancing:**

```yaml
# Cloudflare Load Balancer
resource "cloudflare_load_balancer" "app" {
  zone_id = var.zone_id
  name    = "app.example.com"

  default_pool_ids = [
    cloudflare_load_balancer_pool.us_east.id,
    cloudflare_load_balancer_pool.eu_west.id,
  ]

  steering_policy = "geo"

  region_pools {
    region   = "WNAM"  # Western North America
    pool_ids = [cloudflare_load_balancer_pool.us_east.id]
  }

  region_pools {
    region   = "WEU"  # Western Europe
    pool_ids = [cloudflare_load_balancer_pool.eu_west.id]
  }
}
```

### Circuit Breakers

**Istio Circuit Breaking:**

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: myapp-circuit-breaker
spec:
  host: myapp
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        http2MaxRequests: 100
        maxRequestsPerConnection: 2
    outlierDetection:
      consecutiveErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
      minHealthPercent: 40
```

## Monitoring and Alerting

### HA-Specific Alerts

```yaml
# alerting-rules/ha-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ha-alerts
spec:
  groups:
    - name: high-availability.rules
      rules:
        - alert: PodDistributionUnbalanced
          expr: |
            count(kube_pod_info{namespace="production"}) by (zone) /
            count(kube_pod_info{namespace="production"}) < 0.33
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "Pods unevenly distributed across zones"

        - alert: DatabaseReplicationLag
          expr: |
            pg_replication_lag_seconds > 60
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Database replication lag exceeds 60s"

        - alert: BackupFailed
          expr: |
            time() - kube_job_status_completion_time{job_name=~".*backup.*"} > 86400
          for: 1h
          labels:
            severity: critical
          annotations:
            summary: "Backup not completed in last 24h"

        - alert: PDBViolation
          expr: |
            kube_poddisruptionbudget_status_current_healthy <
            kube_poddisruptionbudget_status_desired_healthy
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "PodDisruptionBudget violated"
```

### Health Checks

**Multi-layer Health Checks:**

```yaml
# Application health
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3

# Startup probe for slow-starting apps
startupProbe:
  httpGet:
    path: /health/startup
    port: 8080
  initialDelaySeconds: 0
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 30  # 5 minutes total
```

## Cost Optimization

### Resource Right-Sizing

```yaml
# Production (primary region)
resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 2000m
    memory: 4Gi

# DR (standby region) - reduced capacity
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 1Gi
```

### Spot Instances for DR

```yaml
# Use spot instances for standby region
nodeSelector:
  node.kubernetes.io/instance-type: spot

tolerations:
  - key: "spot"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```

## Testing HA Configurations

### Chaos Engineering

**Chaos Mesh Experiments:**

```yaml
# Pod failure test
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-failure
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces:
      - production
    labelSelectors:
      app: myapp
  scheduler:
    cron: "@every 2h"
```

**Network Partition Test:**

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-partition
spec:
  action: partition
  mode: all
  selector:
    namespaces:
      - production
  direction: both
  duration: "30s"
```

### DR Drill Checklist

- [ ] Verify backups are restorable
- [ ] Test database failover (< 5 min RTO)
- [ ] Validate DNS failover switches correctly
- [ ] Confirm application starts in DR region
- [ ] Check data consistency between regions
- [ ] Measure actual RTO/RPO
- [ ] Document lessons learned

## Best Practices

### DO:
- ✅ Test failover procedures quarterly
- ✅ Automate backup verification
- ✅ Monitor replication lag continuously
- ✅ Use PodDisruptionBudgets
- ✅ Document runbooks for failure scenarios
- ✅ Set realistic RTO/RPO targets

### DON'T:
- ❌ Trust backups without restore tests
- ❌ Ignore replication lag warnings
- ❌ Deploy to single zone in production
- ❌ Skip DR drills
- ❌ Forget to update DNS after failover
- ❌ Neglect cost of DR environment

## Related Documentation

- [Production Checklist](PRODUCTION_CHECKLIST.md)
- [GitOps Guide](GITOPS_GUIDE.md)
- [Alerting Rules](../alerting-rules/)
- [Chart Development Guide](CHART_DEVELOPMENT_GUIDE.md)
