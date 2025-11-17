# CI/CD Workflow Manual Application Guide

## 📌 Overview

**Status:** Workflow update is committed locally but cannot be pushed due to GitHub App permissions.

**Commit:** `1f0fabd` - ci: Add metadata validation and catalog verification to CI/CD

**Branch:** `claude/apply-cicd-workflow-01MYwP7mxgknDyzH5L66z3q2`

**File:** `.github/workflows/lint-test.yaml`

## ⚠️ Why Manual Application is Needed

GitHub Apps require the `workflows` permission to modify files in `.github/workflows/`. Since this permission is not granted, the changes must be applied manually.

## 📋 Changes Summary

The workflow update includes:

1. **Extended triggers** - Monitor metadata and script changes
2. **metadata-validation job** - Validate Chart.yaml keywords consistency
3. **Catalog verification** - Ensure docs/CHARTS.md is up-to-date
4. **Updated validation-summary** - Include metadata-validation results

## 🔧 Application Methods

### Method 1: GitHub Web UI (Recommended)

1. **Navigate to repository:**
   ```
   https://github.com/ScriptonBasestar-containers/sb-helm-charts
   ```

2. **Switch to branch:**
   ```
   claude/apply-cicd-workflow-01MYwP7mxgknDyzH5L66z3q2
   ```

3. **Edit workflow file:**
   - Open `.github/workflows/lint-test.yaml`
   - Click "Edit" button (pencil icon)

4. **Apply changes** (see detailed changes below)

5. **Commit directly to branch:**
   ```
   Commit message: ci: Add metadata validation and catalog verification to CI/CD
   ```

### Method 2: Local Git (With Workflow Permissions)

If you have a git client with proper permissions:

```bash
# Clone the repository
git clone https://github.com/ScriptonBasestar-containers/sb-helm-charts.git
cd sb-helm-charts

# Fetch the branch
git fetch origin claude/apply-cicd-workflow-01MYwP7mxgknDyzH5L66z3q2

# Checkout the branch
git checkout claude/apply-cicd-workflow-01MYwP7mxgknDyzH5L66z3q2

# The commit is already there, just push it
git push origin claude/apply-cicd-workflow-01MYwP7mxgknDyzH5L66z3q2
```

### Method 3: Apply Patch File

A patch file has been generated at `/tmp/workflow-update.patch`:

```bash
# From any git client with proper permissions:
git checkout claude/apply-cicd-workflow-01MYwP7mxgknDyzH5L66z3q2
git am < workflow-update.patch
git push origin claude/apply-cicd-workflow-01MYwP7mxgknDyzH5L66z3q2
```

## 📝 Detailed Changes

### Change 1: Update Workflow Triggers (Lines 4-17)

**Before:**
```yaml
on:
  pull_request:
    paths:
      - 'charts/**'
  push:
    branches:
      - develop
    paths:
      - 'charts/**'
```

**After:**
```yaml
on:
  pull_request:
    paths:
      - 'charts/**'
      - 'charts-metadata.yaml'
      - 'scripts/*.py'
      - 'scripts/requirements.txt'
  push:
    branches:
      - develop
    paths:
      - 'charts/**'
      - 'charts-metadata.yaml'
      - 'scripts/*.py'
      - 'scripts/requirements.txt'
```

### Change 2: Add metadata-validation Job (After Line 154)

Insert this entire job after the `helm-lint` job and before `validation-summary`:

```yaml
  metadata-validation:
    runs-on: ubuntu-22.04
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: |
          pip install -r scripts/requirements.txt

      - name: Validate chart metadata
        run: |
          echo "### Chart Metadata Validation" >> $GITHUB_STEP_SUMMARY
          python3 scripts/validate-chart-metadata.py
          echo "✅ All charts metadata validated successfully" >> $GITHUB_STEP_SUMMARY

      - name: Check catalog is up-to-date
        run: |
          echo "### Chart Catalog Verification" >> $GITHUB_STEP_SUMMARY
          # Generate catalog
          python3 scripts/generate-chart-catalog.py

          # Check if there are any differences
          if ! git diff --quiet docs/CHARTS.md; then
            echo "❌ Chart catalog is out of date!" >> $GITHUB_STEP_SUMMARY
            echo "Please run 'make generate-catalog' and commit the changes." >> $GITHUB_STEP_SUMMARY
            echo "" >> $GITHUB_STEP_SUMMARY
            echo "Differences:" >> $GITHUB_STEP_SUMMARY
            git diff docs/CHARTS.md >> $GITHUB_STEP_SUMMARY
            exit 1
          else
            echo "✅ Chart catalog is up-to-date" >> $GITHUB_STEP_SUMMARY
          fi
```

