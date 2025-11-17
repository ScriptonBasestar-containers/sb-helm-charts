## Description

<!-- Provide a brief description of the changes in this PR -->

## Type of Change

<!-- Mark the relevant option with an "x" -->

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] New chart
- [ ] Chart enhancement
- [ ] CI/CD improvement
- [ ] Dependency update

## Related Issues

<!-- Link related issues here. Use keywords like "Fixes #123" or "Closes #456" -->

Fixes #

## Changes Made

<!-- Describe the changes in detail -->

-
-
-

## Chart Changes (if applicable)

**Chart Name(s):**

**Version Bump:**
- [ ] MAJOR (breaking changes)
- [ ] MINOR (new features, backward-compatible)
- [ ] PATCH (bug fixes, documentation)

**Affected Files:**
- [ ] Chart.yaml
- [ ] values.yaml
- [ ] values-*.yaml (scenario files)
- [ ] templates/
- [ ] README.md
- [ ] Other (specify):

## Testing Performed

<!-- Describe the testing you've done -->

- [ ] `helm lint` passes with 0 errors
- [ ] `helm install --dry-run --debug` succeeds
- [ ] Tested with `values-home-single.yaml`
- [ ] Tested with `values-startup-single.yaml`
- [ ] Tested with `values-prod-master-replica.yaml`
- [ ] Tested in local Kind/minikube cluster
- [ ] Tested upgrade path from previous version
- [ ] Manual testing performed (describe below)

**Test Environment:**
- Kubernetes version:
- Helm version:
- Platform:

**Test Results:**
<!-- Paste relevant test output or describe results -->

```bash
# Example test commands and output
helm lint charts/my-chart
# Output here
```

## Documentation Updates

- [ ] Chart README.md updated
- [ ] CHANGELOG.md updated
- [ ] values.yaml comments are clear
- [ ] NOTES.txt provides useful post-install information
- [ ] Related documentation updated (if applicable)

## Checklist

<!-- Ensure all items are checked before submitting -->

### Required
- [ ] Code follows the project's [Chart Development Guide](../docs/CHART_DEVELOPMENT_GUIDE.md)
- [ ] Chart version incremented according to [Chart Version Policy](../docs/CHART_VERSION_POLICY.md)
- [ ] CHANGELOG.md updated with changes
- [ ] All CI checks pass
- [ ] Helm chart lints successfully
- [ ] Commit messages follow conventional commits format (`feat:`, `fix:`, `docs:`, etc.)
- [ ] No unrelated changes included
- [ ] Branch is up-to-date with target branch

### Chart-specific (if applicable)
- [ ] `charts-metadata.yaml` updated with chart metadata (name, path, category, tags, keywords)
- [ ] External database configuration follows project philosophy (no subcharts)
- [ ] Configuration uses files over environment variables where appropriate
- [ ] All three scenario values files created/updated
- [ ] Artifact Hub metadata added/updated in Chart.yaml
- [ ] Chart.yaml keywords match charts-metadata.yaml
- [ ] Templates follow naming conventions
- [ ] Helper functions use standard names
- [ ] NOTES.txt includes access information and credential retrieval commands

### Pre-commit Hooks
- [ ] Pre-commit hooks installed and passing
- [ ] All automated checks pass locally

### Optional (but recommended)
- [ ] Screenshots/examples added (for UI changes)
- [ ] Migration guide provided (for breaking changes)
- [ ] Tested with multiple Kubernetes versions
- [ ] Performance implications considered and documented

## Additional Notes

<!-- Any additional information, concerns, or questions -->

## Breaking Changes

<!-- If this is a breaking change, describe the impact and migration path -->

**Migration Guide:**
<!-- Provide step-by-step instructions for users to migrate -->

1.
2.
3.

## Screenshots (if applicable)

<!-- Add screenshots to help explain your changes -->

---

**For Reviewers:**

<!-- Highlight specific areas that need attention -->

Please pay special attention to:
-
-

<!--
Thank you for contributing to sb-helm-charts!
Please ensure you've read our Contributing Guide: .github/CONTRIBUTING.md
-->
