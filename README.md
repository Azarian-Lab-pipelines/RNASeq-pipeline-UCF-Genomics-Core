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



## 🌐 Live Project Status Dashboard

Real-time overview of RNA-seq projects processed by the UCF Genomics Core Facility  
(nf-core/rnaseq • automated, reproducible analysis)

<div class="dashboard-container">
  <iframe 
    src="https://azarian-lab-pipelines.github.io/RNASeq-pipeline-UCF-Genomics-Core/"
    title="UCF Genomics Core – Live RNA-seq Project Dashboard"
    allowfullscreen
    loading="lazy"
    class="dashboard-iframe"
  ></iframe>
</div>

<p class="dashboard-footer">
  • Automatically updates when new data is committed • Search by project ID, PI or analyst • Shows status & runtime
  <br>
  <a href="https://azarian-lab-pipelines.github.io/RNASeq-pipeline-UCF-Genomics-Core/" target="_blank" rel="noopener noreferrer">
    Open dashboard in full window →
  </a>
</p>

<style>
  .dashboard-container {
    position: relative;
    width: 100%;
    max-width: 1400px;
    margin: 1.8rem auto;
    border: 2px solid #4ade80;
    border-radius: 16px;
    overflow: hidden;
    background: #0f172a;
    box-shadow: 0 10px 30px -10px rgba(74, 222, 128, 0.15);
    transition: all 0.3s ease;
  }

  .dashboard-container:hover {
    border-color: #22c55e;
    box-shadow: 0 15px 40px -12px rgba(74, 222, 128, 0.25);
  }

  .dashboard-iframe {
    width: 100%;
    height: clamp(600px, 75vh, 1000px);
    aspect-ratio: 16 / 10;
    border: none;
    display: block;
    background: #0f172a url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text x="50%" y="50%" font-size="12" text-anchor="middle" dy=".3em" fill="%23555">Loading dashboard...</text></svg>') center/80px no-repeat;
  }

  @media (max-width: 768px) {
    .dashboard-iframe {
      height: clamp(500px, 70vh, 800px);
      aspect-ratio: 4 / 5;
    }
  }

  @media (max-width: 480px) {
    .dashboard-iframe {
      height: 60vh;
    }
  }

  .dashboard-footer {
    text-align: center;
    font-size: 0.95rem;
    color: #94a3b8;
    margin-top: 1rem;
    line-height: 1.6;
  }

  .dashboard-footer a {
    color: #4ade80;
    text-decoration: none;
    font-weight: 500;
    transition: color 0.2s;
  }

  .dashboard-footer a:hover,
  .dashboard-footer a:focus {
    color: #22c55e;
    text-decoration: underline;
  }
</style>


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