### Change 3: Update validation-summary Job (Lines 195-213)

**Before:**
```yaml
  validation-summary:
    runs-on: ubuntu-22.04
    needs: [lint-test, helm-lint]
    if: always()
    steps:
      - name: Check results
        run: |
          if [[ "${{ needs.lint-test.result }}" == "success" ]] && [[ "${{ needs.helm-lint.result }}" == "success" ]]; then
            echo "✅ All validation checks passed!" >> $GITHUB_STEP_SUMMARY
            exit 0
          else
            echo "❌ Some validation checks failed!" >> $GITHUB_STEP_SUMMARY
            echo "- lint-test: ${{ needs.lint-test.result }}" >> $GITHUB_STEP_SUMMARY
            echo "- helm-lint: ${{ needs.helm-lint.result }}" >> $GITHUB_STEP_SUMMARY
            exit 1
          fi
```

**After:**
```yaml
  validation-summary:
    runs-on: ubuntu-22.04
    needs: [lint-test, helm-lint, metadata-validation]
    if: always()
    steps:
      - name: Check results
        run: |
          if [[ "${{ needs.lint-test.result }}" == "success" ]] && \
             [[ "${{ needs.helm-lint.result }}" == "success" ]] && \
             [[ "${{ needs.metadata-validation.result }}" == "success" ]]; then
            echo "✅ All validation checks passed!" >> $GITHUB_STEP_SUMMARY
            exit 0
          else
            echo "❌ Some validation checks failed!" >> $GITHUB_STEP_SUMMARY
            echo "- lint-test: ${{ needs.lint-test.result }}" >> $GITHUB_STEP_SUMMARY
            echo "- helm-lint: ${{ needs.helm-lint.result }}" >> $GITHUB_STEP_SUMMARY
            echo "- metadata-validation: ${{ needs.metadata-validation.result }}" >> $GITHUB_STEP_SUMMARY
            exit 1
          fi
```

## ✅ Verification Steps

After applying the changes:

1. **Validate YAML syntax:**
   ```bash
   python3 -c "import yaml; yaml.safe_load(open('.github/workflows/lint-test.yaml'))"
   ```

2. **Test workflow trigger:**
   - Modify `charts-metadata.yaml`
   - Create a PR or push to develop branch
   - Verify `metadata-validation` job appears in GitHub Actions

3. **Test metadata validation:**
   - Intentionally make keywords mismatch
   - Verify workflow catches the error

4. **Test catalog verification:**
   - Modify `charts-metadata.yaml` without running `make generate-catalog`
   - Verify workflow detects outdated catalog

## 📝 Additional Optional Changes

### cleanup.yaml Formatting (Optional)

**File:** `.github/workflows/cleanup.yaml`

**Change:** Remove trailing whitespace (lines 2, 26)

```yaml
# Line 2
-concurrency:
+concurrency:

# Line 26
-
+
```

**Impact:** Code formatting only, no functional change
**Priority:** Low (optional cleanup)

## 🎯 Benefits

Once applied, the enhanced CI workflow will:

- ✅ **Catch metadata issues early** in the PR process
- ✅ **Prevent stale catalog** from being merged
- ✅ **Provide actionable error messages** with clear instructions
- ✅ **Automate Chart Metadata Management System** validation
- ✅ **Ensure consistency** across all chart metadata

## 📚 Related Documentation

- [Workflow Update Instructions](docs/WORKFLOW_UPDATE_INSTRUCTIONS.md)
- [Chart Development Guide](docs/CHART_DEVELOPMENT_GUIDE.md)
- [CLAUDE.md - Chart Metadata Section](CLAUDE.md#chart-metadata)

## 🔗 Related Commits

This change completes the Chart Metadata Management System:

- `acb6ba6` - Initial metadata structure
- `9014a73` - Validation scripts
- `5767add` - Sync automation
- `87a8363` - Pre-commit hooks
- `b1e3a74` - Documentation
- `7de1357` - Catalog generation
- `38b6dfc` - Artifact Hub dashboard
- `59912c3` - Badge integration
- `387f03d` - Cross-references
- `720e305` - Final documentation
- `1f0fabd` - **CI/CD automation (this commit)**

---

**Created:** 2025-11-17
**Status:** Ready for manual application
**Priority:** High (completes automation system)
