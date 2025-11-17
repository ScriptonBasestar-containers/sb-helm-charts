# Troubleshooting Guide

> **Last Updated**: 2025-11-17
> **Applies To**: All charts in sb-helm-charts repository

This guide helps diagnose and resolve common issues when deploying Helm charts from this repository.

---

## Table of Contents

1. [Database Connection Issues](#database-connection-issues)
2. [Persistence and Storage Issues](#persistence-and-storage-issues)
3. [Networking Issues](#networking-issues)
4. [Resource Issues](#resource-issues)
5. [Image Pull Issues](#image-pull-issues)
6. [Configuration Issues](#configuration-issues)
7. [Health Probe Issues](#health-probe-issues)
8. [Chart-Specific Issues](#chart-specific-issues)
9. [Debugging Commands](#debugging-commands)

---

## Database Connection Issues

### Symptom: Pod crashes with "Connection refused" or "Unknown host"

**Causes:**
- External database service not reachable
- Wrong hostname/port in values.yaml
- Database not in same cluster/namespace
- Network policy blocking connection

**Solutions:**

1. **Verify database is running:**
   ```bash
   kubectl get pods -l app=postgresql
   kubectl logs postgresql-0
   ```

2. **Test database connectivity from pod:**
   ```bash
   # For PostgreSQL
   kubectl exec -it <pod-name> -- bash
   pg_isready -h $DB_HOST -p $DB_PORT -U $DB_USER

   # For MySQL
   kubectl exec -it <pod-name> -- bash
   mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p
   ```

3. **Check DNS resolution:**
   ```bash
   kubectl exec -it <pod-name> -- nslookup <db-host>
   ```

4. **Verify values.yaml configuration:**
   ```yaml
   postgresql:
     external:
       enabled: true
       host: "postgres-service.default.svc.cluster.local"  # Must be FQDN
       port: 5432
       database: "myapp"
       username: "myuser"
       password: "mypassword"  # Must not be empty
   ```

5. **Check InitContainer logs:**
   ```bash
   kubectl logs <pod-name> -c wait-for-db
   ```

### Symptom: SSL/TLS connection errors (Keycloak)

**Causes:**
- SSL mode mismatch
- Certificate not found
- Certificate secret not mounted

**Solutions:**

1. **For `require` mode (no certificate validation):**
   ```yaml
   postgresql:
     external:
       ssl:
         enabled: true
         mode: "require"  # No certificate needed
   ```

2. **For `verify-ca` or `verify-full` mode:**
   ```yaml
   postgresql:
     external:
       ssl:
         enabled: true
         mode: "verify-ca"
         certificateSecret: "postgres-ca-cert"
         rootCertKey: "ca.crt"
   ```

3. **Verify certificate secret exists:**
   ```bash
   kubectl get secret postgres-ca-cert
   kubectl describe secret postgres-ca-cert
   ```

4. **Check certificate is mounted:**
   ```bash
   kubectl exec -it <pod-name> -- ls -la /etc/keycloak/certs/
   ```

### Symptom: "Database password is required"

**Cause:** Password field is empty in values.yaml

**Solution:**
```yaml
postgresql:
  external:
    password: "actual-password-here"  # MUST NOT be empty string
```

Or use existing secret:
```yaml
postgresql:
  external:
    existingSecret: "my-db-secret"
    existingSecretPasswordKey: "password"
```

---

## Persistence and Storage Issues

### Symptom: PVC stuck in "Pending" state

**Causes:**
- No storage class available
- Storage class doesn't exist
- Insufficient storage on node
- No dynamic provisioner

**Solutions:**

1. **Check PVC status:**
   ```bash
   kubectl get pvc
   kubectl describe pvc <pvc-name>
   ```

2. **List available storage classes:**
   ```bash
   kubectl get storageclass
   ```

3. **Specify storage class in values.yaml:**
   ```yaml
   persistence:
     enabled: true
     storageClass: "standard"  # or "local-path", "csi-hostpath-sc", etc.
     size: "10Gi"
   ```

4. **For local testing (minikube/kind):**
   ```bash
   # Minikube
   minikube addons enable storage-provisioner

   # Kind - install local-path-provisioner
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
   ```

### Symptom: Permission denied when writing to volume

**Causes:**
- Pod runs as non-root user
- Volume ownership mismatch
- ReadOnly filesystem

**Solutions:**

1. **Check pod security context:**
   ```bash
   kubectl get pod <pod-name> -o yaml | grep -A 10 securityContext
   ```

2. **Check volume permissions:**
   ```bash
   kubectl exec -it <pod-name> -- ls -la /data
   kubectl exec -it <pod-name> -- id
   ```

3. **If using existingClaim, fix permissions manually:**
   ```bash
   # Create debug pod with root access
   kubectl run -it --rm debug --image=busybox --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' -- sh

   # Inside pod, fix permissions (adjust UID/GID as needed)
   chown -R 1000:1000 /data
   chmod -R 755 /data
   ```

4. **Use fsGroup in pod security context (if chart supports):**
   ```yaml
   podSecurityContext:
     fsGroup: 1000
   ```

### Symptom: existingClaim not working

**Cause:** Prior to Redis v0.3.1, existingClaim support was broken

**Solution:**

1. **Update to latest chart version:**
   ```bash
   helm repo update
   helm upgrade <release> scripton-charts/redis --version ">=0.3.1"
   ```

2. **Verify PVC exists and is available:**
   ```bash
   kubectl get pvc <existing-claim-name>
   ```

3. **Ensure PVC access mode matches:**
   ```yaml
   persistence:
     enabled: true
     existingClaim: "my-existing-pvc"
     accessMode: ReadWriteOnce  # Must match PVC access mode
   ```

---

## Networking Issues

### Symptom: Ingress returns 404 or "Backend not found"

**Causes:**
- Ingress controller not installed
- Service name mismatch
- Wrong port configuration
- Ingress class not set

**Solutions:**

1. **Verify ingress controller is running:**
   ```bash
   kubectl get pods -n ingress-nginx
   # or
   kubectl get pods -n traefik
   ```

2. **Check ingress resource:**
   ```bash
   kubectl get ingress
   kubectl describe ingress <ingress-name>
   ```

3. **Verify service is reachable:**
   ```bash
   kubectl get svc
   kubectl port-forward svc/<service-name> 8080:80
   # Test at http://localhost:8080
   ```

4. **Check ingress configuration in values.yaml:**
   ```yaml
   ingress:
     enabled: true
     className: "nginx"  # or "traefik"
     hosts:
       - host: myapp.example.com
         paths:
           - path: /
             pathType: Prefix
   ```

### Symptom: Service not accessible from outside cluster

**Causes:**
- Service type is ClusterIP (internal only)
- LoadBalancer not provisioned
- NodePort not opened on firewall

**Solutions:**

1. **Check service type:**
   ```bash
   kubectl get svc <service-name>
   ```

2. **For local testing, use port-forward:**
   ```bash
   kubectl port-forward svc/<service-name> 8080:80
   ```

3. **For external access, use NodePort:**
   ```yaml
   service:
     type: NodePort
     nodePort: 30080  # Optional: specific port
   ```

4. **For cloud environments, use LoadBalancer:**
   ```yaml
   service:
     type: LoadBalancer
   ```

### Symptom: DNS resolution not working

**Cause:** CoreDNS issues or wrong service naming

**Solutions:**

1. **Test DNS from pod:**
   ```bash
   kubectl exec -it <pod-name> -- nslookup kubernetes.default
   kubectl exec -it <pod-name> -- nslookup <service-name>
   ```

2. **Check CoreDNS pods:**
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   kubectl logs -n kube-system -l k8s-app=kube-dns
   ```

3. **Use FQDN for cross-namespace services:**
   ```
   <service-name>.<namespace>.svc.cluster.local
   ```

---

## Resource Issues

### Symptom: Pod in "OOMKilled" state

**Cause:** Container exceeded memory limit

**Solutions:**

1. **Check pod status:**
   ```bash
   kubectl get pods
   kubectl describe pod <pod-name>
   ```

2. **Increase memory limits:**
   ```yaml
   resources:
     limits:
       memory: "2Gi"  # Increase from default
     requests:
       memory: "512Mi"
   ```

3. **For specific charts, use scenario values:**
   ```bash
   # Use startup values instead of home values
   helm upgrade <release> scripton-charts/<chart> -f values-startup-single.yaml
   ```

4. **Monitor memory usage:**
   ```bash
   kubectl top pod <pod-name>
   ```

### Symptom: Pod stuck in "Pending" state

**Causes:**
- Insufficient CPU/memory on nodes
- Node selector/affinity not matching
- Taints preventing scheduling

**Solutions:**

1. **Check pod events:**
   ```bash
   kubectl describe pod <pod-name>
   # Look for: "Insufficient cpu" or "Insufficient memory"
   ```

2. **Check node resources:**
   ```bash
   kubectl top nodes
   kubectl describe nodes
   ```

3. **Adjust resource requests:**
   ```yaml
   resources:
     requests:
       cpu: "100m"     # Reduce from higher value
       memory: "128Mi"  # Reduce from higher value
   ```

4. **Remove node selector if present:**
   ```yaml
   nodeSelector: {}  # Remove restrictions
   ```

### Symptom: CPU throttling

**Cause:** CPU usage exceeds limits

**Solutions:**

1. **Check metrics:**
   ```bash
   kubectl top pod <pod-name>
   ```

2. **Increase CPU limits:**
   ```yaml
   resources:
     limits:
       cpu: "2000m"  # Increase from default
     requests:
       cpu: "500m"
   ```

---

## Image Pull Issues

### Symptom: "ImagePullBackOff" or "ErrImagePull"

**Causes:**
- Image doesn't exist
- Registry authentication required
- Network issues
- Rate limiting (Docker Hub)

**Solutions:**

1. **Check pod events:**
   ```bash
   kubectl describe pod <pod-name>
   ```

2. **Verify image exists:**
   ```bash
   # Try pulling locally
   docker pull <image:tag>
   ```

3. **For private registries, create image pull secret:**
   ```bash
   kubectl create secret docker-registry regcred \
     --docker-server=<registry> \
     --docker-username=<username> \
     --docker-password=<password> \
     --docker-email=<email>
   ```

4. **Configure in values.yaml:**
   ```yaml
   imagePullSecrets:
     - name: regcred
   ```

5. **For Docker Hub rate limiting, authenticate:**
   ```yaml
   imagePullSecrets:
     - name: dockerhub-creds
   ```

---

## Configuration Issues

### Symptom: Pod crashes with "invalid configuration"

**Causes:**
- Typo in configuration file
- Missing required values
- Wrong data type

**Solutions:**

1. **Check ConfigMap:**
   ```bash
   kubectl get configmap
   kubectl describe configmap <configmap-name>
   kubectl get configmap <configmap-name> -o yaml
   ```

2. **Validate configuration:**
   ```bash
   # For YAML files
   kubectl get configmap <name> -o yaml | yq eval

   # For JSON files
   kubectl get configmap <name> -o json | jq
   ```

3. **Check pod logs for specific errors:**
   ```bash
   kubectl logs <pod-name>
   kubectl logs <pod-name> --previous  # If pod is crash-looping
   ```

4. **Inspect mounted configuration:**
   ```bash
   kubectl exec -it <pod-name> -- cat /path/to/config/file
   ```

### Symptom: Environment variables not set

**Causes:**
- Secret/ConfigMap doesn't exist
- Wrong key name in valueFrom
- extraEnv override not working

**Solutions:**

1. **Check environment variables in pod:**
   ```bash
   kubectl exec -it <pod-name> -- env | grep <VAR_NAME>
   ```

2. **Verify secret/configmap exists:**
   ```bash
   kubectl get secret <secret-name>
   kubectl get configmap <configmap-name>
   ```

3. **Check secret key:**
   ```bash
   kubectl get secret <secret-name> -o jsonpath='{.data}'
   ```

4. **Remember: extraEnv cannot override chart-generated env vars**
   - First definition wins in Kubernetes
   - To override, disable auto-generation and use extraEnv

---

## Health Probe Issues

### Symptom: Pod keeps restarting

**Causes:**
- Liveness probe failing
- Application not starting in time
- Health endpoint not responding

**Solutions:**

1. **Check pod events:**
   ```bash
   kubectl describe pod <pod-name>
   # Look for: "Liveness probe failed" or "Readiness probe failed"
   ```

2. **Check probe configuration:**
   ```bash
   kubectl get pod <pod-name> -o yaml | grep -A 20 livenessProbe
   ```

3. **Increase probe delays:**
   ```yaml
   livenessProbe:
     initialDelaySeconds: 120  # Increase for slow-starting apps
     periodSeconds: 10
     timeoutSeconds: 5
     failureThreshold: 6
   ```

4. **Test probe manually:**
   ```bash
   # For HTTP probes
   kubectl exec -it <pod-name> -- curl -f http://localhost:8080/health

   # For exec probes
   kubectl exec -it <pod-name> -- redis-cli ping
   ```

5. **Temporarily disable probe for debugging:**
   ```yaml
   livenessProbe:
     enabled: false
   ```

### Symptom: Pod never becomes ready

**Cause:** Readiness probe failing

**Solutions:**

1. **Check readiness probe:**
   ```bash
   kubectl get pod <pod-name> -o yaml | grep -A 20 readinessProbe
   ```

2. **View pod logs:**
   ```bash
   kubectl logs <pod-name>
   ```

3. **Increase timeout and failure threshold:**
   ```yaml
   readinessProbe:
     initialDelaySeconds: 60
     periodSeconds: 10
     timeoutSeconds: 10  # Increase if slow
     failureThreshold: 6  # Increase for slow apps
   ```

---

## Chart-Specific Issues

### Redis

#### Issue: Master-replica replication not working

**Solutions:**

1. **Check replication status:**
   ```bash
   make -f make/ops/redis.mk redis-replication-info
   ```

2. **Verify replica configuration:**
   ```yaml
   redis:
     architecture: "replication"
     master:
       count: 1
     replica:
       count: 2
   ```

3. **Check pod connectivity:**
   ```bash
   kubectl exec -it redis-0 -- redis-cli ping
   kubectl exec -it redis-1 -- redis-cli info replication
   ```

#### Issue: Password not working

**Solution:** Ensure password is set in secret:
```bash
kubectl get secret redis -o jsonpath='{.data.redis-password}' | base64 -d
```

### Keycloak

#### Issue: Clustering not working

**Solutions:**

1. **Verify JGroups configuration:**
   ```bash
   make -f make/ops/keycloak.mk kc-cluster-status
   ```

2. **Check cache settings:**
   ```yaml
   keycloak:
     cache:
       type: "ispn"  # Infinispan
       stack: "kubernetes"
   ```

3. **Verify headless service:**
   ```bash
   kubectl get svc <release>-keycloak-headless
   ```

#### Issue: Health probes failing after upgrade

**Cause:** Keycloak 26.x moved health endpoints to port 9000

**Solution:** Update to chart v0.3.0+ which uses correct management port

### RabbitMQ

#### Issue: Clustering expected but only single instance deployed

**Cause:** Chart doesn't implement clustering

**Solution:** Use RabbitMQ Cluster Operator for production clustering
- See: https://github.com/rabbitmq/cluster-operator
- Or use Bitnami chart: https://github.com/bitnami/charts/tree/main/bitnami/rabbitmq

### Memcached

#### Issue: Data not persisting across restarts

**Cause:** Memcached is in-memory only (by design)

**Solution:** Use Redis if persistence is required

#### Issue: Load balancing not working

**Cause:** Requires client-side consistent hashing

**Solution:** Configure client library with consistent hashing and all memcached pod IPs

### WordPress

#### Issue: Permission errors on wp-content

**Solution:**

1. **Check volume ownership:**
   ```bash
   kubectl exec -it <pod-name> -- ls -la /var/www/html/wp-content
   ```

2. **Fix permissions:**
   ```bash
   kubectl exec -it <pod-name> -- chown -R www-data:www-data /var/www/html/wp-content
   ```

#### Issue: White screen after deployment

**Causes:**
- Database connection failed
- PHP memory limit too low
- Plugins incompatible

**Solutions:**

1. **Check logs:**
   ```bash
   kubectl logs <pod-name>
   kubectl exec -it <pod-name> -- tail -f /var/log/apache2/error.log
   ```

2. **Increase PHP memory:**
   ```yaml
   wordpress:
     phpMemoryLimit: "512M"
   ```

### Nextcloud

#### Issue: First-time setup fails

**Solution:**

1. **Use InitContainer to handle installation:**
   ```yaml
   nextcloud:
     autoInstall: true
     adminUser: "admin"
     adminPassword: "<secure-password>"
   ```

2. **Check installation logs:**
   ```bash
   kubectl logs <pod-name> -c nextcloud-install
   ```

### Paperless-ngx

#### Issue: OCR not working

**Solutions:**

1. **Verify Tika container is running:**
   ```bash
   kubectl get pods -l app.kubernetes.io/component=tika
   ```

2. **Check Paperless can reach Tika:**
   ```bash
   kubectl exec -it <paperless-pod> -- curl http://<tika-service>:9998
   ```

### Uptime Kuma

#### Issue: Database locked error

**Cause:** SQLite database accessed by multiple pods

**Solution:** Use only 1 replica for SQLite mode:
```yaml
replicaCount: 1
```

Or use MariaDB backend for multi-replica:
```yaml
uptimeKuma:
  database:
    type: "mariadb"
```

---

## Debugging Commands

### General Debugging

```bash
# Check all resources for release
kubectl get all -l app.kubernetes.io/instance=<release-name>

# View pod logs
kubectl logs <pod-name>
kubectl logs <pod-name> -f  # Follow
kubectl logs <pod-name> --previous  # Previous container (if crashed)
kubectl logs <pod-name> -c <container-name>  # Specific container

# Describe resources for events
kubectl describe pod <pod-name>
kubectl describe svc <service-name>
kubectl describe ingress <ingress-name>

# Open shell in pod
kubectl exec -it <pod-name> -- bash
kubectl exec -it <pod-name> -- sh  # If bash not available

# Copy files from pod
kubectl cp <pod-name>:/path/to/file ./local-file

# Port forward for testing
kubectl port-forward pod/<pod-name> 8080:80
kubectl port-forward svc/<service-name> 8080:80

# Check resource usage
kubectl top nodes
kubectl top pods

# View ConfigMaps and Secrets
kubectl get configmap <name> -o yaml
kubectl get secret <name> -o yaml
kubectl get secret <name> -o jsonpath='{.data.password}' | base64 -d
```

### Helm Debugging

```bash
# Check release status
helm list
helm status <release-name>

# View release values
helm get values <release-name>

# View all resources in release
helm get manifest <release-name>

# Test template rendering
helm template <release-name> scripton-charts/<chart> -f values.yaml

# Dry-run install
helm install <release-name> scripton-charts/<chart> -f values.yaml --dry-run --debug

# View release history
helm history <release-name>

# Rollback release
helm rollback <release-name> <revision>
```

### Network Debugging

```bash
# Test connectivity from pod
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash

# Inside debug pod:
curl http://<service-name>.<namespace>.svc.cluster.local
nslookup <service-name>
ping <pod-ip>
traceroute <service-ip>

# Check service endpoints
kubectl get endpoints <service-name>

# Test DNS
kubectl run -it --rm dnstest --image=busybox --restart=Never -- nslookup kubernetes.default
```

### Chart-Specific Make Commands

Most charts have operational Makefile commands for common tasks:

```bash
# List available commands for a chart
make -f make/ops/<chart>.mk help

# Common patterns:
make -f make/ops/<chart>.mk logs          # View logs
make -f make/ops/<chart>.mk shell         # Open shell
make -f make/ops/<chart>.mk restart       # Restart deployment
make -f make/ops/<chart>.mk port-forward  # Port forward to localhost

# Examples:
make -f make/ops/redis.mk redis-info
make -f make/ops/keycloak.mk kc-cluster-status
make -f make/ops/rabbitmq.mk rmq-status
make -f make/ops/memcached.mk mc-stats
```

---

## Getting Help

If you encounter issues not covered in this guide:

1. **Check chart README**: Each chart has specific documentation in `charts/<chart-name>/README.md`
2. **Review Analysis Report**: See `docs/05-chart-analysis-2025-11.md` for known limitations
3. **Check Testing Guide**: See `docs/TESTING_GUIDE.md` for testing procedures
4. **Search Issues**: https://github.com/ScriptonBasestar-containers/sb-helm-charts/issues
5. **Create Issue**: Provide chart name, version, error logs, and values.yaml (redact secrets!)

---

## Additional Resources

- [Chart Development Guide](CHART_DEVELOPMENT_GUIDE.md) - Development patterns and standards
- [Chart Version Policy](CHART_VERSION_POLICY.md) - Semantic versioning and release process
- [Testing Guide](TESTING_GUIDE.md) - Testing procedures for all deployment scenarios
- [Production Checklist](PRODUCTION_CHECKLIST.md) - Production readiness validation
- [Analysis Report](05-chart-analysis-2025-11.md) - Comprehensive analysis of all charts
- [Scenario Values Guide](SCENARIO_VALUES_GUIDE.md) - Deployment scenarios explained

---

**Document maintained by**: ScriptonBasestar Helm Charts
**Repository**: https://github.com/ScriptonBasestar-containers/sb-helm-charts
