#!/bin/bash
#SBATCH --job-name=nfcore_test
#SBATCH --output=/home/ja581385/genomics_core/logs/system/test_%j.out
#SBATCH --error=/home/ja581385/genomics_core/logs/system/test_%j.err
#SBATCH --time=08:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G

# =============================================================================
# Validation test: Run nf-core/rnaseq test profile
#
# FIX: "Process requirement exceeds available CPUs -- req: 4; avail: 2"
#   The test profile runs with local executor (tasks run inside this job)
#   so we must request enough CPUs and memory for the most demanding task.
#   STAR alignment needs ~12 CPUs and ~36 GB RAM in the test [2]
#   We request 16 CPUs and 64 GB to cover all tasks comfortably.
#
#   For PRODUCTION runs, the institutional SLURM config submits each task
#   as its own SLURM job, so the head job only needs 2 CPUs [2][3].
# =============================================================================

set -euo pipefail

BASE="/home/ja581385/genomics_core"
TEST_DIR="${BASE}/tests/test_run_$(date +%Y%m%d_%H%M%S)"
PIPELINE_PATH="${BASE}/pipelines/nf-core/rnaseq-3.23.0/3_23_0"

# ---- Load environment ----
module unload java 2>/dev/null || true
module unload openjdk 2>/dev/null || true
source ${BASE}/bin/activate_genomics_core.sh
module load singularity 2>/dev/null || module load apptainer 2>/dev/null || true

echo "============================================="
echo "  nf-core/rnaseq Validation Test"
echo "============================================="
echo "  Job ID:       ${SLURM_JOB_ID}"
echo "  Node:         $(hostname)"
echo "  CPUs:         ${SLURM_CPUS_PER_TASK}"
echo "  Memory:       ${SLURM_MEM_PER_NODE:-unknown} MB"
echo "  Java:         $(java -version 2>&1 | grep -i version | head -1)"
echo "  Nextflow:     $(nextflow -version 2>&1 | grep version | head -1)"
echo "  Singularity:  $(singularity --version 2>/dev/null || apptainer --version 2>/dev/null)"
echo "  Pipeline:     ${PIPELINE_PATH}"
echo "  Output:       ${TEST_DIR}"
echo "============================================="
echo ""

# ---- Verify pipeline ----
echo "[Check 1] Verifying pipeline files..."
if [ -f "${PIPELINE_PATH}/main.nf" ]; then
    echo "  ✅ main.nf found"
else
    echo "  ❌ main.nf NOT found"
    exit 1
fi

# ---- Verify containers ----
echo ""
echo "[Check 2] Verifying Singularity containers..."
IMG_DIR="${BASE}/pipelines/nf-core/rnaseq-3.23.0/singularity-images"
IMG_COUNT=$(find ${IMG_DIR} -name "*.img" -type f 2>/dev/null | wc -l)
echo "  Container images: ${IMG_COUNT}"

# Also check central cache
CACHE_COUNT=$(find ${BASE}/singularity_cache -name "*.img" -type f 2>/dev/null | wc -l)
echo "  Central cache: ${CACHE_COUNT} images"

# ---- Create output directory ----
mkdir -p ${TEST_DIR}
cd ${TEST_DIR}

# ---- Run the test ----
echo ""
echo "============================================="
echo "[Step 3] Running nf-core/rnaseq test profile"
echo ""
echo "  The test profile uses the local executor, meaning all tasks"
echo "  run inside this SLURM job using the allocated ${SLURM_CPUS_PER_TASK} CPUs."
echo "  This tests the full pipeline: FASTQ QC → trimming → alignment"
echo "  → quantification → MultiQC report [1]"
echo "============================================="
echo ""

# Set max resources to match what SLURM allocated to this job
# This prevents "Process requirement exceeds available CPUs" errors [2]
nextflow run ${PIPELINE_PATH} \
    -profile test,singularity \
    --outdir ${TEST_DIR}/results \
    --max_cpus ${SLURM_CPUS_PER_TASK} \
    --max_memory "${SLURM_MEM_PER_NODE:-65536}.MB" \
    --max_time '4.h' \
    -work-dir ${BASE}/work/test_validation \
    -with-report ${TEST_DIR}/execution_report.html \
    -with-timeline ${TEST_DIR}/timeline.html \
    -with-trace ${TEST_DIR}/trace.txt \
    -resume \
    2>&1 | tee ${TEST_DIR}/test_run.log

