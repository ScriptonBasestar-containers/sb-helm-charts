# Workflow Update Instructions

## ⚠️ Manual Update Required

The following changes to `.github/workflows/lint-test.yaml` need to be applied manually due to GitHub App workflow permissions.

## Changes to Apply

### 1. Update workflow triggers (lines 4-17)

Add metadata and scripts paths to trigger the workflow:

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

### 2. Add metadata-validation job (after helm-lint job, before validation-summary)

Insert this new job:

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

### 3. Update validation-summary job (lines ~195-213)

Update the `needs` line and condition checks:

```yaml
  validation-summary:
    runs-on: ubuntu-22.04
    needs: [lint-test, helm-lint, metadata-validation]  # Add metadata-validation
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

## How to Apply

### Option 1: Via GitHub Web UI (Recommended)

1. Go to https://github.com/ScriptonBasestar-containers/sb-helm-charts
2. Navigate to `.github/workflows/lint-test.yaml`
3. Click "Edit" button
4. Apply the three changes above
5. Commit directly to the branch or create a PR

### Option 2: Via Git (without GitHub App)

If you have direct git access (not via Claude Code):

```bash
# The changes are already in the local commit:
# commit 8423318: "ci: Add metadata validation and catalog verification to CI/CD"

# To apply manually:
git show 8423318:.github/workflows/lint-test.yaml > .github/workflows/lint-test.yaml
git add .github/workflows/lint-test.yaml
git commit -m "ci: Add metadata validation and catalog verification to CI/CD"
git push
```

## Why This is Needed

The enhanced CI workflow will now:

1. ✅ **Validate chart metadata consistency** (NEW)
   - Ensures Chart.yaml keywords match charts-metadata.yaml
   - Runs on every chart change

2. ✅ **Verify chart catalog is up-to-date** (NEW)
   - Generates catalog and checks for differences
   - Fails if catalog needs regeneration
   - Shows exactly what needs to be updated

3. ✅ Run chart-testing (ct) lint and install (existing)

4. ✅ Run helm lint for all charts and scenarios (existing)

### Benefits

- **Catch metadata issues early** in the PR process
- **Prevent stale catalog** from being merged
- **Actionable error messages** with clear instructions
- **Automated validation** of Chart Metadata Management System

## Verification

After applying the changes:

1. **Test on PR**: Open a PR that modifies `charts-metadata.yaml`
2. **Check Actions**: The `metadata-validation` job should appear
3. **Verify Output**: Check GitHub Step Summary for validation results
4. **Test Catalog**: Modify metadata without regenerating catalog to see failure

## Complete File Reference

The complete updated workflow file is available in commit `8423318`:

```bash
git show 8423318:.github/workflows/lint-test.yaml
```

This commit includes all three changes described above and has been validated for YAML syntax.

---

**Last Updated**: 2025-11-17
**Related**: Chart Metadata Management System (commits: acb6ba6, 9014a73, 5767add, 87a8363, b1e3a74, 7de1357, 38b6dfc, 59912c3, 387f03d, 720e305, 8423318)
