# Keycloak Backup & Recovery Guide

Comprehensive guide for backing up and restoring Keycloak realms and database.

## Table of Contents

- [Overview](#overview)
- [Backup Strategy](#backup-strategy)
- [Backup Procedures](#backup-procedures)
- [Recovery Procedures](#recovery-procedures)
- [Automation](#automation)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Backup Components

Keycloak backup consists of two critical components:

1. **Realm Exports**
   - Keycloak configuration (clients, roles, users, themes)
   - Exported via Keycloak's built-in export command
   - Stored as JSON files

2. **PostgreSQL Database**
   - All Keycloak data including sessions, events
   - Backed up via `pg_dump`
   - Stored as SQL dump files

### Why Both?

- **Realm exports**: Fast, selective recovery (specific realms)
- **Database dumps**: Complete state recovery, including sessions and audit logs
- **Combined**: Maximum data safety and flexibility

---

## Backup Strategy

### Recommended Backup Schedule

| Environment | Realm Export | Database Dump | Retention |
|-------------|--------------|---------------|-----------|
| **Production** | Daily (2 AM) | Daily (2 AM) | 30 days |
| **Staging** | Weekly | Weekly | 14 days |
| **Development** | On-demand | On-demand | 7 days |

### Storage Locations

```
tmp/keycloak-backups/
├── 20251127-020000/          # Realm exports (timestamp)
│   ├── master-realm.json
│   ├── app-realm.json
│   └── users-realm.json
├── db/                        # Database dumps
│   ├── keycloak-db-20251127-020000.sql
│   └── keycloak-db-20251126-020000.sql
└── migration/                 # Single realm migrations
    └── master-realm-20251127-120000.json
```

---

## Backup Procedures

### 1. Backup All Realms

**Export all realms from Keycloak:**

```bash
make -f make/ops/keycloak.mk kc-backup-all-realms
```

**What it does:**
1. Executes `/opt/keycloak/bin/kc.sh export --dir=/tmp/backup` in Keycloak pod
2. Copies backup files to local `tmp/keycloak-backups/<timestamp>/`
3. Includes all realms, clients, roles, and users

**Expected output:**
```
Backing up all Keycloak realms...
Backup completed: tmp/keycloak-backups/20251127-143022
```

### 2. Backup PostgreSQL Database

**Create a database dump:**

```bash
make -f make/ops/keycloak.mk kc-db-backup
```

**What it does:**
1. Connects to PostgreSQL pod
2. Executes `pg_dump keycloak` database
3. Saves to `tmp/keycloak-backups/db/keycloak-db-<timestamp>.sql`

**Expected output:**
```
Creating PostgreSQL backup for Keycloak database...
Database backup saved to tmp/keycloak-backups/db/keycloak-db-20251127-143045.sql
```

**Prerequisites:**
- PostgreSQL pod running in same namespace
- Pod labeled with `app.kubernetes.io/name=postgresql`
- PostgreSQL credentials available

### 3. Verify Backup Integrity

**Validate backup files:**

```bash
make -f make/ops/keycloak.mk kc-backup-verify DIR=tmp/keycloak-backups/20251127-143022
```

**What it checks:**
1. Directory exists and contains files
2. JSON syntax validation for realm files
3. File count and structure

**Expected output:**
```
Verifying backup integrity: tmp/keycloak-backups/20251127-143022
Checking for realm JSON files...
Found 3 realm files
Validating JSON syntax...
Backup verification completed
```

### 4. Export Single Realm (Migration)

**Export a specific realm for migration:**

```bash
make -f make/ops/keycloak.mk kc-realm-migrate REALM=master
```

**Use cases:**
- Cross-cluster migration
- Realm versioning
- Selective restore

**Expected output:**
```
Exporting realm 'master' for migration...
Realm exported to tmp/keycloak-backups/migration/master-realm-20251127-143100.json
```

---

## Recovery Procedures

### 1. Restore All Realms

**Restore from realm backup:**

```bash
make -f make/ops/keycloak.mk kc-backup-restore FILE=tmp/keycloak-backups/20251127-143022
```

**What it does:**
1. Copies backup directory to Keycloak pod
2. Executes `/opt/keycloak/bin/kc.sh import --dir=/tmp/restore`
3. Imports all realm configurations

**Warning:** This will overwrite existing realms with same names.

**Steps to verify:**
```bash
# List realms after restore
make -f make/ops/keycloak.mk kc-list-realms

# Check specific realm
make -f make/ops/keycloak.mk kc-export-realm REALM=master
```

### 2. Restore Database

**Restore PostgreSQL database:**

```bash
make -f make/ops/keycloak.mk kc-db-restore FILE=tmp/keycloak-backups/db/keycloak-db-20251127-143045.sql
```

**Critical steps:**

1. **Scale down Keycloak** (prevents connection conflicts):
   ```bash
   kubectl scale statefulset keycloak --replicas=0
   ```

2. **Restore database:**
   ```bash
   make -f make/ops/keycloak.mk kc-db-restore FILE=tmp/keycloak-backups/db/keycloak-db-20251127-143045.sql
   ```

3. **Scale up Keycloak:**
   ```bash
   kubectl scale statefulset keycloak --replicas=3
   ```

4. **Verify health:**
   ```bash
   make -f make/ops/keycloak.mk kc-post-upgrade-check
   ```

**Warning:** This will completely replace the Keycloak database. All current data will be lost.

### 3. Import Single Realm

**Import a specific realm:**

```bash
make -f make/ops/keycloak.mk kc-import-realm FILE=tmp/keycloak-backups/migration/master-realm-20251127-143100.json
```

**Use cases:**
- Add new realm from backup
- Restore single realm without full restore
- Cross-environment migration

---

## Automation

### Scheduled Backups (Cron Example)

**Option 1: System cron (external to Kubernetes):**

```bash
# /etc/cron.d/keycloak-backup
0 2 * * * /usr/bin/make -f /path/to/make/ops/keycloak.mk kc-backup-all-realms && \
          /usr/bin/make -f /path/to/make/ops/keycloak.mk kc-db-backup
```

**Option 2: Kubernetes CronJob (if desired):**

Create `backup-cronjob.yaml`:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: keycloak-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: keycloak
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              # Realm backup
              kubectl exec keycloak-0 -- /opt/keycloak/bin/kc.sh export --dir=/backup --users=realm_file

              # Copy to PVC or external storage
              kubectl cp keycloak-0:/backup /mnt/backups/$(date +%Y%m%d-%H%M%S)
          restartPolicy: OnFailure
```

### Backup Retention

**Automatic cleanup script:**

```bash
#!/bin/bash
# cleanup-old-backups.sh

BACKUP_DIR="tmp/keycloak-backups"
RETENTION_DAYS=30

find "$BACKUP_DIR" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;
find "$BACKUP_DIR/db" -type f -mtime +$RETENTION_DAYS -delete

echo "Cleaned up backups older than $RETENTION_DAYS days"
```

---

## Best Practices

### Before Production Deployment

1. **Test restore procedure** in staging
2. **Verify backup integrity** weekly
3. **Document recovery time** (RTO)
4. **Test with real data volume**

### Backup Checklist

- [ ] Realm export completed successfully
- [ ] Database dump created
- [ ] Backup integrity verified
- [ ] Backup stored in safe location
- [ ] Old backups cleaned up (retention policy)
- [ ] Restore tested monthly (production)

### Security Considerations

1. **Encrypt backups at rest:**
   ```bash
   # Encrypt backup with GPG
   gpg --symmetric --cipher-algo AES256 backup.sql
   ```

2. **Restrict access:**
   ```bash
   chmod 600 tmp/keycloak-backups/*.sql
   ```

3. **Store off-site:**
   - S3/MinIO with encryption
   - Separate Kubernetes cluster
   - Physical backup location

### Monitoring

**Track backup success:**
```bash
#!/bin/bash
# check-backup-status.sh

BACKUP_DIR="tmp/keycloak-backups"
LATEST_BACKUP=$(ls -t "$BACKUP_DIR" | head -1)
BACKUP_AGE=$(find "$BACKUP_DIR/$LATEST_BACKUP" -mtime +1 | wc -l)

if [ "$BACKUP_AGE" -gt 0 ]; then
  echo "❌ Backup is older than 24 hours!"
  exit 1
else
  echo "✅ Backup is up to date"
fi
```

---

## Troubleshooting

### Backup fails with "permission denied"

**Cause:** Insufficient permissions in Keycloak pod

**Solution:**
```bash
# Check pod security context
kubectl get pod keycloak-0 -o jsonpath='{.spec.securityContext}'

# Ensure write access to /tmp
kubectl exec keycloak-0 -- touch /tmp/test-write
```

### Database backup fails: "PostgreSQL pod not found"

**Cause:** PostgreSQL pod not labeled correctly

**Solution:**
```bash
# Verify PostgreSQL pod label
kubectl get pod -l app.kubernetes.io/name=postgresql

# If missing, add label:
kubectl label pod postgres-0 app.kubernetes.io/name=postgresql
```

### Restore fails: "realm already exists"

**Cause:** Keycloak import doesn't overwrite by default

**Solution:**
```bash
# Delete existing realm first (via Admin Console or CLI)
make -f make/ops/keycloak.mk kc-cli CMD="delete realms/master"

# Then restore
make -f make/ops/keycloak.mk kc-backup-restore FILE=...
```

### JSON validation errors

**Cause:** Corrupted backup file

**Solution:**
```bash
# Validate JSON manually
jq empty tmp/keycloak-backups/<timestamp>/master-realm.json

# If corrupted, use previous backup
ls -lt tmp/keycloak-backups/
```

### Database restore hangs

**Cause:** Active connections to database

**Solution:**
```bash
# 1. Scale down Keycloak completely
kubectl scale statefulset keycloak --replicas=0

# 2. Wait for all pods to terminate
kubectl get pods -w

# 3. Terminate active connections in PostgreSQL
kubectl exec postgres-0 -- psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='keycloak';"

# 4. Restore database
make -f make/ops/keycloak.mk kc-db-restore FILE=...

# 5. Scale back up
kubectl scale statefulset keycloak --replicas=3
```

---

## Recovery Time Objectives (RTO)

### Estimated Recovery Times

| Scenario | RTO | Steps |
|----------|-----|-------|
| **Single realm restore** | 5-10 minutes | Import realm JSON |
| **All realms restore** | 10-20 minutes | Import all realms |
| **Full database restore** | 20-40 minutes | Scale down + restore + scale up |
| **Complete disaster recovery** | 1-2 hours | Redeploy + restore realms + restore DB |

### Disaster Recovery Plan

**Complete Keycloak failure:**

1. **Redeploy Keycloak chart** (10-15 min)
   ```bash
   helm install keycloak charts/keycloak -f values-prod-master-replica.yaml
   ```

2. **Restore database** (20-30 min)
   ```bash
   make -f make/ops/keycloak.mk kc-db-restore FILE=<latest-backup>
   ```

3. **Verify health** (5-10 min)
   ```bash
   make -f make/ops/keycloak.mk kc-post-upgrade-check
   ```

4. **Test authentication** (5-10 min)
   - Login to Admin Console
   - Test OIDC/SAML flows
   - Verify user access

**Total RTO: 40-65 minutes**

---

## Resources

- [Keycloak Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/current/backup.html)
- [Chart README](../charts/keycloak/README.md)

---

**Last Updated:** 2025-11-27