EXIT_CODE=$?

echo ""
echo "============================================="
echo "  Pipeline Exit Code: ${EXIT_CODE}"
echo "============================================="

# ---- Verify outputs ----
echo ""
echo "[Step 4] Verifying outputs..."

# MultiQC report
MULTIQC=$(find ${TEST_DIR}/results -name "multiqc_report.html" 2>/dev/null | head -1)
if [ -n "${MULTIQC}" ]; then
    echo "  ✅ MultiQC report: FOUND"
    echo "     ${MULTIQC}"
else
    echo "  ❌ MultiQC report: NOT FOUND"
    find ${TEST_DIR}/results -name "*.html" 2>/dev/null | head -5 | sed 's/^/     /'
fi

# Gene count matrix - primary deliverable [1]
echo ""
echo "  Gene count files:"
COUNTS_FOUND=false
find ${TEST_DIR}/results -name "*gene_counts*" -o -name "*salmon.merged*" 2>/dev/null | \
    while read f; do
        SIZE=$(ls -lh "$f" | awk '{print $5}')
        echo "  ✅ ${SIZE}  $(basename $f)"
        COUNTS_FOUND=true
    done

# BAM files
BAMS=$(find ${TEST_DIR}/results -name "*.bam" 2>/dev/null | wc -l)
echo ""
echo "  BAM files: ${BAMS} found"

# Trace file summary
if [ -f "${TEST_DIR}/trace.txt" ]; then
    TOTAL=$(tail -n +2 ${TEST_DIR}/trace.txt | wc -l)
    COMPLETED=$(grep -c 'COMPLETED' ${TEST_DIR}/trace.txt 2>/dev/null || echo 0)
    FAILED=$(grep -c 'FAILED' ${TEST_DIR}/trace.txt 2>/dev/null || echo 0)
    CACHED=$(grep -c 'CACHED' ${TEST_DIR}/trace.txt 2>/dev/null || echo 0)
    echo ""
    echo "  Task summary:"
    echo "    Total:     ${TOTAL}"
    echo "    Completed: ${COMPLETED}"
    echo "    Cached:    ${CACHED}"
    echo "    Failed:    ${FAILED}"

    # Show any failed tasks
    if [ ${FAILED} -gt 0 ]; then
        echo ""
        echo "  Failed tasks:"
        grep 'FAILED' ${TEST_DIR}/trace.txt | awk -F'\t' '{print "    " $4 " (exit: " $7 ")"}' 2>/dev/null
    fi
fi

# ---- Final verdict ----
echo ""
echo "============================================="
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "  ✅ VALIDATION TEST PASSED"
    echo ""
    echo "  Your nf-core/rnaseq installation is fully verified!"
    echo "  You are ready to run real RNA-seq projects."
    echo ""
    echo "  Key outputs:"
    echo "    Results dir: ${TEST_DIR}/results/"
    echo "    MultiQC:     ${MULTIQC:-not found}"
    echo "    Report:      ${TEST_DIR}/execution_report.html"
    echo "    Timeline:    ${TEST_DIR}/timeline.html"
    echo "    Trace:       ${TEST_DIR}/trace.txt"
    echo ""
    echo "  Next steps:"
    echo "    1. Download reference genome:"
    echo "       ./scripts/reference_management/download_references.sh GRCh38"
    echo "    2. Build STAR index:"
    echo "       sbatch scripts/reference_management/build_star_index.sh GRCh38 149"
    echo "    3. Initialize your first project:"
    echo "       ./scripts/project_management/init_project.sh PROJ-2026-001 'Dr.Smith' GRCh38 'ja581385'"
else
    echo "  ❌ VALIDATION TEST FAILED (exit code: ${EXIT_CODE})"
    echo ""
    echo "  Check the log:"
    echo "    ${TEST_DIR}/test_run.log"
    echo ""
    echo "  Last 30 lines:"
    tail -30 ${TEST_DIR}/test_run.log
    echo ""
    echo "  If the error is resource-related, try increasing SLURM allocation."
    echo "  If container-related, check singularity_cache for missing images."
fi
echo "============================================="
