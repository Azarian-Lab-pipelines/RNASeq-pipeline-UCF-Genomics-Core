# 🧬 UCF Genomics Core Facility – RNA-seq Analysis Pipeline (short-read)

## Overview

This repository manages standardized, reproducible **bulk RNA-seq** processing using the nf-core/rnaseq pipeline on the Stokes HPC cluster.

**Core Technologies**

- **Pipeline** — nf-core/rnaseq **v3.23.0** (with selected updates & custom patches)
- **Workflow Engine** — Nextflow ≥23.10
- **Container Runtime** — Apptainer (Singularity-compatible)
- **Job Scheduler** — SLURM
- **Reference Genomes** — GRCh38, GRCm39
- **Quantification** — Salmon + STAR (primary), with optional StringTie / RSEM modes
- **Quality Control** — MultiQC, FastQC, QualiMap, Preseq, Picard, RSeQC, dupRadar

Designed for high-throughput operation with strict project isolation, audit trails, and centralized logging.

## Directory Structure

```text
genomics_core/
├── bin/                    # Environment activation & Nextflow wrapper
├── configs/                # nf-core/rnaseq profiles, custom modules,institutional defaults
│   ├── conf/
│   ├── modules/
│   └── profiles/
├── pipelines/              # Version-pinned nf-core/rnaseq installations
├── references/             # Genome indices, GTFs, Salmon indexes, igenomes cache
├── projects/
│   ├── active/             # Currently processing projects
│   ├── completed/          # Finished & delivered projects
│   └── failed/             # Projects that require intervention
├── scripts/
│   ├── project_management/ # init, archive, monitor, status reporting
│   ├── validation/         # samplesheet generation & validation
│   └── qc/                 # automated QC extraction & reporting
├── templates/              # Reusable project skeletons & default configs
├── docs/                   # SOPs, checklists, training slides, troubleshooting
├── logs/                   # Centralized Nextflow & SLURM logs (rotated)
├── tests/                  # Automated pipeline validation & mock datasets
└── archive/                # Long-term compressed project storage
```

## Quick Start – New RNA-seq Project

```bash
# 1. Activate the genomics core environment
source /home/ja581385/genomics_core/bin/activate_genomics_core.sh

# 2. Create new project (project ID, PI name, reference, analyst)
./scripts/project_management/init_project.sh \
    "PROJ-2025-042" \
    "Dr. XYZ Lab" \
    "GRCh38" \
    "Analyst name"

# 3. Move into project directory
cd projects/active/PROJ-2025-042

# 4. Stage FASTQ files (symlinks preferred)
ln -s /path/from/sequencer/*.fastq.gz data/fastq/

# 5. Generate & edit samplesheet
python ../../scripts/validation/generate_samplesheet.py \
    --input_dir data/fastq \
    --output samplesheet.csv

# → Open samplesheet.csv and add condition, replicate, other metadata.

# 6. Validate samplesheet
python ../../scripts/validation/validate_samplesheet.py samplesheet.csv

# 7. Launch pipeline (SLURM submission)
sbatch launch_pipeline.sh

# 8. Monitor progress (real-time or periodic)
../../scripts/project_management/monitor_runs.sh
# or watch -n 30 ../../scripts/project_management/monitor_runs.sh
```

## Key Features & Conventions

- **Project isolation** — each project gets its own Nextflow work/ directory
- **Immutable references** — pre-built indices stored in `/references/`
- **Centralized logging** — all runs logged to `logs/YYYY-MM/`
- **Automated QC extraction** — key metrics parsed into QC summary tables
- **Archival workflow** — moves project → `archive/` + lightweight tarball of results
- **Samplesheet validation** — enforces required columns, unique IDs, valid paths

## Important Scripts

| Script Path                                      | Purpose                                      |
|--------------------------------------------------|----------------------------------------------|
| `scripts/project_management/init_project.sh`     | Create new project structure & metadata      |
| `scripts/project_management/monitor_runs.sh`     | Show status of all active/completed runs     |
| `scripts/project_management/archive_project.sh`  | Archive project & create delivery tarball    |
| `scripts/validation/generate_samplesheet.py`     | Auto-detect FASTQs → draft samplesheet       |
| `scripts/validation/validate_samplesheet.py`     | Strict validation before pipeline launch     |
| `scripts/qc/extract_multiqc_metrics.py`          | Parse MultiQC JSON → tabular QC summary      |

## Contact & Support

For pipeline issues, project setup questions, or urgent failed runs:

**Jash Trivedi**  
Genomics Core Facility, University of Central Florida


Email: [ja581385@ucf.edu](mailto:ja581385@ucf.edu)


---
<img src="img/UCF_logo.png" alt="UCF Genomics Core Logo" width="120"/>

 [📧 **Email**](mailto:BSBSgenomicsCore@ucf.edu)

 [🌐 **Website**](https://med.ucf.edu/biomed/burnett-school-of-biomedical-sciences-research/core/genomics-core/)
