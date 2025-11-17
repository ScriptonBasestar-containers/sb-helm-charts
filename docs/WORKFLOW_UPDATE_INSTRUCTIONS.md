# Workflow Update Instructions

## ⚠️ Manual Update Required

The following changes to `.github/workflows/lint-test.yaml` need to be applied manually due to GitHub App workflow permissions.

## Changes to Apply

### 1. Update workflow triggers (lines 4-12)

Add `charts-metadata.yaml` and validation script to trigger paths:

```yaml
on:
  pull_request:
    paths:
      - 'charts/**'
      - 'charts-metadata.yaml'
      - 'scripts/validate-chart-metadata.py'
  push:
    branches:
      - develop
    paths:
      - 'charts/**'
      - 'charts-metadata.yaml'
      - 'scripts/validate-chart-metadata.py'
```

### 2. Add new validate-metadata job (after lint-test job, before helm-lint)

Insert this new job after the `lint-test` job:

```yaml
  validate-metadata:
    runs-on: ubuntu-22.04
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install PyYAML
        run: pip install pyyaml

      - name: Validate chart metadata
        run: |
          echo "## Chart Metadata Validation" >> $GITHUB_STEP_SUMMARY
          if python3 scripts/validate-chart-metadata.py; then
            echo "✅ All chart metadata validated successfully" >> $GITHUB_STEP_SUMMARY
          else
            echo "❌ Chart metadata validation failed" >> $GITHUB_STEP_SUMMARY
            exit 1
          fi
```

### 3. Update validation-summary job dependencies

Update the `needs` line and the condition check:

```yaml
  validation-summary:
    runs-on: ubuntu-22.04
    needs: [lint-test, validate-metadata, helm-lint]  # Add validate-metadata
    if: always()
    steps:
      - name: Check results
        run: |
          if [[ "${{ needs.lint-test.result }}" == "success" ]] && \
             [[ "${{ needs.validate-metadata.result }}" == "success" ]] && \
             [[ "${{ needs.helm-lint.result }}" == "success" ]]; then
            echo "✅ All validation checks passed!" >> $GITHUB_STEP_SUMMARY
            exit 0
          else
            echo "❌ Some validation checks failed!" >> $GITHUB_STEP_SUMMARY
            echo "- lint-test: ${{ needs.lint-test.result }}" >> $GITHUB_STEP_SUMMARY
            echo "- validate-metadata: ${{ needs.validate-metadata.result }}" >> $GITHUB_STEP_SUMMARY
            echo "- helm-lint: ${{ needs.helm-lint.result }}" >> $GITHUB_STEP_SUMMARY
            exit 1
          fi
```

## How to Apply

### Option 1: Via GitHub Web UI

1. Go to https://github.com/ScriptonBasestar-containers/sb-helm-charts
2. Navigate to `.github/workflows/lint-test.yaml`
3. Click "Edit" button
4. Apply the changes above
5. Commit directly to the branch

### Option 2: Via Git (without GitHub App)

If you have direct git access (not via Claude Code):

```bash
# Apply the changes manually to .github/workflows/lint-test.yaml
git add .github/workflows/lint-test.yaml
git commit -m "feat(ci): Add chart metadata validation to CI workflow"
git push
```

## Why This is Needed

The CI workflow will now:
1. ✅ Run chart-testing (ct) lint and install
2. ✅ **Validate chart metadata consistency** (NEW)
3. ✅ Run helm lint for all charts and scenarios

This ensures that `charts-metadata.yaml` and `Chart.yaml` keywords remain synchronized.

## Verification

After applying the changes, the next PR or push to `develop` that modifies charts, charts-metadata.yaml, or the validation script will trigger the new validation job.
