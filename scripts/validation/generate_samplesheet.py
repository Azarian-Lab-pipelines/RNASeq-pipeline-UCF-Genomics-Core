#!/usr/bin/env python3
"""
Auto-generate an nf-core/rnaseq samplesheet from a directory of FASTQ files.

Scans the input directory for .fastq.gz files, identifies pairs by
common naming patterns, and generates a CSV samplesheet ready for
the nf-core/rnaseq pipeline.

Supported FASTQ naming patterns:
  - Illumina BCL2FASTQ: SampleName_S1_L001_R1_001.fastq.gz
  - Simple paired:       SampleName_R1.fastq.gz / SampleName_R2.fastq.gz
  - Underscore style:    SampleName_1.fastq.gz / SampleName_2.fastq.gz
  - Dot separated:       SampleName.R1.fastq.gz / SampleName.R2.fastq.gz

Multi-lane samples are detected automatically — each lane becomes a
separate row with the same sample name. The pipeline merges rows with
the same sample identifier as technical replicates.

Usage:
    python generate_samplesheet.py --input_dir <FASTQ_DIR> --output <CSV>

Options:
    --input_dir       Directory containing FASTQ files
    --output          Output samplesheet CSV path
    --strandedness    Strandedness for all samples (default: auto)
    --platform        Sequencing platform (default: ILLUMINA)
    --recursive       Search subdirectories for FASTQ files
    --single_end      Force single-end mode (ignore R2 files)

Examples:
    python generate_samplesheet.py --input_dir data/fastq/ --output samplesheet.csv
    python generate_samplesheet.py --input_dir /data/run1/ --output ss.csv --recursive
"""

import argparse
import os
import re
import csv
from collections import defaultdict

def find_fastqs(input_dir, recursive=False):
    """Find and pair FASTQ files in the given directory."""
    
    # Collect all fastq.gz files
    fastq_files = []
    if recursive:
        for root, dirs, files in os.walk(input_dir):
            for f in files:
                if f.endswith('.fastq.gz') or f.endswith('.fq.gz'):
                    fastq_files.append(os.path.join(root, f))
    else:
        for f in os.listdir(input_dir):
            if f.endswith('.fastq.gz') or f.endswith('.fq.gz'):
                fastq_files.append(os.path.join(input_dir, f))

    fastq_files.sort()

    # Pair files by sample name and read number
    samples = defaultdict(lambda: {'R1': None, 'R2': None, 'sample': None})

    for filepath in fastq_files:
        filename = os.path.basename(filepath)
        full_path = os.path.abspath(filepath)

        # Pattern 1: Illumina BCL2FASTQ
        # SampleName_S1_L001_R1_001.fastq.gz
        match = re.match(
            r'^(.+?)(_S\d+)?(_L\d+)?[_.]R([12])(?:_\d+)?\.(?:fastq|fq)\.gz$',
            filename
        )

        if not match:
            # Pattern 2: Simple paired
            # SampleName_R1.fastq.gz or SampleName_1.fastq.gz
            match = re.match(
                r'^(.+?)[_.](?:R)?([12])\.(?:fastq|fq)\.gz$',
                filename
            )
            if match:
                sample_name = match.group(1)
                read_num = match.group(2)
                # Use full filename minus read designation as unique key
                pair_key = re.sub(r'[_.](?:R)?[12]\.(?:fastq|fq)\.gz$', '', filename)
            else:
                # Cannot parse — skip with warning
                print(f"  WARNING: Cannot parse filename, skipping: {filename}")
                continue
        else:
            sample_name = match.group(1)
            read_num = match.group(4)
            # Reconstruct pair key preserving lane info for multi-lane
            pair_key = re.sub(r'[_.]R[12](?:_\d+)?\.(?:fastq|fq)\.gz$', '', filename)

        # Clean sample name: remove trailing lane/sample designators for grouping
        # But keep them in the pair_key for unique identification
        clean_sample = re.sub(r'_S\d+$', '', sample_name)
        clean_sample = re.sub(r'_L\d+$', '', clean_sample)

        if read_num == '1':
            samples[pair_key]['R1'] = full_path
            samples[pair_key]['sample'] = clean_sample
        elif read_num == '2':
            samples[pair_key]['R2'] = full_path
            if samples[pair_key]['sample'] is None:
                samples[pair_key]['sample'] = clean_sample

    return samples


