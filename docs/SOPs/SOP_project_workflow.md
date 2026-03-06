# Standard Operating Procedure (SOP)  
**Project Workflow – UCF Genomics Core**  
**RNA-seq Analysis Pipeline (short-read)**

**Document ID:** SOP-PROJ-WORKFLOW  
**Version:** 1.0  
**Last Updated:** March 2026  
**Owner:** UCF Genomics Core Team  
**Applies to:** All new bulk RNA-seq projects

## 1. Project Initialization

Create the project directory structure and metadata.

```bash
cd /home/ja581385/genomics_core

./scripts/project_management/init_project.sh \
    "PROJ-2025-XXX" \
    "PI/Lab Name" \
    "GRCh38" \
    "Analyst Name"
```

Replace:
- `PROJ-2025-XXX` with the actual project ID (e.g., `PROJ-2025-042`)
- `"PI/Lab Name"` with the principal investigator’s or lab's name
- `"Analyst Name"` with assigned analyst name

This script creates:
```
projects/active/PROJ-2025-XXX/
├── data/
│   └── fastq/
├── docs/
├── results/
├── qc_review/
└── scripts/          → symlink to ../genomics_core/scripts/
```

## 2. Data Staging

1. **Receive FASTQ files**  
   Obtain files from the sequencing core facility (secure FTP, Globus, external drive, etc.).

2. **Stage files in project directory**  
   - Preferred method: symbolic links (preserves original location & saves space)
   - Alternative: copy if symlinks are not feasible

   ```bash
   # Example using symlinks
   ln -s /path/from/sequencer/*.fastq.gz projects/active/PROJ-2025-XXX/data/fastq/
   ```

   Target location:  
   `projects/active/PROJ-2025-XXX/data/fastq/`

3. **Verify file integrity**  
   - Use provided checksums (MD5/SHA256) from sequencing facility when available
   - If no checksums provided, generate and store your own:

   ```bash
   cd projects/active/PROJ-2025-XXX
   find data/fastq/ -type f -name "*.fastq.gz" -exec md5sum {} \; \
       > data/fastq/checksums.md5
   ```

   Compare against facility-provided file if later received.

## 3. Samplesheet Preparation

1. **Auto-generate draft samplesheet**

   ```bash
   python scripts/validation/generate_samplesheet.py \
       --input_dir projects/active/PROJ-2025-XXX/data/fastq/ \
       --output     projects/active/PROJ-2025-XXX/samplesheet.csv
   ```

2. **Manually edit samplesheet.csv**  
   Open in spreadsheet editor or text editor and add/correct:
   - Sample names (unique, no spaces/special characters)
   - Condition / group
   - Replicate number
   - Library prep type (if needed)
   - Any other metadata required by downstream analysis

3. **Validate samplesheet**

   ```bash
   python scripts/validation/validate_samplesheet.py \
       projects/active/PROJ-2025-XXX/samplesheet.csv
   ```

   Resolve all errors and warnings before proceeding.

## 4. Pipeline Execution

```bash
cd projects/active/PROJ-2025-XXX

sbatch launch_pipeline.sh
```

- Monitor job with:
  ```bash
  squeue -u $USER
  sacct -j <jobid>
  tail -f slurm-*.out
  ```

## 5. Quality Control (QC) Review

After pipeline completion:

1. Open MultiQC report  
   `results/multiqc/multiqc_report.html`

2. Complete QC checklist  
   Edit: `qc_review/qc_checklist.md`

3. Key QC thresholds to verify:
   - Raw read quality — acceptable FastQC scores
   - Post-trimming adapter content < 0.1%
   - Overall mapping rate > 70–75% (ideally > 80%)
   - Properly paired alignment rate high
   - Low contamination (rRNA, bacterial, etc.)
   - PCA / sample clustering matches expected biological groups
   - No extreme outliers unless biologically explained

4. Document findings & decisions  
   Add notes to: `qc_review/qc_notes.md`

## 6. Data Delivery to PI/Lab

**Prepare delivery package:**

- Primary files:
  - Gene count matrix: `results/star_salmon/salmon.merged.gene_counts.tsv`
  - Transcript counts (optional): `results/star_salmon/salmon.merged.transcript_counts.tsv`
  - MultiQC report: `results/multiqc/multiqc_report.html`
  - QC checklist & notes: `qc_review/`

- Optional (if requested or agreed):
  - Normalized counts (CPM / TPM / vst)
  - DESeq2-ready tables
  - Preliminary differential expression results

**Transfer method** (use secure, institution-approved options):
- Box / OneDrive / Google Drive (shared link with password)
- Globus
- Encrypted external drive
- SFTP / rsync to PI’s server

**Notify PI/Lab** via email:
- Include link/access instructions
- Summarize QC status
- Mention any limitations or follow-up needed

## 7. Project Archival

After PI confirms receipt and satisfaction:

```bash
cd /home/ja581385/genomics_core

./scripts/project_management/archive_project.sh PROJ-2025-XXX
```

This typically:
- Moves project from `active/` to `archive/`
- Creates lightweight archive (metadata + logs + key results)
- Updates project tracking database (if implemented)



