#!/bin/bash

# =============================================================================
# run_analysis.sh - Submit downstream RNA-seq analysis to SLURM
#
# Usage:
#   ./run_analysis.sh \
#     --counts /path/to/salmon.merged.gene_counts.tsv \
#     --metadata /path/to/samplesheet.csv \
#     --organism human \
#     --project "ProjectName" \
#     --pi "Dr. Smith" \
#     --outdir ./downstream_results
# =============================================================================

PIPELINE_DIR="/home/ja581385/genomics_core/downstream_rnaseq"

# Defaults
ORGANISM="human"
PROJECT="RNA-seq_Project"
PI="PI"
OUTDIR="./downstream_results"
COUNTS=""
METADATA=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --counts)    COUNTS="$2";   shift 2 ;;
        --metadata)  METADATA="$2"; shift 2 ;;
        --organism)  ORGANISM="$2"; shift 2 ;;
        --project)   PROJECT="$2";  shift 2 ;;
        --pi)        PI="$2";       shift 2 ;;
        --outdir)    OUTDIR="$2";   shift 2 ;;
        --help|-h)
            echo "RNA-seq Downstream Analysis Pipeline"
            echo ""
            echo "Usage:"
            echo "  $0 --counts <file> --metadata <file> [options]"
            echo ""
            echo "Required:"
            echo "  --counts     Gene count matrix from nf-core rnaseq"
            echo "  --metadata   Sample metadata CSV (sample_id, condition)"
            echo ""
            echo "Optional:"
            echo "  --organism   human (default) or mouse"
            echo "  --project    Project name (default: RNA-seq_Project)"
            echo "  --pi         PI name"
            echo "  --outdir     Output directory (default: ./downstream_results)"
            exit 0
            ;;
        *) echo "Unknown: $1. Use --help"; exit 1 ;;
    esac
done

if [[ -z "${COUNTS}" || -z "${METADATA}" ]]; then
    echo "ERROR: --counts and --metadata are required. Use --help."
    exit 1
fi

# =============================================
# FIX: Get absolute paths WITHOUT resolving
# symlinks. On this HPC, readlink -f converts
# /home/ja581385 -> /lustre/fs1/home/ja581385
# which breaks apptainer bind mounts.
# Use cd+pwd instead.
# =============================================
get_abs_path() {
    local target="$1"
    if [[ -d "$target" ]]; then
        (cd "$target" && pwd)
    elif [[ -f "$target" ]]; then
        local dir=$(cd "$(dirname "$target")" && pwd)
        echo "${dir}/$(basename "$target")"
    else
        echo "$target"
    fi
}

COUNTS=$(get_abs_path "$COUNTS")
METADATA=$(get_abs_path "$METADATA")

# For outdir, create it first then get absolute path
mkdir -p "$OUTDIR"
OUTDIR=$(get_abs_path "$OUTDIR")

if [[ ! -f "$COUNTS" ]]; then
    echo "ERROR: Counts file not found: $COUNTS"
    exit 1
fi

if [[ ! -f "$METADATA" ]]; then
    echo "ERROR: Metadata file not found: $METADATA"
    exit 1
fi

CONTAINER="${PIPELINE_DIR}/containers/rnaseq_report.sif"
if [[ ! -f "$CONTAINER" ]]; then
    echo "ERROR: Container not found: $CONTAINER"
    exit 1
fi

# Sanitize project name for filename
PROJECT_FILENAME=$(echo "${PROJECT}" | sed 's/ /_/g; s/[^a-zA-Z0-9_-]//g')

# Get absolute paths for dirs used inside SLURM script
COUNTS_DIR=$(dirname "${COUNTS}")
METADATA_DIR=$(dirname "${METADATA}")
BIN_DIR="${PIPELINE_DIR}/bin"
TEMPLATE_DIR="${PIPELINE_DIR}/templates"

# Create SLURM batch script
SLURM_SCRIPT="${OUTDIR}/slurm_downstream_$(date +%Y%m%d_%H%M%S).sh"

cat > "${SLURM_SCRIPT}" << SLURMEOF
#!/bin/bash
#SBATCH --job-name=rnaseq_downstream
#SBATCH --output=${OUTDIR}/downstream_%j.out
#SBATCH --error=${OUTDIR}/downstream_%j.err
#SBATCH --time=04:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --mail-type=ALL
#SBATCH --mail-user=ja581385@ucf.edu


set -euo pipefail

echo "============================================================"
echo "  RNA-seq Downstream Analysis Pipeline"
echo "============================================================"
echo "  Project:    ${PROJECT}"
echo "  PI:         ${PI}"
echo "  Organism:   ${ORGANISM}"
echo "  Counts:     ${COUNTS}"
echo "  Metadata:   ${METADATA}"
echo "  Output:     ${OUTDIR}"
echo "  Container:  ${CONTAINER}"
echo "  Started:    \$(date)"
echo "============================================================"
echo ""

module load apptainer 2>/dev/null || module load singularity 2>/dev/null || true

mkdir -p "${OUTDIR}"/{prepared_data,qc_results,de_results,enrichment,report}

run_r() {
    local script="\$1"
    shift
    echo ""
    echo "--- Running: \$(basename \$script) at \$(date) ---"
    apptainer exec \\
        --bind "${OUTDIR}:${OUTDIR}" \\
        --bind "${BIN_DIR}:${BIN_DIR}" \\
        --bind "${COUNTS_DIR}:${COUNTS_DIR}" \\
        --bind "${METADATA_DIR}:${METADATA_DIR}" \\
        --bind "${TEMPLATE_DIR}:${TEMPLATE_DIR}" \\
        "${CONTAINER}" \\
        Rscript "\${script}" "\$@"
    echo "--- Completed: \$(basename \$script) at \$(date) ---"
}

