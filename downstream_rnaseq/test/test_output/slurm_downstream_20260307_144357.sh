#!/bin/bash
#SBATCH --job-name=rnaseq_downstream
#SBATCH --output=/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/downstream_%j.out
#SBATCH --error=/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/downstream_%j.err
#SBATCH --time=08:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=8
#SBATCH --mail-type=ALL
#SBATCH --mail-user=ja581385@ucf.edu

set -euo pipefail

echo "============================================================"
echo "  RNA-seq Downstream Analysis Pipeline"
echo "============================================================"
echo "  Project:    Test_Run"
echo "  PI:         PI"
echo "  Organism:   human"
echo "  Counts:     /lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/testdata/salmon.merged.gene_counts.tsv"
echo "  Metadata:   /lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/testdata/samplesheet.csv"
echo "  Output:     /lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output"
echo "  Container:  /home/ja581385/genomics_core/downstream_rnaseq/containers/rnaseq_report.sif"
echo "  Started:    $(date)"
echo "============================================================"
echo ""

# Load apptainer
module load apptainer 2>/dev/null || module load singularity 2>/dev/null || true

PIPELINE_DIR="/home/ja581385/genomics_core/downstream_rnaseq"
CONTAINER="/home/ja581385/genomics_core/downstream_rnaseq/containers/rnaseq_report.sif"
BIN_DIR="/home/ja581385/genomics_core/downstream_rnaseq/bin"
TEMPLATE_DIR="/home/ja581385/genomics_core/downstream_rnaseq/templates"

# Create output subdirectories
mkdir -p "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output"/{prepared_data,qc_results,de_results,enrichment,report}

# Helper function
run_r() {
    local script="$1"
    shift
    echo ""
    echo "--- Running: $(basename $script) at $(date) ---"
    apptainer exec \
        --bind "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output:/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output" \
        --bind "${BIN_DIR}:${BIN_DIR}" \
        --bind "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/testdata:/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/testdata" \
        --bind "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/testdata:/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/testdata" \
        --bind "${TEMPLATE_DIR}:${TEMPLATE_DIR}" \
        "${CONTAINER}" \
        Rscript "${script}" "$@"
    echo "--- Completed: $(basename $script) at $(date) ---"
}

# ========================================
# Step 1: Prepare Data
# ========================================
echo "==== STEP 1/5: Data Preparation ===="
run_r "${BIN_DIR}/01_prepare_data.R" \
    "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/testdata/salmon.merged.gene_counts.tsv" \
    "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/testdata/samplesheet.csv" \
    "human" \
    "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/prepared_data"

# ========================================
# Step 2: Quality Assessment
# ========================================
echo "==== STEP 2/5: Quality Assessment ===="
run_r "${BIN_DIR}/02_quality_assessment.R" \
    "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/prepared_data" \
    "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/qc_results"

# ========================================
# Step 3: Differential Expression
# ========================================
echo "==== STEP 3/5: Differential Expression ===="
run_r "${BIN_DIR}/03_differential_expression.R" \
    "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/prepared_data" \
    "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/de_results"

# ========================================
# Step 4: Functional Enrichment
# ========================================
echo "==== STEP 4/5: Functional Enrichment ===="
run_r "${BIN_DIR}/04_functional_enrichment.R" \
    "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/prepared_data" \
    "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/de_results" \
    "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/enrichment" \
    "human"

# ========================================
# Step 5: Render Report
# ========================================
echo "==== STEP 5/5: Report Generation ===="

REPORT_WORKDIR="/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/report_workspace"
mkdir -p "${REPORT_WORKDIR}"
cp -r "${TEMPLATE_DIR}"/* "${REPORT_WORKDIR}/"

apptainer exec \
    --bind "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output:/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output" \
    --bind "${BIN_DIR}:${BIN_DIR}" \
    --bind "${REPORT_WORKDIR}:${REPORT_WORKDIR}" \
    "${CONTAINER}" \
    bash -c "
        cd ${REPORT_WORKDIR}
        quarto render report.qmd \
            --to html \
            --output '/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/report/Test_Run_report.html' \
            -P project_name:'Test_Run' \
            -P pi_name:'PI' \
            -P organism:'human' \
            -P data_dir:'/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/prepared_data' \
            -P de_dir:'/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/de_results' \
            -P enrichment_dir:'/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/enrichment' \
            -P qc_dir:'/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/qc_results'
    "

cp "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/de_results"/*.csv "/lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/report/" 2>/dev/null || true
rm -rf "${REPORT_WORKDIR}"

echo ""
echo "============================================================"
echo "  Pipeline Complete!"
echo "============================================================"
echo "  Report: /lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/report/Test_Run_report.html"
echo "  DE:     /lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/de_results/"
echo "  Enrich: /lustre/fs1/home/ja581385/genomics_core/downstream_rnaseq/test/test_output/enrichment/"
echo "  Done:   $(date)"
echo "============================================================"
