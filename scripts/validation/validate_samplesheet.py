#!/usr/bin/env python3
"""
Validate an nf-core/rnaseq samplesheet before pipeline execution.

Checks:
  - Required columns present (sample, fastq_1, fastq_2, strandedness)
  - Sample names contain no spaces or invalid characters
  - FASTQ files exist and are gzip compressed
  - Strandedness values are valid (auto, forward, reverse, unstranded)
  - Paired-end files both exist when specified
  - Detects multi-lane technical replicates (same sample name)
  - Warns about potential issues

Each row represents a fastq file (single-end) or a pair of fastq files
(paired end). Rows with the same sample identifier are considered
technical replicates and merged automatically.
The strandedness refers to the library preparation and will be
automatically inferred if set to auto.

Usage:
    python validate_samplesheet.py <samplesheet.csv>

Exit codes:
    0 = validation passed
    1 = validation failed (errors found)
"""

import csv
import sys
import os
import gzip
from collections import Counter

def validate(filepath):
    """Validate samplesheet and return lists of errors and warnings."""
    errors = []
    warnings = []
    samples = Counter()
    row_count = 0
    all_se = True
    all_pe = True

    # Check file exists and is readable
    if not os.path.isfile(filepath):
        return [f"File not found: {filepath}"], []

    if os.path.getsize(filepath) == 0:
        return ["File is empty"], []

    with open(filepath, 'r', newline='') as f:
        # Check for BOM (byte order mark) that can cause issues
        first_bytes = f.read(3)
        if first_bytes.startswith('\ufeff'):
            warnings.append("File contains BOM (byte order mark) — may cause parsing issues")
        f.seek(0)

        try:
            reader = csv.DictReader(f)
        except Exception as e:
            return [f"Cannot parse CSV: {e}"], []

        if reader.fieldnames is None:
            return ["No header row found — file may be empty or not CSV format"], []

        # Check required columns
        required_cols = ['sample', 'fastq_1', 'fastq_2', 'strandedness']
        missing_cols = [c for c in required_cols if c not in reader.fieldnames]
        if missing_cols:
            return [f"Missing required columns: {missing_cols}. Found: {reader.fieldnames}"], []

        # Check for optional columns
        optional_cols = ['seq_platform']
        extra_cols = [c for c in reader.fieldnames if c not in required_cols + optional_cols]
        if extra_cols:
            warnings.append(f"Unexpected columns (will be ignored): {extra_cols}")

        # Valid strandedness values
        valid_strands = {'auto', 'forward', 'reverse', 'unstranded'}

        for i, row in enumerate(reader, start=2):
            row_count += 1

            sample = row.get('sample', '').strip()
            fq1 = row.get('fastq_1', '').strip()
            fq2 = row.get('fastq_2', '').strip()
            strand = row.get('strandedness', '').strip()

            # ---- Sample name validation ----
            if not sample:
                errors.append(f"Row {i}: Empty sample name")
                continue

            if ' ' in sample:
                errors.append(f"Row {i}: Sample name contains spaces: '{sample}'")

            if not all(c.isalnum() or c in '_-.' for c in sample):
                warnings.append(f"Row {i}: Sample name has special characters: '{sample}'")

            if sample.startswith('-') or sample.startswith('.'):
                errors.append(f"Row {i}: Sample name starts with invalid character: '{sample}'")

            # ---- FASTQ_1 validation (required) ----
            if not fq1:
                errors.append(f"Row {i}: Empty fastq_1 for sample '{sample}'")
            else:
                if not os.path.isabs(fq1):
                    warnings.append(f"Row {i}: fastq_1 is not an absolute path: '{fq1}'")

                if not os.path.isfile(fq1):
                    errors.append(f"Row {i}: fastq_1 not found: '{fq1}'")
                elif os.path.getsize(fq1) == 0:
                    errors.append(f"Row {i}: fastq_1 is empty (0 bytes): '{fq1}'")

                if not (fq1.endswith('.fastq.gz') or fq1.endswith('.fq.gz')):
                    errors.append(f"Row {i}: fastq_1 must be gzip compressed (.fastq.gz or .fq.gz): '{os.path.basename(fq1)}'")

            # ---- FASTQ_2 validation (optional for SE) ----
            if fq2:
                all_se = False
                if not os.path.isabs(fq2):
                    warnings.append(f"Row {i}: fastq_2 is not an absolute path: '{fq2}'")

                if not os.path.isfile(fq2):
                    errors.append(f"Row {i}: fastq_2 not found: '{fq2}'")
                elif os.path.getsize(fq2) == 0:
                    errors.append(f"Row {i}: fastq_2 is empty (0 bytes): '{fq2}'")

                if not (fq2.endswith('.fastq.gz') or fq2.endswith('.fq.gz')):
                    errors.append(f"Row {i}: fastq_2 must be gzip compressed (.fastq.gz or .fq.gz): '{os.path.basename(fq2)}'")

                # Check R1 and R2 are not the same file
                if fq1 and fq2 and os.path.abspath(fq1) == os.path.abspath(fq2):
                    errors.append(f"Row {i}: fastq_1 and fastq_2 point to the same file: '{fq1}'")
            else:
                all_pe = False

            # ---- Strandedness validation ----
            if not strand:
                errors.append(f"Row {i}: Empty strandedness for sample '{sample}'")
            elif strand.lower() not in valid_strands:
                errors.append(
                    f"Row {i}: Invalid strandedness '{strand}' for sample '{sample}'. "
                    f"Must be one of: {', '.join(sorted(valid_strands))}"
                )

            # Track sample counts for replicate detection
            samples[sample] += 1

    # ---- Post-row checks ----
    if row_count == 0:
        errors.append("No data rows found (only header present)")

    # Mixed SE/PE check
    if not all_se and not all_pe:
        warnings.append(
            "Samplesheet contains a mix of single-end and paired-end samples. "
            "This is supported but verify this is intentional."
        )

    # Multi-lane / technical replicate reporting
    for sample_name, count in samples.items():
        if count > 1:
            warnings.append(
                f"Sample '{sample_name}' has {count} rows — "
                f"these will be merged as technical replicates"
            )

    return errors, warnings


