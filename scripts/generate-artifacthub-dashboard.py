#!/usr/bin/env python3
"""
Generate Artifact Hub Statistics Dashboard

This script generates a dashboard showing Artifact Hub status and badges
for all charts in the repository.

Usage:
    python3 scripts/generate-artifacthub-dashboard.py

Output:
    docs/ARTIFACTHUB_DASHBOARD.md
"""

import yaml
import sys
from pathlib import Path
from datetime import datetime

def load_yaml_file(file_path):
    """Load and parse a YAML file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"❌ Error: File not found: {file_path}", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"❌ Error parsing YAML file {file_path}: {e}", file=sys.stderr)
        sys.exit(1)

def generate_artifacthub_badge(repo_name, chart_name=None):
    """Generate Artifact Hub badge markdown."""
    if chart_name:
        # Package-specific badge
        badge_url = f"https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/{repo_name}"
        link_url = f"https://artifacthub.io/packages/helm/{repo_name}/{chart_name}"
    else:
        # Repository badge
        badge_url = f"https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/{repo_name}"
        link_url = f"https://artifacthub.io/packages/search?repo={repo_name}"

    return f"[![Artifact Hub]({badge_url})]({link_url})"

def generate_dashboard(metadata_file, output_file, repo_name):
    """Generate Artifact Hub dashboard from metadata."""

    # Load metadata
    metadata = load_yaml_file(metadata_file)
    charts = metadata.get('charts', {})

    if not charts:
        print("❌ No charts found in metadata", file=sys.stderr)
        sys.exit(1)

    # Group by category
    categories = {}
    for chart_name, chart_info in sorted(charts.items()):
        category = chart_info.get('category', 'uncategorized')
        if category not in categories:
            categories[category] = []
        categories[category].append((chart_name, chart_info))

    # Generate markdown
    md = []
    md.append("# Artifact Hub Statistics Dashboard")
    md.append("")
    md.append("<!-- AUTO-GENERATED FILE - DO NOT EDIT MANUALLY -->")
    md.append(f"<!-- Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} -->")
    md.append(f"<!-- To update, run: make generate-artifacthub-dashboard -->")
    md.append("")
    md.append("> **Note**: This dashboard is automatically generated from `charts-metadata.yaml`.")
    md.append("> To update the dashboard, run `make generate-artifacthub-dashboard`.")
    md.append("")

    # Repository badge
    md.append("## Repository Status")
    md.append("")
    md.append(f"**Repository**: {repo_name}")
    md.append("")
    md.append(generate_artifacthub_badge(repo_name))
    md.append("")
    md.append("**Artifact Hub URL**: " +
             f"https://artifacthub.io/packages/search?repo={repo_name}")
    md.append("")

    # Quick stats
    total_charts = len(charts)
    app_charts = len([c for c in charts.values() if c.get('category') == 'application'])
    infra_charts = len([c for c in charts.values() if c.get('category') == 'infrastructure'])

    md.append("## Quick Statistics")
    md.append("")
    md.append(f"- **Total Charts**: {total_charts}")
    md.append(f"- **Application Charts**: {app_charts}")
    md.append(f"- **Infrastructure Charts**: {infra_charts}")
    md.append("")

    # Table of contents
    md.append("## Table of Contents")
    md.append("")
    for category in sorted(categories.keys()):
        category_title = category.replace('_', ' ').title()
        md.append(f"- [{category_title} Charts](#" +
                 category.replace('_', '-') + "-charts)")
    md.append("")
    md.append("---")
    md.append("")

    # Charts by category
    for category in sorted(categories.keys()):
        category_title = category.replace('_', ' ').title()
        md.append(f"## {category_title} Charts")
        md.append("")

        category_charts = categories[category]

        for chart_name, chart_info in category_charts:
            display_name = chart_info.get('name', chart_name)
            description = chart_info.get('description', 'No description')
            path = chart_info.get('path', f'charts/{chart_name}')

            # Chart header with badge
            md.append(f"### {display_name}")
            md.append("")
            md.append(generate_artifacthub_badge(repo_name, chart_name))
            md.append("")
            md.append(f"**Description**: {description}")
            md.append("")

            # Artifact Hub link
            md.append("**Artifact Hub Package**: " +
                     f"https://artifacthub.io/packages/helm/{repo_name}/{chart_name}")
            md.append("")

            # Metadata
            tags = chart_info.get('tags', [])
            keywords = chart_info.get('keywords', [])

            if tags:
                md.append(f"**Tags**: {', '.join(tags)}")
                md.append("")

            if keywords:
                md.append(f"**Keywords**: {', '.join(keywords[:5])}" +
                         (f" (+{len(keywords)-5} more)" if len(keywords) > 5 else ""))
                md.append("")

            # Production note
            if chart_info.get('production_note'):
                md.append(f"> ⚠️ **Production Note**: {chart_info['production_note']}")
                md.append("")

            # Local documentation
            md.append(f"**Local Documentation**: [{path}/README.md](../{path}/README.md)")
            md.append("")
            md.append("---")
            md.append("")

    # Publishing guide
    md.append("## Publishing to Artifact Hub")
    md.append("")
    md.append("If your charts are not yet published to Artifact Hub, follow these steps:")
    md.append("")
    md.append("### Prerequisites")
    md.append("")
    md.append("1. Charts must be published to a Helm repository (GitHub Pages, etc.)")
    md.append("2. Repository must be publicly accessible")
    md.append("3. Charts must follow Helm best practices")
    md.append("")
    md.append("### Publishing Steps")
    md.append("")
    md.append("1. **Create Artifact Hub Repository Metadata**")
    md.append("")
    md.append("   Add `artifacthub-repo.yml` to your chart repository root:")
    md.append("")
    md.append("   ```yaml")
    md.append("   repositoryID: <your-repository-id>")
    md.append("   owners:")
    md.append("     - name: <your-name>")
    md.append("       email: <your-email>")
    md.append("   ```")
    md.append("")
    md.append("2. **Add Repository to Artifact Hub**")
    md.append("")
    md.append("   - Go to https://artifacthub.io/")
    md.append("   - Sign in with GitHub")
    md.append("   - Navigate to Control Panel > Add Repository")
    md.append("   - Enter your Helm repository URL")
    md.append("")
    md.append("3. **Verify Publisher**")
    md.append("")
    md.append("   Add the provided verification metadata file to your GitHub repository root.")
    md.append("")
    md.append("### Chart Annotations")
    md.append("")
    md.append("Enhance chart metadata with Artifact Hub annotations in `Chart.yaml`:")
    md.append("")
    md.append("```yaml")
    md.append("annotations:")
    md.append("  artifacthub.io/changes: |")
    md.append("    - kind: added")
    md.append("      description: Initial release")
    md.append("  artifacthub.io/containsSecurityUpdates: \"false\"")
    md.append("  artifacthub.io/prerelease: \"false\"")
    md.append("```")
    md.append("")
    md.append("## Artifact Hub Badges")
    md.append("")
    md.append("Once published, you can add Artifact Hub badges to your READMEs:")
    md.append("")
    md.append("### Repository Badge")
    md.append("")
    md.append("```markdown")
    md.append(f"[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/{repo_name})]" +
             f"(https://artifacthub.io/packages/search?repo={repo_name})")
    md.append("```")
    md.append("")
    md.append("### Package Badge")
    md.append("")
    md.append("```markdown")
    md.append(f"[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/{repo_name})]" +
             f"(https://artifacthub.io/packages/helm/{repo_name}/{{chart-name}})")
    md.append("```")
    md.append("")
    md.append("## Resources")
    md.append("")
    md.append("- [Artifact Hub Documentation](https://artifacthub.io/docs)")
    md.append("- [Helm Chart Annotations](https://artifacthub.io/docs/topics/annotations/helm/)")
    md.append("- [Repository Metadata](https://artifacthub.io/docs/topics/repositories/)")
    md.append("- [Chart Catalog](CHARTS.md) - Browse all available charts")
    md.append("")
    md.append("---")
    md.append("")
    md.append(f"**Last Updated**: {datetime.now().strftime('%Y-%m-%d')}")
    md.append("")

    # Write to file
    output_path = Path(output_file)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(md))

    print(f"✅ Generated Artifact Hub dashboard: {output_file}")
    print(f"   Total charts: {total_charts}")
    print(f"   Categories: {len(categories)}")

def main():
    """Main function."""
    # File paths
    repo_root = Path(__file__).parent.parent
    metadata_file = repo_root / 'charts-metadata.yaml'
    output_file = repo_root / 'docs' / 'ARTIFACTHUB_DASHBOARD.md'

    # Repository name (adjust as needed)
    repo_name = 'sb-helm-charts'

    print("Generating Artifact Hub dashboard...")
    generate_dashboard(metadata_file, output_file, repo_name)
    print("✅ Dashboard generation complete!")

if __name__ == '__main__':
    main()