def write_samplesheet(samples, output_file, strandedness='auto',
                      platform='ILLUMINA', single_end=False):
    """Write samplesheet CSV file."""

    # Sort by sample name for consistent output
    sorted_keys = sorted(samples.keys(), key=lambda k: (samples[k]['sample'] or '', k))

    written = 0
    skipped = 0

    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['sample', 'fastq_1', 'fastq_2', 'strandedness', 'seq_platform'])

        for key in sorted_keys:
            s = samples[key]
            sample_name = s.get('sample', 'UNKNOWN')
            r1 = s.get('R1', '')
            r2 = s.get('R2', '') if not single_end else ''

            if not r1:
                print(f"  WARNING: No R1 found for pair key '{key}', skipping")
                skipped += 1
                continue

            writer.writerow([
                sample_name,
                r1,
                r2,
                strandedness,
                platform
            ])
            written += 1

    return written, skipped


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Auto-generate nf-core/rnaseq samplesheet from FASTQ directory'
    )
    parser.add_argument('--input_dir', required=True,
                        help='Directory containing FASTQ files')
    parser.add_argument('--output', required=True,
                        help='Output samplesheet CSV path')
    parser.add_argument('--strandedness', default='auto',
                        choices=['auto', 'forward', 'reverse', 'unstranded'],
                        help='Strandedness for all samples (default: auto)')
    parser.add_argument('--platform', default='ILLUMINA',
                        help='Sequencing platform (default: ILLUMINA)')
    parser.add_argument('--recursive', action='store_true',
                        help='Search subdirectories for FASTQ files')
    parser.add_argument('--single_end', action='store_true',
                        help='Force single-end mode (ignore R2 files)')
    args = parser.parse_args()

    # Validate input directory
    if not os.path.isdir(args.input_dir):
        print(f"ERROR: Directory not found: {args.input_dir}")
        exit(1)

    print()
    print("=" * 60)
    print("  Generating nf-core/rnaseq samplesheet")
    print("=" * 60)
    print(f"  Input directory: {args.input_dir}")
    print(f"  Recursive: {args.recursive}")
    print(f"  Single-end: {args.single_end}")
    print(f"  Strandedness: {args.strandedness}")
    print(f"  Platform: {args.platform}")
    print()

    # Find and pair FASTQs
    samples = find_fastqs(args.input_dir, args.recursive)

    if not samples:
        print("ERROR: No FASTQ files found in the specified directory.")
        print(f"  Searched: {os.path.abspath(args.input_dir)}")
        print("  Expected: *.fastq.gz or *.fq.gz files")
        exit(1)

    # Count unique sample names
    unique_samples = set(s['sample'] for s in samples.values() if s['sample'])

    # Write samplesheet
    written, skipped = write_samplesheet(
        samples, args.output, args.strandedness, args.platform, args.single_end
    )

    # Summary
    print(f"  FASTQ pairs found:  {len(samples)}")
    print(f"  Unique samples:     {len(unique_samples)}")
    print(f"  Rows written:       {written}")
    if skipped:
        print(f"  Rows skipped:       {skipped}")

    # Detect multi-lane samples
    sample_counts = defaultdict(int)
    for s in samples.values():
        if s['sample']:
            sample_counts[s['sample']] += 1

    multi_lane = {k: v for k, v in sample_counts.items() if v > 1}
    if multi_lane:
        print()
        print("  Multi-lane samples detected (will be merged as technical replicates):")
        for name, count in sorted(multi_lane.items()):
            print(f"    {name}: {count} lanes")

    print()
    print(f"  ✅ Samplesheet written: {args.output}")
    print()
    print("  Next step: Validate the samplesheet")
    print(f"    python validate_samplesheet.py {args.output}")
    print()
    print("=" * 60)
