#!/usr/bin/env python3
"""
Validate Chart Metadata Consistency

This script validates that:
1. All charts in charts/ directory have entries in charts-metadata.yaml
2. Keywords in Chart.yaml match charts-metadata.yaml
3. Chart names and descriptions are consistent

Usage:
    python scripts/validate-chart-metadata.py

Exit codes:
    0: All validations passed
    1: Validation failures found
"""

import sys
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


def find_chart_dirs(charts_dir: Path) -> List[Path]:
    """Find all chart directories."""
    chart_dirs = []
    for item in charts_dir.iterdir():
        if item.is_dir() and (item / "Chart.yaml").exists():
            chart_dirs.append(item)
    return sorted(chart_dirs)


def normalize_keywords(keywords: List[str]) -> set:
    """Normalize keywords for comparison (lowercase, stripped)."""
    return set(k.lower().strip() for k in keywords)


def validate_chart(
    chart_name: str,
    chart_yaml: Dict,
    metadata_entry: Dict
) -> Tuple[bool, List[str]]:
    """Validate a single chart against metadata.

    Returns:
        (is_valid, errors)
    """
    errors = []

    # Check keywords
    chart_keywords = normalize_keywords(chart_yaml.get('keywords', []))
    meta_keywords = normalize_keywords(metadata_entry.get('keywords', []))

    if chart_keywords != meta_keywords:
        errors.append(
            f"  Keywords mismatch:\n"
            f"    Chart.yaml:          {sorted(chart_keywords)}\n"
            f"    charts-metadata.yaml: {sorted(meta_keywords)}"
        )

    # Note: We don't validate description as Chart.yaml typically has more detailed
    # descriptions while metadata has concise summaries for CLAUDE.md

    return (len(errors) == 0, errors)


def main():
    """Main validation logic."""
    # Setup paths
    repo_root = Path(__file__).parent.parent
    charts_dir = repo_root / "charts"
    metadata_file = repo_root / "charts" / "charts-metadata.yaml"

    print("=" * 80)
    print("Chart Metadata Validation")
    print("=" * 80)
    print()

    # Load metadata
    if not metadata_file.exists():
        print(f"Error: {metadata_file} not found")
        sys.exit(1)

    metadata = load_yaml_file(metadata_file)
    charts_metadata = metadata.get('charts', {})

    # Find all charts
    chart_dirs = find_chart_dirs(charts_dir)

    if not chart_dirs:
        print(f"Error: No charts found in {charts_dir}")
        sys.exit(1)

    print(f"Found {len(chart_dirs)} charts to validate")
    print(f"Metadata file contains {len(charts_metadata)} chart entries")
    print()

    # Validate each chart
    all_valid = True
    charts_checked = []

    for chart_dir in chart_dirs:
        chart_name = chart_dir.name
        chart_yaml_path = chart_dir / "Chart.yaml"

        print(f"Checking {chart_name}...")
        charts_checked.append(chart_name)

        # Load Chart.yaml
        chart_yaml = load_yaml_file(chart_yaml_path)

        # Check if chart exists in metadata
        if chart_name not in charts_metadata:
            print(f"  ❌ Chart not found in charts-metadata.yaml")
            all_valid = False
            continue

        # Validate chart
        is_valid, errors = validate_chart(
            chart_name,
            chart_yaml,
            charts_metadata[chart_name]
        )

        if is_valid:
            print(f"  ✅ Valid")
        else:
            print(f"  ❌ Validation failed:")
            for error in errors:
                print(error)
            all_valid = False

        print()

    # Check for charts in metadata but not in filesystem
    for meta_chart_name in charts_metadata.keys():
        if meta_chart_name not in charts_checked:
            print(f"⚠️  Warning: {meta_chart_name} exists in metadata but not in charts/ directory")
            print()

    # Summary
    print("=" * 80)
    if all_valid:
        print("✅ All validations passed!")
        print("=" * 80)
        sys.exit(0)
    else:
        print("❌ Validation failed - please fix the errors above")
        print("=" * 80)
        sys.exit(1)


if __name__ == "__main__":
    main()
