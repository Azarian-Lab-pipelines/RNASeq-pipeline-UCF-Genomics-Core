# RNA-seq Downstream Analysis & Interactive Reporting Pipeline

**Bioinformatics Core Facility – Automated RNA-seq Downstream Analysis**  
**Version:** 1.0.0  
**Last Updated:** March 2026  
**Author:** UCF Genomics Core Facility  
**Pipeline Location:** `/home/ja581385/genomics_core/downstream_rnaseq/`

---

## Table of Contents

1. [Overview](#overview)
2. [What This Pipeline Does](#what-this-pipeline-does)
3. [Supported Designs](#supported-experimental-designs)
4. [Directory Structure](#directory-structure)
5. [Prerequisites](#prerequisites)
6. [Quick Start](#quick-start)
7. [Detailed Usage](#detailed-usage)
8. [Input Requirements](#input-file-requirements)
9. [Pipeline Steps](#pipeline-steps-explained)
10. [Output Structure](#output-files-and-directory-structure)
11. [Interactive Report Features](#interactive-report-features)
12. [Customization](#customization-guide)
13. [Troubleshooting](#troubleshooting)
14. [Adding a New Organism](#adding-a-new-organism)
15. [Running on Real Data – Example](#running-on-real-data)
16. [FAQ](#faq)
17. [Contact](#contact)

---

## Overview

This pipeline takes **nf-core/rnaseq** output (STAR + Salmon) and automatically performs:

- Quality control and exploratory analysis
- Differential expression with **DESeq2** (with apeglm shrinkage)
- Functional enrichment (GO, KEGG, Reactome, GSEA Hallmark)
- Generation of a **self-contained interactive HTML report** using Quarto + Plotly + crosstalk

The report is inspired by high-quality commercial RNA-seq reporting services and is designed to be usable by non-bioinformaticians.

**One command → full analysis + beautiful interactive report.**

---

## What This Pipeline Does

```
nf-core/rnaseq output          This Pipeline                     Final Deliverable
───────────────────────►        ───────────────────────────►      ───────────────────────
Gene count matrix (TSV)         1. Data Preparation               Interactive HTML Report
Sample metadata (CSV)           2. Quality Assessment             featuring:
                                3. DESeq2 DE Analysis             • Volcano plots (interactive)
                                4. Enrichment (GO/KEGG/Reactome)  • Pathway bar plots + tables
                                5. Quarto HTML Report             • PCA, heatmaps, correlation
                                                                  • Searchable gene & pathway tables
                                                                  • Downloadable CSVs
```

---

## Supported Experimental Designs

The pipeline **automatically detects** the design from the `condition` column (and optional `batch`):

| Design Type       | Example Conditions                     | Design Formula             | Contrasts Generated          |
|-------------------|----------------------------------------|----------------------------|------------------------------|
| Two-condition     | Control, Treatment                     | `~ condition`              | 1 contrast                   |
| Multi-condition   | Control, DrugA, DrugB, DrugC           | `~ condition`              | All pairwise                 |
| Batch-corrected   | Conditions + batch                     | `~ batch + condition`      | All pairwise                 |
| Time-series       | Day0, Day1, Day3, Day7                 | `~ condition`              | All pairwise (or customize)  |

**Reference level auto-detection** looks for:  
`Control`, `Ctrl`, `WT`, `Wildtype`, `Untreated`, `DMSO`, `Vehicle`, `Baseline`, `Scramble`, `Day0`, `T0`  
→ Falls back to **first condition alphabetically** if none found.

Override via `analysis_config.yml` (see Customization).

---

## Directory Structure

```
downstream_rnaseq/
├── run_analysis.sh               # ★ Main entry point
├── containers/
│   ├── rnaseq_report.sif         # Apptainer container (~3 GB)
│   ├── rnaseq_report_v5_fix.def
│   └── build_container_v5_fix.sh
├── bin/                          # Core analysis scripts
│   ├── 01_prepare_data.R
│   ├── 02_quality_assessment.R
│   ├── 03_differential_expression.R
│   ├── 04_functional_enrichment.R
│   └── utils/
│       ├── annotation_utils.R
│       ├── contrast_utils.R
│       ├── enrichment_utils.R
│       └── plot_utils.R
├── templates/                    # Quarto report template
│   ├── report.qmd
│   ├── _quarto.yml
│   ├── css/custom.css
│   └── js/linked_plots.js
├── test/
│   ├── testdata/
│   ├── test_report_only.sh
│   └── create_test_data.R
├── configs/                      # (optional)
└── docs/
```

---

## Prerequisites

**On the HPC:**

- Apptainer / Singularity (`module load apptainer`)
- SLURM scheduler
- Container image: `containers/rnaseq_report.sif`

**Inside the container (no need to install):**

- R 4.4.1 + >50 packages (DESeq2, clusterProfiler, ReactomePA, fgsea, plotly, DT, crosstalk, Quarto 1.5+)

Quick test:

```bash
module load apptainer
apptainer exec containers/rnaseq_report.sif R -e "library(DESeq2); cat('OK\n')"
apptainer exec containers/rnaseq_report.sif quarto --version
```

---

## Quick Start

```bash
cd /home/ja581385/genomics_core/downstream_rnaseq

./run_analysis.sh \
    --counts  /path/to/star_salmon/salmon.merged.gene_counts.tsv \
    --metadata /path/to/samplesheet.csv \
    --organism human \
    --project "My_KO_vs_WT_Study" \
    --pi "Dr. Jane Smith" \
    --outdir /path/to/output_directory
```

Monitor:

```bash
squeue -u $USER
tail -f /path/to/output_directory/downstream_*.out
```

---

## Detailed Usage – Command Line Options

```bash
./run_analysis.sh [OPTIONS]

Required:
  --counts      Gene count matrix (salmon.merged.gene_counts.tsv)
  --metadata    Sample metadata CSV (sample_id, condition, [batch])

Optional:
  --organism    human | mouse               (default: human)
  --project     Project name in report      (default: RNA-seq_Project)
  --pi          PI name in report           (default: PI)
  --outdir      Output folder               (default: ./downstream_results)
  --help
```

---

## Input File Requirements

### 1. Gene Count Matrix (from nf-core/rnaseq)

- File: `star_salmon/salmon.merged.gene_counts.tsv`
- Format: tab-separated, first column `gene_id` (± `gene_name`), then sample columns

### 2. Metadata CSV (you create this)

**Required columns:**

| Column     | Description                        | Example      |
|------------|------------------------------------|--------------|
| sample_id  | Must match count matrix columns    | WT_rep1      |
| condition  | Experimental group                 | Control      |

**Optional / recognized columns:**

| Column   | Effect                              |
|----------|-------------------------------------|
| batch    | Triggers `~batch + condition`       |
| replicate| Shown in report metadata table      |

Alternative names accepted: `sample`, `SampleID`, `group`, `treatment`, `Treatment`

---

## Pipeline Steps Explained

| Step | Script                        | Main Tasks                                                                 |
|------|-------------------------------|----------------------------------------------------------------------------|
| 1    | `01_prepare_data.R`           | Load, clean, annotate (Ensembl → Symbol), detect design & contrasts       |
| 2    | `02_quality_assessment.R`     | VST, PCA, correlation heatmap, library sizes, top variable genes          |
| 3    | `03_differential_expression.R`| DESeq2, apeglm shrinkage, all contrasts, normalized counts                |
| 4    | `04_functional_enrichment.R`  | ORA: GO/KEGG/Reactome, GSEA: Hallmark                                     |
| 5    | Quarto (`report.qmd`)         | Renders interactive self-contained HTML report                            |

---

## Output Files and Directory Structure

```
<outdir>/
├── prepared_data/
│   ├── count_matrix.rds
│   ├── metadata.rds
│   ├── gene_annotation.rds
│   ├── design_info.rds
│   └── data_summary.json
├── qc_results/
│   └── qc_results.rds
├── de_results/
│   ├── de_results.rds
│   ├── DE_*.csv               (one per contrast)
│   ├── DE_summary.csv
│   └── normalized_counts.csv
├── enrichment/
│   ├── enrichment_results.rds
│   └── <contrast_name>/
│       ├── GO_BP.csv
│       ├── GO_MF.csv
│       ├── GO_CC.csv
│       ├── KEGG.csv
│       ├── Reactome.csv
│       └── GSEA_Hallmark.csv
├── report/
│   └── <project_name>_report.html     ← ★ Deliver this file ★
├── downstream_<jobid>.out
└── downstream_<jobid>.err
```

---

## Interactive Report Features

**Key sections:**

- Project & sample overview
- Data quality (PCA, correlation, library size, top variable genes)
- Differential expression (per contrast: volcano, MA, top genes heatmap, searchable table)
- Pathway analysis (GO/KEGG/Reactome bar plots, GSEA Hallmark, combined table)
- Gene explorer (expression boxplots, searchable table)
- Methods & downloads

**Interactivity highlights:**

- Hover info on volcano/enrichment/PCA/heatmap
- Click-to-zoom, drag-to-select
- Sort/filter/search tables
- Cross-highlighting: pathway genes ↔ volcano points
- Download filtered tables as CSV/Excel
- Save plots as PNG/SVG

---

## Customization Guide (most common changes)

| Goal                              | File to edit                                 | Location                             |
|-----------------------------------|----------------------------------------------|--------------------------------------|
| Change colors/fonts               | `custom.css`                                 | `templates/css/`                     |
| Add/remove report sections        | `report.qmd`                                 | `templates/`                         |
| Change significance thresholds    | `03_differential_expression.R`               | `bin/`                               |
| Override reference level          | Create `analysis_config.yml` next to metadata| same dir as `--metadata`             |
| Add new organism                  | `annotation_utils.R`                         | `bin/utils/`                         |
| Change SLURM resources            | `#SBATCH` lines in `run_analysis.sh`         | root                                 |
| Add facility logo                 | Place `logo.png` → edit YAML in `report.qmd` | `templates/assets/`                  |

**Example: override reference level**

```yaml
# analysis_config.yml (place beside metadata.csv)
reference_level: "DMSO"
design_formula: "~ batch + condition"
```

---

## Troubleshooting – Quick Checklist

- Container missing? → `ls containers/rnaseq_report.sif`
- Windows line endings? → `sed -i 's/\r$//' run_analysis.sh`
- Sample names mismatch? → Check exact match with `head -1 counts.tsv`
- Low annotation? → Wrong `--organism` selected
- Job OOM? → Increase `#SBATCH --mem=...` in `run_analysis.sh`
- No enrichment? → Test data uses fake IDs; real data should work

Logs:

```bash
tail -n 200 downstream_*.out
grep -i "error\|warn\|fatal" downstream_*.err
```

---

## Adding a New Organism (e.g. rat)

In `bin/utils/annotation_utils.R`:

```r
} else if (organism == "rat") {
    library(org.Rn.eg.db)
    return(list(
        orgdb         = org.Rn.eg.db,
        kegg_organism = "rno",
        reactome_organism = "rat",
        msigdb_species = "Rattus norvegicus"
    ))
}
```

Then use `--organism rat`

---

## Running on Real Data – Minimal Example

```bash
# 1. Prepare metadata
cat > metadata.csv << EOF
sample_id,condition
WT_1,Control
WT_2,Control
WT_3,Control
KO_1,Knockout
KO_2,Knockout
KO_3,Knockout
EOF

# 2. Run
./run_analysis.sh \
    --counts /data/.../salmon.merged.gene_counts.tsv \
    --metadata metadata.csv \
    --organism human \
    --project "CRISPR_KO_2026" \
    --pi "Dr. Elena Martinez" \
    --outdir results/downstream
```

Deliver: `results/downstream/report/*_report.html` (single file)

---

## FAQ

**Q:** Multiple projects at once?  
**A:** Yes — each run submits an independent SLURM job.

**Q:** Single-end data?  
**A:** Yes — only needs the Salmon gene count matrix.

**Q:** No enrichment with test data?  
**A:** Normal — test data uses fake gene IDs.

**Q:** Share report?  
**A:** Just send the `.html` file — fully offline & self-contained.

**Q:** Raw DESeq2 object?  
**A:** `<outdir>/de_results/de_results.rds` → `dds <- readRDS(...)$dds`

---

## Contact

Genomics Core Facility  
Pipeline location: `/home/ja581385/genomics_core/downstream_rnaseq/`

For bugs, feature requests, or support — please open an issue or email the core
