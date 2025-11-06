# Development Guide

## Git Configuration

### Exclude gh-pages from Git Log

The `gh-pages` branch is an orphan branch used for GitHub Pages hosting and has no common history with `master`/`develop`. To keep your git log clean:

**One-time setup (permanent):**

```bash
# Delete local tracking of gh-pages
git branch -rd origin/gh-pages

# Prevent future fetches of gh-pages
git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
git config --add remote.origin.fetch "^refs/heads/gh-pages"
```

**Verify it works:**

```bash
git fetch
git log --oneline --graph --all --decorate | head -20
# gh-pages commits should not appear
```

**Alternative: Temporary exclusion (for one-time use):**

```bash
# Just view without gh-pages
git log --oneline --graph --branches --remotes --exclude=refs/remotes/*/gh-pages
```

## Chart Development Workflow

### Making Changes

1. Work on `develop` branch
2. Update `Chart.yaml` version (semantic versioning)
3. Test locally with `make -f Makefile.{chart}.mk lint`
4. Commit changes
5. Merge to `master` when ready for release

### Release Process

Charts are automatically released when merged to `master`:

1. **Trigger**: Push to `master` branch with changes in `charts/**`
2. **Actions**:
   - GitHub Release created (via chart-releaser)
   - GitHub Pages updated (`gh-pages` branch)
   - OCI registry push (GHCR)
3. **Requirements**: Chart version must be incremented in `Chart.yaml`

### Concurrency Control

The release workflow uses `cancel-in-progress: true` to prevent multiple simultaneous releases:

- New pushes cancel in-progress releases
- Only the latest push will complete
- Prevents resource waste and duplicate releases

## Testing

```bash
# Lint all charts
make lint

# Test specific chart
make -f Makefile.keycloak.mk template
make -f Makefile.keycloak.mk install

# Local testing with Kind
make kind-create
helm install test-release ./charts/keycloak -f values-example.yaml
make kind-delete
```
