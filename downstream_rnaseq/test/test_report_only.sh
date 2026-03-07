#!/bin/bash
#SBATCH --job-name=test_report
#SBATCH --output=test_report_%j.out
#SBATCH --error=test_report_%j.err
#SBATCH --time=01:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=4
#SBATCH --partition=normal
#SBATCH --mail-type=ALL
#SBATCH --mail-user=ja581385@ucf.edu

set -euo pipefail

module load apptainer 2>/dev/null || module load singularity 2>/dev/null || true

PIPELINE_DIR="/home/ja581385/genomics_core/downstream_rnaseq"
CONTAINER="${PIPELINE_DIR}/containers/rnaseq_report.sif"
OUTDIR="/home/ja581385/genomics_core/downstream_rnaseq/test/test_output"
TEMPLATE_DIR="${PIPELINE_DIR}/templates"
BIN_DIR="${PIPELINE_DIR}/bin"

REPORT_DIR="${OUTDIR}/report"
REPORT_WORKDIR="${REPORT_DIR}/workspace"
REPORT_FILENAME="Test_Run_report.html"

echo "=== Testing report generation ==="

# Check inputs exist
for f in prepared_data/count_matrix.rds qc_results/qc_results.rds de_results/de_results.rds enrichment/enrichment_results.rds; do
    if [[ -f "${OUTDIR}/${f}" ]]; then
        echo "  OK: ${f}"
    else
        echo "  MISSING: ${f}"
        exit 1
    fi
done

# Clean workspace
rm -rf "${REPORT_WORKDIR}" 2>/dev/null || true
mkdir -p "${REPORT_WORKDIR}"
cp -r "${TEMPLATE_DIR}"/* "${REPORT_WORKDIR}/"

echo ""
echo "  Rendering report..."
echo "  Working dir: ${REPORT_WORKDIR}"
echo ""

apptainer exec \
    --bind "${OUTDIR}:${OUTDIR}" \
    --bind "${BIN_DIR}:${BIN_DIR}" \
    --bind "${REPORT_WORKDIR}:${REPORT_WORKDIR}" \
    "${CONTAINER}" \
    bash -c "
        cd ${REPORT_WORKDIR}
        echo 'PWD:' \$(pwd)
        echo 'Files:' \$(ls)
        quarto render report.qmd \
            --to html \
            --output ${REPORT_FILENAME} \
            -P project_name:'Test_Run' \
            -P pi_name:'PI' \
            -P organism:'human' \
            -P data_dir:'${OUTDIR}/prepared_data' \
            -P de_dir:'${OUTDIR}/de_results' \
            -P enrichment_dir:'${OUTDIR}/enrichment' \
            -P qc_dir:'${OUTDIR}/qc_results'
    "

echo ""
echo "  Searching for rendered report..."
find "${REPORT_WORKDIR}" -name "*.html" -type f

# Find and move report
FOUND=""
for p in \
    "${REPORT_WORKDIR}/${REPORT_FILENAME}" \
    "${REPORT_WORKDIR}/output/${REPORT_FILENAME}"; do
    if [[ -f "$p" ]]; then
        FOUND="$p"
        break
    fi
done

if [[ -z "$FOUND" ]]; then
    FOUND=$(find "${REPORT_WORKDIR}" -name "*.html" -type f | head -1)
fi

if [[ -n "$FOUND" ]]; then
    mv "$FOUND" "${REPORT_DIR}/${REPORT_FILENAME}"
    echo ""
    echo "=== SUCCESS ==="
    echo "Report: ${REPORT_DIR}/${REPORT_FILENAME}"
    ls -lh "${REPORT_DIR}/${REPORT_FILENAME}"
else
    echo ""
    echo "=== FAILED: No HTML report found ==="
    find "${REPORT_WORKDIR}" -type f | head -20
fi

rm -rf "${REPORT_WORKDIR}"