# ========================================
# Step 1: Prepare Data
# ========================================
echo "==== STEP 1/5: Data Preparation ===="
run_r "${BIN_DIR}/01_prepare_data.R" \\
    "${COUNTS}" \\
    "${METADATA}" \\
    "${ORGANISM}" \\
    "${OUTDIR}/prepared_data"

# ========================================
# Step 2: Quality Assessment
# ========================================
echo "==== STEP 2/5: Quality Assessment ===="
run_r "${BIN_DIR}/02_quality_assessment.R" \\
    "${OUTDIR}/prepared_data" \\
    "${OUTDIR}/qc_results"

# ========================================
# Step 3: Differential Expression
# ========================================
echo "==== STEP 3/5: Differential Expression ===="
run_r "${BIN_DIR}/03_differential_expression.R" \\
    "${OUTDIR}/prepared_data" \\
    "${OUTDIR}/de_results"

# ========================================
# Step 4: Functional Enrichment
# ========================================
echo "==== STEP 4/5: Functional Enrichment ===="
run_r "${BIN_DIR}/04_functional_enrichment.R" \\
    "${OUTDIR}/prepared_data" \\
    "${OUTDIR}/de_results" \\
    "${OUTDIR}/enrichment" \\
    "${ORGANISM}"

# ========================================
# Step 5: Render Report
#
# Quarto --output only accepts a filename,
# not a path. So we:
#   1. Copy templates to a workspace dir
#   2. cd into that dir
#   3. Render with filename only
#   4. Find and move the output html
# ========================================
echo "==== STEP 5/5: Report Generation ===="

REPORT_DIR="${OUTDIR}/report"
REPORT_WORKDIR="${REPORT_DIR}/workspace"
REPORT_FILENAME="${PROJECT_FILENAME}_report.html"

rm -rf "\${REPORT_WORKDIR}" 2>/dev/null || true
mkdir -p "\${REPORT_WORKDIR}"
cp -r "${TEMPLATE_DIR}"/* "\${REPORT_WORKDIR}/"

apptainer exec \\
    --bind "${OUTDIR}:${OUTDIR}" \\
    --bind "${BIN_DIR}:${BIN_DIR}" \\
    "${CONTAINER}" \\
    bash -c "
        cd \${REPORT_WORKDIR}
        quarto render report.qmd \\
            --to html \\
            --output \${REPORT_FILENAME} \\
            -P project_name:'${PROJECT}' \\
            -P pi_name:'${PI}' \\
            -P organism:'${ORGANISM}' \\
            -P data_dir:'${OUTDIR}/prepared_data' \\
            -P de_dir:'${OUTDIR}/de_results' \\
            -P enrichment_dir:'${OUTDIR}/enrichment' \\
            -P qc_dir:'${OUTDIR}/qc_results'
    "

# Find the rendered file wherever Quarto put it
# Could be in workspace root, or workspace/output/
FOUND_REPORT=""
for search_path in \\
    "\${REPORT_WORKDIR}/\${REPORT_FILENAME}" \\
    "\${REPORT_WORKDIR}/output/\${REPORT_FILENAME}" \\
    "\${REPORT_WORKDIR}/_output/\${REPORT_FILENAME}"; do
    if [[ -f "\${search_path}" ]]; then
        FOUND_REPORT="\${search_path}"
        break
    fi
done

if [[ -z "\${FOUND_REPORT}" ]]; then
    echo "WARNING: Could not find rendered report at expected location"
    echo "Searching workspace for any HTML files..."
    FOUND_REPORT=\$(find "\${REPORT_WORKDIR}" -name "*.html" -type f | head -1)
fi

if [[ -n "\${FOUND_REPORT}" ]]; then
    mv "\${FOUND_REPORT}" "\${REPORT_DIR}/\${REPORT_FILENAME}"
    echo "Report moved to: \${REPORT_DIR}/\${REPORT_FILENAME}"
else
    echo "ERROR: No HTML report found after rendering"
    echo "Contents of workspace:"
    find "\${REPORT_WORKDIR}" -type f
fi

# Copy downloadable files
cp "${OUTDIR}/de_results"/*.csv "\${REPORT_DIR}/" 2>/dev/null || true

# Clean up workspace
rm -rf "\${REPORT_WORKDIR}"

echo ""
echo "============================================================"
echo "  Pipeline Complete!"
echo "============================================================"
echo "  Report: \${REPORT_DIR}/\${REPORT_FILENAME}"
echo "  DE:     ${OUTDIR}/de_results/"
echo "  Enrich: ${OUTDIR}/enrichment/"
echo "  Done:   \$(date)"
echo "============================================================"

ls -lh "\${REPORT_DIR}/\${REPORT_FILENAME}" 2>/dev/null || echo "WARNING: Report file not found"
SLURMEOF

echo "Submitting downstream analysis job..."
echo "  Counts:    ${COUNTS}"
echo "  Metadata:  ${METADATA}"
echo "  Organism:  ${ORGANISM}"
echo "  Project:   ${PROJECT}"
echo "  Output:    ${OUTDIR}"
echo ""

sbatch "${SLURM_SCRIPT}"

echo ""
echo "Monitor: squeue -u $(whoami)"
echo "Logs:    ${OUTDIR}/downstream_*.out"
