# GitHub Pages Setup Guide

## Overview

This guide explains how to enable GitHub Pages for the sb-helm-charts repository to publish Helm charts via `https://scriptonbasestar-containers.github.io/sb-helm-charts`.

## Prerequisites

**Current Status:**

- ✅ gh-pages branch exists and contains index.yaml
- ✅ Chart Releaser workflow is active (`.github/workflows/release.yaml`)
- ✅ 16 charts are packaged and released
- ❌ GitHub Pages is not enabled (returns 403 Forbidden)

**Required:**

- Repository admin/owner access
- Chart Releaser GitHub Action running successfully

## Enabling GitHub Pages

### Step 1: Access Repository Settings

1. Navigate to your repository:
   ```
   https://github.com/ScriptonBasestar-containers/sb-helm-charts
   ```

2. Click on **Settings** (top menu)

3. In the left sidebar, scroll down to **Pages** under "Code and automation"

### Step 2: Configure Pages Source

In the GitHub Pages settings:

1. **Source Section:**
   - Select: **Deploy from a branch**

2. **Branch Selection:**
   - Branch: **gh-pages**
   - Folder: **/ (root)**

3. Click **Save**

### Step 3: Wait for Deployment

1. GitHub will start building and deploying your site
2. This typically takes 5-10 minutes
3. You'll see a notification: "Your site is ready to be published at..."

### Step 4: Verify Deployment

Once the deployment is complete, verify the setup:

```bash
# Check if index.yaml is accessible
curl -I https://scriptonbasestar-containers.github.io/sb-helm-charts/index.yaml

# Expected output:
# HTTP/2 200
# content-type: application/yaml
```

## Testing Helm Repository

After GitHub Pages is active, test the Helm repository:

```bash
# Add the repository
helm repo add scripton-charts https://scriptonbasestar-containers.github.io/sb-helm-charts

# Update repository index
helm repo update

# Search for charts
helm search repo scripton-charts

# Expected output: List of 16 charts
```

## Troubleshooting

### Issue: 403 Forbidden

**Symptoms:**

```bash
curl https://scriptonbasestar-containers.github.io/sb-helm-charts/index.yaml
# Output: Access denied
```

**Solutions:**

1. Verify GitHub Pages is enabled in Settings
2. Check that gh-pages branch exists: `git ls-remote --heads origin gh-pages`
3. Ensure Pages source is set to "gh-pages" branch, "/" folder
4. Wait 5-10 minutes after enabling for DNS propagation

### Issue: 404 Not Found

**Symptoms:**

- Site accessible but index.yaml returns 404

**Solutions:**

1. Check gh-pages branch content:
   ```bash
   git ls-tree gh-pages
   # Should show: index.yaml
   ```

2. Verify Chart Releaser workflow ran successfully:
   - Check: https://github.com/ScriptonBasestar-containers/sb-helm-charts/actions
   - Look for successful "Release Charts" workflow runs

3. Manually trigger Chart Releaser:
   - Push a change to master branch in `charts/` directory

### Issue: Old Chart Versions

**Symptoms:**

- Helm search shows outdated chart versions

**Solutions:**

```bash
# Force repository update
helm repo update

# Clear Helm cache
rm -rf ~/.cache/helm/repository/*
helm repo update
```

## Artifact Hub Integration

Once GitHub Pages is active, you can publish to Artifact Hub:

### Prerequisites

- ✅ GitHub Pages enabled and accessible
- ✅ `artifacthub-repo.yml` in repository root
- ✅ Chart READMEs contain Artifact Hub badges

### Publishing Steps

1. **Create Artifact Hub Account:**
   - Visit: https://artifacthub.io/
   - Sign in with GitHub

2. **Add Repository:**
   - Click "Add Repository"
   - Repository Type: **Helm charts**
   - URL: `https://scriptonbasestar-containers.github.io/sb-helm-charts`
   - Branch: `master` (for artifacthub-repo.yml)
   - Click "Add"

3. **Verify Synchronization:**
   - Wait 5-10 minutes for initial sync
   - Check: https://artifacthub.io/packages/search?org=scriptonbasestar
   - All 16 charts should appear

4. **Monitor:**
   - Artifact Hub automatically syncs every few hours
   - Security scans run on all 16 container images
   - Download statistics are tracked

## Maintenance

### Updating Charts

When you release new chart versions:

1. Charts are automatically packaged by Chart Releaser workflow
2. gh-pages branch is automatically updated
3. index.yaml is regenerated
4. GitHub Pages deploys changes automatically
5. Artifact Hub syncs within hours

No manual intervention required!

### Monitoring

Check GitHub Pages status:

```bash
# Via GitHub API
curl -s https://api.github.com/repos/ScriptonBasestar-containers/sb-helm-charts/pages | jq .

# Expected output:
# {
#   "url": "https://scriptonbasestar-containers.github.io/sb-helm-charts",
#   "status": "built",
#   "html_url": "https://scriptonbasestar-containers.github.io/sb-helm-charts",
#   ...
# }
```

## Benefits

Once GitHub Pages is enabled:

- ✅ **Public Helm Repository:** Anyone can `helm repo add` your charts
- ✅ **Automatic Updates:** Chart Releaser handles packaging and indexing
- ✅ **Artifact Hub Ready:** Enable discovery on https://artifacthub.io
- ✅ **Version History:** All chart versions remain accessible
- ✅ **Zero Cost:** Free hosting via GitHub Pages
- ✅ **High Availability:** GitHub's CDN infrastructure

## Related Documentation

- [Chart Releaser Workflow](.github/workflows/release.yaml)
- [Artifact Hub Repository Metadata](../artifacthub-repo.yml)
- [Artifact Hub Dashboard](ARTIFACTHUB_DASHBOARD.md)
- [Chart Catalog](CHARTS.md)

## Support

If you encounter issues:

1. Check workflow logs: https://github.com/ScriptonBasestar-containers/sb-helm-charts/actions
2. Verify gh-pages branch: `git ls-remote --heads origin gh-pages`
3. Review Pages settings in repository Settings > Pages
4. Wait 10-15 minutes after enabling for full propagation

---

**Next Steps:** After enabling GitHub Pages, proceed to [Artifact Hub Dashboard](ARTIFACTHUB_DASHBOARD.md) for publishing instructions.
