# WordPress Helm Chart - Comprehensive Upgrade Guide

## Table of Contents

1. [Overview](#overview)
2. [Upgrade Philosophy](#upgrade-philosophy)
3. [Upgrade Strategies](#upgrade-strategies)
4. [Pre-Upgrade Preparation](#pre-upgrade-preparation)
5. [Upgrade Procedures](#upgrade-procedures)
6. [Post-Upgrade Validation](#post-upgrade-validation)
7. [Rollback Procedures](#rollback-procedures)
8. [Version-Specific Notes](#version-specific-notes)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)

---

## Overview

### Purpose

This guide provides comprehensive upgrade procedures for WordPress deployments using the Helm chart. Upgrading WordPress involves multiple components: WordPress core, plugins, themes, PHP runtime, and database schema.

### Upgrade Scope

**What Gets Upgraded**:
- **WordPress Core**: Security patches, new features (e.g., 6.7 → 6.8)
- **PHP Runtime**: Apache/PHP version in container image (e.g., PHP 8.1 → 8.3)
- **Database Schema**: Automatic schema migrations on WordPress startup
- **Plugins**: Security updates, new features (manual or automated)
- **Themes**: Security updates, new features (manual or automated)
- **Helm Chart**: Chart improvements, new features (e.g., 0.3.0 → 0.4.0)

**What Doesn't Change**:
- **MySQL Database**: External database (upgrade separately)
- **User Content**: Posts, pages, media files (preserved)
- **Configuration**: wp-config.php, Kubernetes ConfigMaps/Secrets (preserved)

### Upgrade Complexity Matrix

| Upgrade Type | Downtime | Complexity | Risk Level | Testing Required |
|--------------|----------|------------|------------|------------------|
| **Patch (6.7.1 → 6.7.2)** | None | Low | Low | Basic |
| **Minor (6.7.x → 6.8.x)** | None | Medium | Medium | Moderate |
| **Major (5.x → 6.x)** | 10-15 min | High | High | Extensive |
| **PHP Version (8.1 → 8.3)** | 10-15 min | Medium | Medium | Plugin compatibility |
| **Chart Only (0.3.0 → 0.4.0)** | None | Low | Low | Basic |

---

## Upgrade Philosophy

### Core Principles

1. **Always Backup First**: WordPress content and database are irreplaceable
2. **Test in Staging**: Never upgrade production without testing first
3. **Database Schema Auto-Migration**: WordPress automatically upgrades database on first run
4. **No Schema Downgrades**: Rollback requires database restore (WordPress doesn't support schema downgrades)
5. **Plugin Compatibility**: Check plugin compatibility before major WordPress upgrades
6. **Zero-Downtime (Minor)**: Rolling upgrades for patch/minor versions
7. **Brief Downtime (Major)**: Maintenance mode for major versions

### WordPress Upgrade Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                  WordPress Upgrade Workflow                      │
├─────────────────────────────────────────────────────────────────┤
│ 1. Pre-Upgrade                                                   │
│    ├─ Backup WordPress content (uploads, plugins, themes)       │
│    ├─ Backup MySQL database (full dump)                         │
│    ├─ Backup Kubernetes configuration                           │
│    ├─ Review WordPress release notes                            │
│    ├─ Check plugin/theme compatibility                          │
│    └─ Create PVC snapshot (optional)                            │
├─────────────────────────────────────────────────────────────────┤
│ 2. Upgrade Execution                                             │
│    ├─ Strategy 1: Rolling Upgrade (zero-downtime)               │
│    ├─ Strategy 2: Maintenance Mode (brief downtime)             │
│    ├─ Strategy 3: Blue-Green Deployment (zero-downtime)         │
│    └─ Strategy 4: Database Migration (MySQL upgrade)            │
├─────────────────────────────────────────────────────────────────┤
│ 3. Post-Upgrade                                                  │
│    ├─ WordPress automatically migrates database schema          │
│    ├─ Verify WordPress version                                  │
│    ├─ Test database integrity                                   │
│    ├─ Login to admin panel                                      │
│    ├─ Verify posts, pages, media load correctly                 │
│    ├─ Test plugin functionality                                 │
│    ├─ Test theme rendering                                      │
│    └─ Monitor logs for errors                                   │
├─────────────────────────────────────────────────────────────────┤
│ 4. Rollback (If Needed)                                          │
│    ├─ Helm rollback (for chart-only changes)                    │
│    └─ Full database restore (for WordPress core upgrades)       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Upgrade Strategies

### Strategy 1: Rolling Upgrade (Zero-Downtime)

**Best For**: Patch and minor WordPress versions (6.7.1 → 6.7.2 or 6.7.x → 6.8.x)

**Downtime**: None

**Complexity**: Low

**How It Works**:
1. Helm updates Deployment with new image tag
2. Kubernetes creates new pod with new WordPress version
3. New pod runs database migration (if needed)
4. Old pod is terminated after new pod is ready
5. No user-facing downtime

**Procedure**:

```bash
# 1. Pre-upgrade backup
make -f make/ops/wordpress.mk wp-full-backup

# 2. Pre-upgrade validation
make -f make/ops/wordpress.mk wp-pre-upgrade-check

# 3. Upgrade via Helm (rolling update)
helm upgrade wordpress scripton-charts/wordpress \
  --namespace wordpress \
  --set image.tag=6.8-apache \
  --reuse-values

# 4. Monitor rollout
kubectl rollout status deployment/wordpress -n wordpress

# 5. Post-upgrade validation
make -f make/ops/wordpress.mk wp-post-upgrade-check
```

**Advantages**:
- ✅ Zero downtime
- ✅ Automatic rollback on failure
- ✅ Fast upgrade (2-5 minutes)

**Limitations**:
- ❌ Not suitable for major PHP version changes (may have incompatibility during rollout)
- ❌ Not suitable for major database schema changes

---

### Strategy 2: Maintenance Mode Upgrade (Brief Downtime)

**Best For**: Major WordPress versions (5.x → 6.x) or PHP version upgrades (8.1 → 8.3)

**Downtime**: 10-15 minutes

**Complexity**: Medium

**How It Works**:
1. Enable WordPress maintenance mode
2. Scale down deployment to 0 replicas
3. Perform database backup
4. Upgrade Helm chart with new image tag
5. New pod starts and runs database migration
6. Disable maintenance mode
7. Service resumes

**Procedure**:

```bash
# 1. Pre-upgrade backup
make -f make/ops/wordpress.mk wp-full-backup

# 2. Enable WordPress maintenance mode
make -f make/ops/wordpress.mk wp-enable-maintenance

# 3. Scale down deployment
kubectl scale deployment wordpress -n wordpress --replicas=0

# 4. Verify no pods running
kubectl get pods -n wordpress

# 5. Upgrade via Helm
helm upgrade wordpress scripton-charts/wordpress \
  --namespace wordpress \
  --set image.tag=6.8-apache \
  --reuse-values

# 6. Scale up deployment
kubectl scale deployment wordpress -n wordpress --replicas=1

# 7. Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=wordpress -n wordpress --timeout=300s

# 8. Disable maintenance mode
make -f make/ops/wordpress.mk wp-disable-maintenance

# 9. Post-upgrade validation
make -f make/ops/wordpress.mk wp-post-upgrade-check
```

**Advantages**:
- ✅ Safe for major version upgrades
- ✅ Controlled database migration
- ✅ No partial state issues

**Limitations**:
- ❌ 10-15 minutes downtime
- ❌ Requires maintenance window

---

### Strategy 3: Blue-Green Deployment (Zero-Downtime)

**Best For**: Production with strict zero-downtime requirement for major upgrades

**Downtime**: None (instant cutover)

**Complexity**: High

**How It Works**:
1. Deploy new WordPress version in parallel namespace (green)
2. Point green to same MySQL database (shared state)
3. Test green environment thoroughly
4. Switch Ingress to point to green
5. Decommission old environment (blue)

**Procedure**:

```bash
# ==========================
# Phase 1: Deploy Green Environment
# ==========================

# 1. Pre-upgrade backup
make -f make/ops/wordpress.mk wp-full-backup

# 2. Create green namespace
kubectl create namespace wordpress-green

# 3. Copy secrets to green namespace
kubectl get secret wordpress-secret -n wordpress -o yaml | \
  sed 's/namespace: wordpress/namespace: wordpress-green/' | \
  kubectl apply -f -

# 4. Deploy WordPress to green namespace (new version)
helm install wordpress-green scripton-charts/wordpress \
  --namespace wordpress-green \
  --set image.tag=6.8-apache \
  --set wordpress.siteUrl="https://wordpress.example.com" \
  --set mysql.external.enabled=true \
  --set mysql.external.host="mysql-service.default.svc.cluster.local" \
  --set mysql.external.database="wordpress" \
  --set persistence.content.existingClaim=""  # Create new PVC for green

# ==========================
# Phase 2: Sync Content from Blue to Green
# ==========================

# 5. Copy WordPress content from blue to green
make -f make/ops/wordpress.mk wp-sync-content-to-green

# ==========================
# Phase 3: Test Green Environment
# ==========================

# 6. Port-forward to green for testing
kubectl port-forward -n wordpress-green svc/wordpress 8081:80

# 7. Test WordPress functionality (browser: http://localhost:8081)
# - Login to admin panel
# - Verify posts and pages load
# - Test media library
# - Test plugin functionality

# ==========================
# Phase 4: Cutover to Green
# ==========================

# 8. Update Ingress to point to green service
kubectl patch ingress wordpress -n wordpress -p '{"spec":{"rules":[{"host":"wordpress.example.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"wordpress-green","port":{"number":80}}}}]}}]}}'

# 9. Wait 5 minutes for DNS/cache propagation

# ==========================
# Phase 5: Decommission Blue
# ==========================

# 10. Scale down blue deployment
kubectl scale deployment wordpress -n wordpress --replicas=0

# 11. After 24 hours, delete blue namespace (if no issues)
# kubectl delete namespace wordpress

echo "Blue-Green upgrade completed successfully!"
```

**Advantages**:
- ✅ Zero downtime
- ✅ Instant cutover
- ✅ Easy rollback (switch Ingress back)

**Limitations**:
- ❌ High complexity
- ❌ Requires separate content PVC or content sync
- ❌ Shared database (both versions access same DB)

---

### Strategy 4: MySQL Database Upgrade

**Best For**: Upgrading MySQL database version (e.g., MySQL 5.7 → 8.0)

**Downtime**: 30 minutes - 2 hours (depending on database size)

**Complexity**: High

**How It Works**:
1. Backup MySQL database (mysqldump)
2. Deploy new MySQL version
3. Restore database to new MySQL
4. Update WordPress to point to new MySQL
5. Test connectivity and data integrity

**Procedure**:

```bash
# ==========================
# Phase 1: Backup Current Database
# ==========================

# 1. Backup MySQL database
make -f make/ops/wordpress.mk wp-backup-mysql

# ==========================
# Phase 2: Deploy New MySQL Version
# ==========================

# 2. Deploy new MySQL 8.0 instance (separate namespace or service)
helm install mysql80 scripton-charts/mysql \
  --namespace database \
  --set image.tag=8.0 \
  --set mysql.rootPassword="STRONG_PASSWORD" \
  --set mysql.database="wordpress" \
  --set mysql.username="wordpress" \
  --set mysql.password="WORDPRESS_DB_PASSWORD"

# 3. Wait for MySQL to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mysql -n database --timeout=300s

# ==========================
# Phase 3: Restore Database to New MySQL
# ==========================

# 4. Copy backup to new MySQL pod
export MYSQL80_POD=$(kubectl get pods -n database -l app.kubernetes.io/name=mysql -o jsonpath='{.items[0].metadata.name}')
kubectl cp backups/wordpress-mysql-20250108-143022.sql.gz database/$MYSQL80_POD:/tmp/

# 5. Restore database
kubectl exec -n database $MYSQL80_POD -- bash -c \
  "zcat /tmp/wordpress-mysql-20250108-143022.sql.gz | mysql -u root -pSTRONG_PASSWORD wordpress"

# ==========================
# Phase 4: Update WordPress Configuration
# ==========================

# 6. Update WordPress Secret with new MySQL host
kubectl patch secret wordpress-secret -n wordpress -p \
  '{"data":{"WORDPRESS_DB_HOST":"'$(echo -n "mysql80-service.database.svc.cluster.local" | base64)'"}}'

# 7. Restart WordPress to pick up new database
kubectl rollout restart deployment/wordpress -n wordpress

# ==========================
# Phase 5: Validation
# ==========================

# 8. Verify database connectivity
make -f make/ops/wordpress.mk wp-db-check

# 9. Verify WordPress functionality
make -f make/ops/wordpress.mk wp-post-upgrade-check

echo "MySQL upgrade completed successfully!"
```

**Advantages**:
- ✅ Clean database upgrade
- ✅ Old MySQL instance preserved for rollback

**Limitations**:
- ❌ Long downtime (30 min - 2 hours)
- ❌ High complexity
- ❌ Requires double storage temporarily

---

## Pre-Upgrade Preparation

### Pre-Upgrade Checklist

**CRITICAL**: Complete ALL items before upgrading.

```bash
# ========================================
# 1. Review WordPress Release Notes
# ========================================
# Check: https://wordpress.org/news/category/releases/

# Key areas to review:
# - Breaking changes
# - Deprecated functions
# - PHP version requirements
# - Plugin compatibility issues
# - Security fixes

# ========================================
# 2. Check Current Versions
# ========================================

# Check WordPress version
make -f make/ops/wordpress.mk wp-version

# Check PHP version
make -f make/ops/wordpress.mk wp-php-version

# Check MySQL version
make -f make/ops/wordpress.mk wp-db-version

# ========================================
# 3. Full Backup (CRITICAL!)
# ========================================

# Full backup (content + database + config)
make -f make/ops/wordpress.mk wp-full-backup

# Verify backups exist
ls -lh backups/wordpress-*

# ========================================
# 4. PVC Snapshot (Optional but Recommended)
# ========================================

# Create PVC snapshot for fast rollback
make -f make/ops/wordpress.mk wp-snapshot-content

# ========================================
# 5. Check Plugin/Theme Compatibility
# ========================================

# List installed plugins
make -f make/ops/wordpress.mk wp-list-plugins

# Check plugin compatibility at: https://wordpress.org/plugins/
# - Search for each plugin
# - Check "Tested up to" version

# List installed themes
make -f make/ops/wordpress.mk wp-list-themes

# ========================================
# 6. Test Database Integrity
# ========================================

# Check database integrity
make -f make/ops/wordpress.mk wp-db-check

# Check database size
make -f make/ops/wordpress.mk wp-db-size

# ========================================
# 7. Export Current Helm Values
# ========================================

# Export current Helm values for reference
helm get values wordpress -n wordpress > backups/helm-values-pre-upgrade.yaml

# ========================================
# 8. Check Disk Space
# ========================================

# Check WordPress content disk usage
make -f make/ops/wordpress.mk wp-disk-usage

# Ensure sufficient space for upgrade (recommendation: 20% free)

# ========================================
# 9. Plan Maintenance Window (If Needed)
# ========================================

# For major upgrades or MySQL upgrades:
# - Schedule 1-2 hour maintenance window
# - Notify users via WordPress admin notice
# - Enable maintenance mode

# ========================================
# 10. Staging Environment Test (Recommended)
# ========================================

# If possible, test upgrade in staging environment first
# - Deploy WordPress to staging namespace
# - Restore production backup
# - Perform upgrade
# - Test functionality
# - Document any issues
```

---

## Upgrade Procedures

### Procedure 1: Patch Upgrade (e.g., 6.7.1 → 6.7.2)

**Downtime**: None

**Estimated Time**: 5 minutes

**Steps**:

```bash
# 1. Pre-upgrade check
make -f make/ops/wordpress.mk wp-pre-upgrade-check

# 2. Backup (quick - incremental backup sufficient)
make -f make/ops/wordpress.mk wp-backup-content-incremental
make -f make/ops/wordpress.mk wp-backup-mysql

# 3. Upgrade WordPress image tag
helm upgrade wordpress scripton-charts/wordpress \
  --namespace wordpress \
  --set image.tag=6.7.2-apache \
  --reuse-values

# 4. Monitor rollout
kubectl rollout status deployment/wordpress -n wordpress

# 5. Post-upgrade validation
make -f make/ops/wordpress.mk wp-post-upgrade-check

# Expected output:
# ✅ WordPress version: 6.7.2
# ✅ Database integrity: OK
# ✅ Admin login: OK
```

---

### Procedure 2: Minor Upgrade (e.g., 6.7.x → 6.8.x)

**Downtime**: None (rolling) or 10-15 minutes (maintenance mode recommended)

**Estimated Time**: 15-30 minutes

**Steps**:

```bash
# 1. Pre-upgrade checklist
make -f make/ops/wordpress.mk wp-pre-upgrade-check

# 2. Full backup
make -f make/ops/wordpress.mk wp-full-backup

# 3. Review WordPress 6.8 release notes
# Check: https://wordpress.org/news/

# 4. Check plugin compatibility
make -f make/ops/wordpress.mk wp-list-plugins
# Verify each plugin supports WordPress 6.8

# 5. Enable maintenance mode (recommended for minor upgrades)
make -f make/ops/wordpress.mk wp-enable-maintenance

# 6. Scale down deployment
kubectl scale deployment wordpress -n wordpress --replicas=0

# 7. Upgrade WordPress image tag
helm upgrade wordpress scripton-charts/wordpress \
  --namespace wordpress \
  --set image.tag=6.8-apache \
  --reuse-values

# 8. Scale up deployment
kubectl scale deployment wordpress -n wordpress --replicas=1

# 9. Wait for pod to be ready (database migration happens here)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=wordpress -n wordpress --timeout=300s

# 10. Disable maintenance mode
make -f make/ops/wordpress.mk wp-disable-maintenance

# 11. Post-upgrade validation
make -f make/ops/wordpress.mk wp-post-upgrade-check

# 12. Manual verification
# - Login to admin panel
# - Verify posts/pages load correctly
# - Test media library
# - Check plugin functionality
# - Test theme rendering

# Expected output:
# ✅ WordPress version: 6.8.0
# ✅ Database version: 57155 (updated)
# ✅ Database integrity: OK
# ✅ Admin login: OK
# ✅ Plugins: 15 active, 0 errors
```

---

### Procedure 3: Major Upgrade (e.g., 5.x → 6.x)

**Downtime**: 10-15 minutes (maintenance mode required)

**Estimated Time**: 30-60 minutes

**Steps**:

```bash
# ==========================
# Phase 1: Pre-Upgrade Preparation
# ==========================

# 1. Review WordPress 6.x release notes THOROUGHLY
# Check: https://wordpress.org/news/
# Pay attention to:
# - Breaking changes
# - Deprecated functions
# - Plugin compatibility issues

# 2. Pre-upgrade validation
make -f make/ops/wordpress.mk wp-pre-upgrade-check

# 3. Full backup (CRITICAL!)
make -f make/ops/wordpress.mk wp-full-backup

# 4. Create PVC snapshot for fast rollback
make -f make/ops/wordpress.mk wp-snapshot-content

# 5. Export current Helm values
helm get values wordpress -n wordpress > backups/helm-values-pre-major-upgrade.yaml

# 6. Check plugin compatibility for WordPress 6.x
make -f make/ops/wordpress.mk wp-list-plugins
# Verify EACH plugin supports WordPress 6.x
# Disable any incompatible plugins before upgrade

# 7. Check theme compatibility
make -f make/ops/wordpress.mk wp-list-themes

# ==========================
# Phase 2: Staging Test (HIGHLY RECOMMENDED)
# ==========================

# 8. Deploy WordPress to staging namespace
kubectl create namespace wordpress-staging

# 9. Restore production backup to staging
# (See Backup Guide for restore procedures)

# 10. Perform upgrade in staging
# (Repeat steps below in wordpress-staging namespace)

# 11. Test staging thoroughly
# - Login to admin panel
# - Verify all posts/pages
# - Test all plugins
# - Test theme rendering
# - Check for PHP errors/warnings

# ==========================
# Phase 3: Production Upgrade
# ==========================

# 12. Enable maintenance mode
make -f make/ops/wordpress.mk wp-enable-maintenance

# 13. Scale down deployment
kubectl scale deployment wordpress -n wordpress --replicas=0

# 14. Verify no pods running
kubectl get pods -n wordpress

# 15. Upgrade WordPress image tag to 6.x
helm upgrade wordpress scripton-charts/wordpress \
  --namespace wordpress \
  --set image.tag=6.8-apache \
  --reuse-values

# 16. Scale up deployment
kubectl scale deployment wordpress -n wordpress --replicas=1

# 17. Wait for pod to be ready (database migration takes longer for major upgrades)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=wordpress -n wordpress --timeout=600s

# 18. Monitor logs during database migration
kubectl logs -f -l app.kubernetes.io/name=wordpress -n wordpress

# Look for:
# - "WordPress database update required"
# - "WordPress database update completed"

# ==========================
# Phase 4: Post-Upgrade Validation
# ==========================

# 19. Post-upgrade validation
make -f make/ops/wordpress.mk wp-post-upgrade-check

# 20. Manual verification (CRITICAL!)
# - Login to admin panel
# - Verify database upgrade completed
# - Check all posts and pages load
# - Test media library (upload new image)
# - Test each plugin functionality
# - Test theme rendering on multiple pages
# - Check for PHP errors in logs

# 21. Disable maintenance mode (only if validation passes!)
make -f make/ops/wordpress.mk wp-disable-maintenance

# 22. Monitor logs for 1 hour
kubectl logs -f -l app.kubernetes.io/name=wordpress -n wordpress

# Look for:
# - PHP errors
# - Database errors
# - Plugin errors

# ==========================
# Phase 5: Cleanup
# ==========================

# 23. Delete staging namespace (after 24 hours, if production stable)
# kubectl delete namespace wordpress-staging

echo "Major upgrade completed successfully!"
```

---

### Procedure 4: PHP Version Upgrade (e.g., PHP 8.1 → PHP 8.3)

**Downtime**: 10-15 minutes

**Estimated Time**: 30 minutes

**Steps**:

```bash
# 1. Pre-upgrade validation
make -f make/ops/wordpress.mk wp-pre-upgrade-check

# 2. Check current PHP version
make -f make/ops/wordpress.mk wp-php-version

# 3. Review PHP 8.3 changelog
# Check: https://www.php.net/releases/8.3/

# 4. Check plugin compatibility with PHP 8.3
# Many older plugins may not support PHP 8.3

# 5. Full backup
make -f make/ops/wordpress.mk wp-full-backup

# 6. Enable maintenance mode
make -f make/ops/wordpress.mk wp-enable-maintenance

# 7. Scale down deployment
kubectl scale deployment wordpress -n wordpress --replicas=0

# 8. Upgrade WordPress image tag (includes PHP 8.3)
helm upgrade wordpress scripton-charts/wordpress \
  --namespace wordpress \
  --set image.tag=6.8-apache-php8.3 \
  --reuse-values

# 9. Scale up deployment
kubectl scale deployment wordpress -n wordpress --replicas=1

# 10. Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=wordpress -n wordpress --timeout=300s

# 11. Check PHP version
make -f make/ops/wordpress.mk wp-php-version

# 12. Monitor logs for PHP errors
kubectl logs -f -l app.kubernetes.io/name=wordpress -n wordpress

# Look for:
# - Deprecated function warnings
# - Fatal errors
# - Plugin compatibility issues

# 13. Disable maintenance mode (if no errors)
make -f make/ops/wordpress.mk wp-disable-maintenance

# 14. Post-upgrade validation
make -f make/ops/wordpress.mk wp-post-upgrade-check
```

---

### Procedure 5: Chart-Only Upgrade (e.g., 0.3.0 → 0.4.0)

**Downtime**: None

**Estimated Time**: 5 minutes

**Steps**:

```bash
# 1. Review chart changelog
# Check: https://github.com/scriptonbasestar-container/sb-helm-charts/releases

# 2. Update Helm repo
helm repo update scripton-charts

# 3. Check new chart version
helm search repo scripton-charts/wordpress

# 4. Backup current Helm values
helm get values wordpress -n wordpress > backups/helm-values-pre-chart-upgrade.yaml

# 5. Upgrade chart
helm upgrade wordpress scripton-charts/wordpress \
  --namespace wordpress \
  --version 0.4.0 \
  --reuse-values

# 6. Monitor rollout
kubectl rollout status deployment/wordpress -n wordpress

# 7. Verify WordPress version unchanged (chart upgrade only)
make -f make/ops/wordpress.mk wp-version

# 8. Verify WordPress functionality
make -f make/ops/wordpress.mk wp-post-upgrade-check
```

---

## Post-Upgrade Validation

### Post-Upgrade Checklist

**CRITICAL**: Complete ALL validation steps before declaring upgrade successful.

```bash
# ========================================
# 1. Pod Health
# ========================================

# Verify WordPress pod is running
kubectl get pods -n wordpress -l app.kubernetes.io/name=wordpress

# Check pod events for errors
kubectl describe pod -n wordpress -l app.kubernetes.io/name=wordpress

# ========================================
# 2. WordPress Version
# ========================================

# Verify WordPress version
make -f make/ops/wordpress.mk wp-version

# Expected output:
# WordPress Version: 6.8.0

# ========================================
# 3. PHP Version
# ========================================

# Verify PHP version
make -f make/ops/wordpress.mk wp-php-version

# Expected output:
# PHP Version: 8.3.x

# ========================================
# 4. Database Integrity
# ========================================

# Check database version (should be updated)
make -f make/ops/wordpress.mk wp-db-version

# Check database integrity
make -f make/ops/wordpress.mk wp-db-check

# Check database table count (should match pre-upgrade)
make -f make/ops/wordpress.mk wp-db-table-count

# ========================================
# 5. WordPress Core Functionality
# ========================================

# Port-forward to WordPress
make -f make/ops/wordpress.mk wp-port-forward

# Open browser: http://localhost:8080

# Manual tests:
# ✅ Login to /wp-admin
# ✅ Verify dashboard loads
# ✅ Check "At a Glance" widget (post count, page count)
# ✅ Navigate to Posts → All Posts (verify posts load)
# ✅ Navigate to Pages → All Pages (verify pages load)
# ✅ Navigate to Media → Library (verify media files load)
# ✅ Upload a new image (test upload functionality)
# ✅ Create a new test post
# ✅ Preview and publish test post
# ✅ View published post on frontend

# ========================================
# 6. Plugin Functionality
# ========================================

# List active plugins
make -f make/ops/wordpress.mk wp-list-plugins

# Manual tests:
# ✅ Navigate to Plugins → Installed Plugins
# ✅ Verify all plugins are active (no errors)
# ✅ Test key plugin functionality:
#    - WooCommerce: View products, test checkout
#    - Contact Form 7: View forms, test submission
#    - Yoast SEO: Check SEO analysis on post
#    - Jetpack: Verify stats, security features

# ========================================
# 7. Theme Functionality
# ========================================

# List active theme
make -f make/ops/wordpress.mk wp-list-themes

# Manual tests:
# ✅ View frontend homepage
# ✅ Navigate to different pages
# ✅ Check responsive design (mobile, tablet)
# ✅ Verify images load correctly
# ✅ Test navigation menu
# ✅ Test search functionality
# ✅ Test comments (if enabled)

# ========================================
# 8. Permalink and Rewrite Rules
# ========================================

# Test permalink structure
# Navigate to Settings → Permalinks
# Click "Save Changes" to flush rewrite rules

# Test:
# ✅ Post permalinks work
# ✅ Page permalinks work
# ✅ Category/tag archives work
# ✅ Custom post types work (if any)

# ========================================
# 9. Performance
# ========================================

# Check pod resource usage
make -f make/ops/wordpress.mk wp-top

# Check disk usage
make -f make/ops/wordpress.mk wp-disk-usage

# Check response time
curl -o /dev/null -s -w 'Total: %{time_total}s\n' http://localhost:8080

# ========================================
# 10. Logs and Errors
# ========================================

# Check WordPress logs for errors
kubectl logs -l app.kubernetes.io/name=wordpress -n wordpress --tail=100

# Look for:
# ❌ PHP Fatal errors
# ❌ PHP Warnings
# ❌ Database errors
# ❌ Plugin errors
# ✅ "WordPress database upgrade completed" (for major upgrades)

# ========================================
# 11. Monitoring
# ========================================

# Continue monitoring for 1-24 hours:
# - Check logs hourly for first 6 hours
# - Monitor user feedback
# - Check error rates in monitoring system (if available)
```

---

## Rollback Procedures

### Rollback Decision Matrix

| Scenario | Rollback Method | Downtime | Data Loss Risk |
|----------|----------------|----------|----------------|
| **Chart upgrade only** | Helm rollback | None | None |
| **WordPress patch/minor** | Helm rollback + DB restore | 10-15 min | Data since upgrade |
| **WordPress major** | Helm rollback + DB restore | 10-15 min | Data since upgrade |
| **PHP upgrade** | Helm rollback | None | None |
| **Database corruption** | PVC snapshot restore | 5-10 min | Data since snapshot |

---

### Rollback 1: Helm Rollback (Chart-Only Changes)

**When to Use**: Chart upgrade with no WordPress core or database changes

**Downtime**: None

**Steps**:

```bash
# 1. Check Helm revision history
helm history wordpress -n wordpress

# 2. Rollback to previous revision
helm rollback wordpress -n wordpress

# 3. Monitor rollout
kubectl rollout status deployment/wordpress -n wordpress

# 4. Verify WordPress version (should be unchanged)
make -f make/ops/wordpress.mk wp-version

# 5. Verify functionality
make -f make/ops/wordpress.mk wp-post-upgrade-check
```

---

### Rollback 2: Full Rollback (WordPress Core Upgrade)

**When to Use**: WordPress core upgrade with database migration

**Downtime**: 10-15 minutes

**Data Loss**: Any content created/modified since upgrade will be lost

**Steps**:

```bash
# ==========================
# Phase 1: Enable Maintenance Mode
# ==========================

# 1. Enable maintenance mode
make -f make/ops/wordpress.mk wp-enable-maintenance

# 2. Scale down deployment
kubectl scale deployment wordpress -n wordpress --replicas=0

# ==========================
# Phase 2: Restore Database
# ==========================

# 3. Restore MySQL database from pre-upgrade backup
make -f make/ops/wordpress.mk wp-restore-mysql \
  BACKUP_FILE=backups/wordpress-mysql-20250108-143022.sql.gz

# ==========================
# Phase 3: Restore WordPress Content (If Needed)
# ==========================

# 4. Restore WordPress content from pre-upgrade backup (if needed)
make -f make/ops/wordpress.mk wp-restore-content \
  BACKUP_FILE=backups/wordpress-content-full-20250108-143022.tar.gz

# ==========================
# Phase 4: Rollback Helm Release
# ==========================

# 5. Check Helm history
helm history wordpress -n wordpress

# 6. Rollback Helm release to previous revision
helm rollback wordpress -n wordpress

# ==========================
# Phase 5: Scale Up and Verify
# ==========================

# 7. Scale up deployment
kubectl scale deployment wordpress -n wordpress --replicas=1

# 8. Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=wordpress -n wordpress --timeout=300s

# 9. Verify WordPress version (should be rolled back)
make -f make/ops/wordpress.mk wp-version

# 10. Verify database version (should be rolled back)
make -f make/ops/wordpress.mk wp-db-version

# 11. Verify database integrity
make -f make/ops/wordpress.mk wp-db-check

# ==========================
# Phase 6: Disable Maintenance Mode
# ==========================

# 12. Disable maintenance mode
make -f make/ops/wordpress.mk wp-disable-maintenance

# 13. Post-rollback validation
make -f make/ops/wordpress.mk wp-post-upgrade-check

echo "Rollback completed successfully!"
```

---

### Rollback 3: PVC Snapshot Restore (Fastest)

**When to Use**: Complete WordPress content loss or corruption

**Downtime**: 5-10 minutes

**Data Loss**: Any content created/modified since snapshot

**Steps**:

```bash
# 1. Enable maintenance mode
make -f make/ops/wordpress.mk wp-enable-maintenance

# 2. Scale down deployment
kubectl scale deployment wordpress -n wordpress --replicas=0

# 3. Restore from PVC snapshot
make -f make/ops/wordpress.mk wp-restore-from-snapshot \
  SNAPSHOT_NAME=wordpress-content-snapshot-20250108-143022

# 4. Scale up deployment
kubectl scale deployment wordpress -n wordpress --replicas=1

# 5. Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=wordpress -n wordpress --timeout=300s

# 6. Disable maintenance mode
make -f make/ops/wordpress.mk wp-disable-maintenance

# 7. Verify functionality
make -f make/ops/wordpress.mk wp-post-upgrade-check
```

---

## Version-Specific Notes

### WordPress 6.7 → 6.8

**Release Date**: 2024-12-11

**Key Changes**:
- **Performance**: Improved block editor performance
- **Accessibility**: Enhanced keyboard navigation
- **Security**: Security fixes for XSS vulnerabilities
- **Database**: Schema version updated to 57155

**Compatibility**:
- **PHP**: Minimum PHP 7.4, recommended PHP 8.1+
- **MySQL**: Minimum MySQL 5.7 or MariaDB 10.3

**Plugin Issues**:
- **Classic Editor**: Compatible
- **WooCommerce**: Tested up to 6.8
- **Jetpack**: Compatible
- **Contact Form 7**: Compatible

**Upgrade Notes**:
- No breaking changes
- Rolling upgrade recommended
- Database migration is automatic and fast (< 1 minute)

---

### WordPress 6.6 → 6.7

**Release Date**: 2024-11-12

**Key Changes**:
- **Twenty Twenty-Five Theme**: New default theme
- **Block Editor**: Improved block patterns
- **Performance**: Faster block rendering

**Compatibility**:
- **PHP**: Minimum PHP 7.4
- **MySQL**: Minimum MySQL 5.7

**Upgrade Notes**:
- No breaking changes
- Rolling upgrade recommended

---

### WordPress 6.x → 7.x (Future)

**Estimated Release**: TBD

**Expected Changes**:
- **Block-First Architecture**: Full-site editing by default
- **Gutenberg**: Mature block editor
- **PHP**: Minimum PHP 8.0 expected

**Upgrade Notes**:
- Major version - test thoroughly in staging
- Maintenance mode recommended
- Check all plugins for compatibility

---

## Troubleshooting

### Issue 1: Database Migration Fails

**Symptoms**:
```
WordPress database error: [Table 'wp_posts' doesn't exist]
```

**Diagnosis**:

```bash
# Check WordPress logs
kubectl logs -l app.kubernetes.io/name=wordpress -n wordpress

# Check database connectivity
make -f make/ops/wordpress.mk wp-db-check

# Check database tables
make -f make/ops/wordpress.mk wp-db-list-tables
```

**Solution**:

```bash
# Option 1: Restore database from backup
make -f make/ops/wordpress.mk wp-restore-mysql BACKUP_FILE=backups/wordpress-mysql-20250108-143022.sql.gz

# Option 2: Manually trigger database upgrade
make -f make/ops/wordpress.mk wp-db-upgrade
```

---

### Issue 2: Plugins Broken After Upgrade

**Symptoms**:
- Plugin errors in WordPress admin
- PHP fatal errors in logs

**Diagnosis**:

```bash
# Check WordPress logs for PHP errors
kubectl logs -l app.kubernetes.io/name=wordpress -n wordpress | grep -i "fatal error"

# List active plugins
make -f make/ops/wordpress.mk wp-list-plugins
```

**Solution**:

```bash
# Option 1: Disable problematic plugin via wp-cli
make -f make/ops/wordpress.mk wp-plugin-deactivate PLUGIN=problematic-plugin

# Option 2: Update plugin to latest version
make -f make/ops/wordpress.mk wp-plugin-update PLUGIN=problematic-plugin

# Option 3: Rollback WordPress
# (See Rollback Procedures section)
```

---

### Issue 3: White Screen of Death (WSOD)

**Symptoms**:
- Blank white screen on WordPress admin or frontend
- No error messages visible

**Diagnosis**:

```bash
# Check WordPress logs
kubectl logs -l app.kubernetes.io/name=wordpress -n wordpress

# Look for PHP fatal errors, memory exhaustion, or database errors
```

**Solution**:

```bash
# Option 1: Increase PHP memory limit
kubectl set env deployment/wordpress -n wordpress WP_MEMORY_LIMIT=256M

# Option 2: Enable WordPress debug mode
kubectl set env deployment/wordpress -n wordpress WP_DEBUG=true

# Restart pod
kubectl rollout restart deployment/wordpress -n wordpress

# Check logs for detailed error
kubectl logs -f -l app.kubernetes.io/name=wordpress -n wordpress

# Option 3: Restore from backup (if error persists)
make -f make/ops/wordpress.mk wp-full-recovery \
  CONTENT_BACKUP=backups/wordpress-content-full-20250108-143022.tar.gz \
  MYSQL_BACKUP=backups/wordpress-mysql-20250108-143022.sql.gz
```

---

### Issue 4: Pod CrashLoopBackOff After Upgrade

**Symptoms**:
```
kubectl get pods -n wordpress
wordpress-xxxx   0/1   CrashLoopBackOff
```

**Diagnosis**:

```bash
# Check pod logs
kubectl logs -l app.kubernetes.io/name=wordpress -n wordpress

# Check pod events
kubectl describe pod -l app.kubernetes.io/name=wordpress -n wordpress

# Common causes:
# - Database connection failure
# - PHP fatal error
# - File permission issues
```

**Solution**:

```bash
# Check database connectivity
make -f make/ops/wordpress.mk wp-db-check

# Rollback to previous version
helm rollback wordpress -n wordpress

# If rollback fails, restore from backup
make -f make/ops/wordpress.mk wp-full-recovery \
  CONTENT_BACKUP=backups/wordpress-content-full-20250108-143022.tar.gz \
  MYSQL_BACKUP=backups/wordpress-mysql-20250108-143022.sql.gz
```

---

## Best Practices

### 1. Always Backup First

**CRITICAL**: Never upgrade without a complete, tested backup.

```bash
# Before EVERY upgrade:
make -f make/ops/wordpress.mk wp-full-backup

# Verify backups exist
ls -lh backups/

# Test restore in staging (quarterly)
```

---

### 2. Test in Staging

**Best Practice**: Always test upgrades in staging environment first.

```bash
# Create staging namespace
kubectl create namespace wordpress-staging

# Restore production backup to staging
# (See Backup Guide)

# Perform upgrade in staging
# Test thoroughly

# Only then proceed with production upgrade
```

---

### 3. Read Release Notes

**Best Practice**: Always review WordPress release notes before upgrading.

**Key Resources**:
- https://wordpress.org/news/category/releases/
- https://make.wordpress.org/core/
- https://codex.wordpress.org/Upgrading_WordPress

**What to Look For**:
- Breaking changes
- Deprecated functions (affects custom plugins/themes)
- PHP version requirements
- MySQL version requirements
- Known plugin compatibility issues

---

### 4. Monitor After Upgrade

**Best Practice**: Don't declare success immediately after upgrade.

**Monitoring Schedule**:
- **First hour**: Check logs every 15 minutes
- **First 6 hours**: Check logs hourly
- **First 24 hours**: Check logs every 4 hours
- **First week**: Monitor daily

**What to Monitor**:
- WordPress error logs
- PHP errors/warnings
- Database errors
- User feedback
- Site performance

---

### 5. Incremental Upgrades

**Best Practice**: Don't skip multiple major versions.

**Recommended**:
- ✅ 6.6 → 6.7 → 6.8 (incremental)
- ❌ 6.6 → 6.8 (skip 6.7)

**Why**:
- Database migrations are cumulative
- Plugin compatibility easier to track
- Easier to identify which version caused issues

---

### 6. Maintenance Window Planning

**Best Practice**: Plan maintenance windows for major upgrades.

**Factors to Consider**:
- **Time of Day**: Low-traffic hours (2-4 AM for most sites)
- **Day of Week**: Tuesday or Wednesday (avoid weekends, Mondays, Fridays)
- **Duration**: 1-2 hours for major upgrades
- **Notification**: Notify users 7 days in advance, 24 hours reminder, 1 hour warning

**Example Notification**:

```text
Subject: Scheduled WordPress Maintenance - [Date] [Time]

Dear Users,

We will be performing a scheduled maintenance to upgrade WordPress on:

Date: January 15, 2025
Time: 2:00 AM - 4:00 AM EST
Expected Downtime: 15 minutes

What to expect:
- Brief site unavailability (10-15 minutes)
- Improved security and performance
- No data loss

Thank you for your patience.
```

---

## Summary

### Quick Reference

| Task | Command | Estimated Time |
|------|---------|----------------|
| **Pre-Upgrade Check** | `make -f make/ops/wordpress.mk wp-pre-upgrade-check` | 5 min |
| **Full Backup** | `make -f make/ops/wordpress.mk wp-full-backup` | 10-30 min |
| **Snapshot** | `make -f make/ops/wordpress.mk wp-snapshot-content` | 2 min |
| **Enable Maintenance** | `make -f make/ops/wordpress.mk wp-enable-maintenance` | 1 min |
| **Disable Maintenance** | `make -f make/ops/wordpress.mk wp-disable-maintenance` | 1 min |
| **Helm Upgrade** | `helm upgrade wordpress scripton-charts/wordpress --set image.tag=6.8-apache` | 5 min |
| **Post-Upgrade Check** | `make -f make/ops/wordpress.mk wp-post-upgrade-check` | 5 min |
| **Helm Rollback** | `helm rollback wordpress -n wordpress` | 5 min |
| **Full Rollback** | `make -f make/ops/wordpress.mk wp-full-recovery ...` | 30 min |

### Upgrade Strategy Decision Tree

```
Is it a patch upgrade (6.7.1 → 6.7.2)?
├─ Yes → Strategy 1: Rolling Upgrade (zero-downtime)
└─ No → Is it a minor upgrade (6.7.x → 6.8.x)?
    ├─ Yes → Strategy 1 or 2: Rolling or Maintenance Mode
    └─ No → Is it a major upgrade (5.x → 6.x)?
        ├─ Yes → Strategy 2: Maintenance Mode (test in staging first!)
        └─ No → Is it a PHP upgrade (8.1 → 8.3)?
            ├─ Yes → Strategy 2: Maintenance Mode
            └─ No → Is it a database migration (MySQL 5.7 → 8.0)?
                ├─ Yes → Strategy 4: Database Migration
                └─ No → Chart-only upgrade → Procedure 5
```

---

**Related Documentation**:
- [WordPress Backup Guide](wordpress-backup-guide.md)
- [WordPress Chart README](../charts/wordpress/README.md)
- [Makefile Commands](MAKEFILE_COMMANDS.md)

**Last Updated**: 2025-12-08