def print_summary(filepath, errors, warnings, row_count):
    """Print formatted validation summary."""
    print()
    print("=" * 60)
    print(f"  Samplesheet Validation: {os.path.basename(filepath)}")
    print("=" * 60)
    print()

    # Count samples
    try:
        with open(filepath, 'r') as f:
            reader = csv.DictReader(f)
            samples = set()
            total_rows = 0
            for row in reader:
                total_rows += 1
                s = row.get('sample', '').strip()
                if s:
                    samples.add(s)
        print(f"  File:             {filepath}")
        print(f"  Total rows:       {total_rows}")
        print(f"  Unique samples:   {len(samples)}")
        if total_rows > len(samples):
            print(f"  Tech replicates:  {total_rows - len(samples)} rows will be merged")
    except Exception:
        pass

    if warnings:
        print(f"\n  ⚠️  WARNINGS ({len(warnings)}):")
        for w in warnings:
            print(f"     • {w}")

    if errors:
        print(f"\n  ❌ ERRORS ({len(errors)}):")
        for e in errors:
            print(f"     • {e}")
        print()
        print("  ❌ VALIDATION FAILED — fix errors above before running pipeline")
    else:
        print()
        print("  ✅ VALIDATION PASSED")

    print()
    print("=" * 60)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python validate_samplesheet.py <samplesheet.csv>")
        print()
        print("Validates samplesheet format for nf-core/rnaseq pipeline.")
        print("Each row represents a fastq file (single-end) or a pair of")
        print("fastq files (paired end). Rows with the same sample identifier")
        print("are considered technical replicates and merged automatically.")
        sys.exit(1)

    filepath = sys.argv[1]
    errors, warnings = validate(filepath)

    # Count rows for summary
    row_count = 0
    try:
        with open(filepath, 'r') as f:
            row_count = sum(1 for _ in f) - 1
    except Exception:
        pass

    print_summary(filepath, errors, warnings, row_count)

    sys.exit(1 if errors else 0)
