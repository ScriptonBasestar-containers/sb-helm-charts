#!/usr/bin/env python3
"""
Sync Chart.yaml Keywords from Metadata

This script automatically updates Chart.yaml keywords based on charts-metadata.yaml.
Useful for bulk updates when metadata is the source of truth.

Usage:
    # Dry-run (preview changes)
    python scripts/sync-chart-keywords.py --dry-run

    # Apply changes
    python scripts/sync-chart-keywords.py

    # Sync specific chart
    python scripts/sync-chart-keywords.py --chart keycloak

Exit codes:
    0: Success (changes applied or no changes needed)
    1: Errors occurred
"""

import sys
import argparse
import yaml
from pathlib import Path
from typing import Dict, List, Tuple


def load_yaml_file(file_path: Path) -> Dict:
    """Load and parse YAML file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    except Exception as e:
        print(f"Error loading {file_path}: {e}")
        sys.exit(1)


def save_yaml_file(file_path: Path, data: Dict) -> None:
    """Save YAML file preserving formatting."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Simple keyword replacement to preserve formatting
        # Find the keywords section and replace it
        lines = content.split('\n')
        new_lines = []
        in_keywords = False
        indent = ''

        for line in lines:
            if line.strip().startswith('keywords:'):
                in_keywords = True
                indent = line[:len(line) - len(line.lstrip())]
                new_lines.append(line)
                # Add new keywords
                for keyword in data.get('keywords', []):
                    new_lines.append(f"{indent}  - {keyword}")
            elif in_keywords and line.strip().startswith('-'):
                # Skip old keywords
                continue
            elif in_keywords and line and not line.startswith(' '):
                # End of keywords section
                in_keywords = False
                new_lines.append(line)
            elif in_keywords and not line.strip():
                # Empty line in keywords - end of section
                in_keywords = False
                new_lines.append(line)
            else:
                new_lines.append(line)

        with open(file_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(new_lines))

    except Exception as e:
        print(f"Error saving {file_path}: {e}")
        sys.exit(1)


def sync_chart_keywords(
    chart_name: str,
    chart_yaml_path: Path,
    metadata_keywords: List[str],
    dry_run: bool
) -> Tuple[bool, str]:
    """Sync keywords from metadata to Chart.yaml.

    Returns:
        (changed, message)
    """
    # Load Chart.yaml
    chart_yaml = load_yaml_file(chart_yaml_path)
    current_keywords = chart_yaml.get('keywords', [])

    # Compare keywords
    if set(current_keywords) == set(metadata_keywords):
        return (False, f"  ℹ️  {chart_name}: Keywords already synchronized")

    # Update keywords
    if dry_run:
        return (
            True,
            f"  🔄 {chart_name}: Would update keywords\n"
            f"     Current: {current_keywords}\n"
            f"     New:     {metadata_keywords}"
        )
    else:
        chart_yaml['keywords'] = metadata_keywords
        save_yaml_file(chart_yaml_path, chart_yaml)
        return (
            True,
            f"  ✅ {chart_name}: Keywords updated\n"
            f"     Old: {current_keywords}\n"
            f"     New: {metadata_keywords}"
        )


def main():
    """Main sync logic."""
    parser = argparse.ArgumentParser(
        description='Sync Chart.yaml keywords from charts-metadata.yaml'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Preview changes without applying them'
    )
    parser.add_argument(
        '--chart',
        type=str,
        help='Sync specific chart only'
    )
    args = parser.parse_args()

    # Setup paths
    repo_root = Path(__file__).parent.parent
    charts_dir = repo_root / "charts"
    metadata_file = repo_root / "charts-metadata.yaml"

    print("=" * 80)
    if args.dry_run:
        print("Chart Keywords Sync (DRY RUN)")
    else:
        print("Chart Keywords Sync")
    print("=" * 80)
    print()

    # Load metadata
    if not metadata_file.exists():
        print(f"Error: {metadata_file} not found")
        sys.exit(1)

    metadata = load_yaml_file(metadata_file)
    charts_metadata = metadata.get('charts', {})

    # Determine which charts to sync
    if args.chart:
        if args.chart not in charts_metadata:
            print(f"Error: Chart '{args.chart}' not found in metadata")
            sys.exit(1)
        charts_to_sync = {args.chart: charts_metadata[args.chart]}
    else:
        charts_to_sync = charts_metadata

    print(f"Syncing {len(charts_to_sync)} chart(s)...")
    print()

    # Sync each chart
    changes_made = False
    for chart_name, chart_meta in charts_to_sync.items():
        chart_yaml_path = charts_dir / chart_name / "Chart.yaml"

        if not chart_yaml_path.exists():
            print(f"  ⚠️  {chart_name}: Chart.yaml not found, skipping")
            continue

        metadata_keywords = chart_meta.get('keywords', [])
        if not metadata_keywords:
            print(f"  ⚠️  {chart_name}: No keywords in metadata, skipping")
            continue

        changed, message = sync_chart_keywords(
            chart_name,
            chart_yaml_path,
            metadata_keywords,
            args.dry_run
        )

        print(message)
        if changed:
            changes_made = True

    # Summary
    print()
    print("=" * 80)
    if args.dry_run:
        if changes_made:
            print("✅ Preview complete - changes would be applied")
            print("   Run without --dry-run to apply changes")
        else:
            print("✅ Preview complete - no changes needed")
    else:
        if changes_made:
            print("✅ Keywords synchronized successfully!")
            print("   Don't forget to commit the changes")
        else:
            print("✅ All keywords already synchronized")
    print("=" * 80)


if __name__ == "__main__":
    main()
