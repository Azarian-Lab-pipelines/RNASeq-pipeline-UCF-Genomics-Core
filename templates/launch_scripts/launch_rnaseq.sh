#!/bin/bash
#SBATCH --job-name=nfcore__PROJECT_ID__
#SBATCH --output=logs/slurm_nextflow_%j.out
#SBATCH --error=logs/slurm_nextflow_%j.err
#SBATCH --time=96:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --mail-type=ALL
#SBATCH --mail-user=ja581385@ucf.edu
# =============================================================================
# nf-core/rnaseq v3.23.0 Launch Script
#
# Project: __PROJECT_ID__
# PI: __PI_NAME__
# Analyst: __ANALYST__
# Date: __DATE__
#
# HOW THIS WORKS:
#   This is the NEXTFLOW HEAD JOB [2]. It submits a low resource but
#   long running batch job that controls the Nextflow workflow.
#   All pipeline processes (STAR, Salmon, FastQC, etc.) are submitted
#   by Nextflow as SEPARATE SLURM jobs with their own dedicated
#   resources defined in slurm_hpc.config.
#
#   The head job only needs 2 CPUs and 8 GB RAM because it only
#   manages the workflow graph — it does not run any analysis tasks.
#
# USAGE:
#   cd /home/ja581385/genomics_core/projects/active/__PROJECT_ID__
#   sbatch launch_pipeline.sh
#
# MONITOR:
#   squeue -u ja581385                         # All your jobs
#   tail -f logs/slurm_nextflow_<JOBID>.out    # Nextflow output
#   tail -f logs/nextflow_run_*.log            # Pipeline log
#
# RESUME AFTER FAILURE:
#   The -resume flag is included by default. If the pipeline fails,
#   fix the issue and simply re-run:
#   sbatch launch_pipeline.sh
#   Nextflow will resume from the last successful checkpoint.
#
# The pipeline takes a samplesheet with FASTQ files as input, performs
# quality control, trimming and alignment, and produces a gene expression
# matrix and extensive QC report [1].
# =============================================================================

set -euo pipefail

# =====================================================================
# CONFIGURATION
# =====================================================================

# Pipeline version — always pin to a specific version for reproducibility
PIPELINE_VERSION="3.23.0"

# Base directories
BASE="/home/ja581385/genomics_core"
PROJECT_DIR="$(pwd)"
PROJECT_ID="$(basename ${PROJECT_DIR})"
WORK_DIR="${BASE}/work/${PROJECT_ID}"

# Pipeline path — points to the downloaded nf-core/rnaseq code
PIPELINE_PATH="${BASE}/pipelines/nf-core/rnaseq-${PIPELINE_VERSION}/3_23_0"

# Configuration files
CONFIG_DIR="${BASE}/configs/institutional"
SLURM_CONFIG="${CONFIG_DIR}/slurm_hpc.config"
GENOMES_CONFIG="${CONFIG_DIR}/genomes.config"

# Resource profile — uncomment ONE based on project size
RESOURCE_PROFILE="${BASE}/configs/resource_profiles/medium_project.config"
# RESOURCE_PROFILE="${BASE}/configs/resource_profiles/small_project.config"
# RESOURCE_PROFILE="${BASE}/configs/resource_profiles/large_project.config"
# RESOURCE_PROFILE="${BASE}/configs/resource_profiles/multi_project.config"
# RESOURCE_PROFILE="${BASE}/configs/resource_profiles/preemptable.config"


# =====================================================================
# ENVIRONMENT SETUP
# =====================================================================

# Unload system Java (Java 11 — too old for Nextflow 25.x)
module unload java 2>/dev/null || true
module unload openjdk 2>/dev/null || true

# Load genomics core environment (sets Java 17, Nextflow, paths)
source ${BASE}/bin/activate_genomics_core.sh

# Load Singularity/Apptainer for container execution
module load singularity 2>/dev/null || module load apptainer 2>/dev/null || true


# =====================================================================
# JOB INFORMATION
# =====================================================================

echo "============================================="
echo "  nf-core/rnaseq v${PIPELINE_VERSION}"
echo "  Nextflow Head Job"
echo "============================================="
echo ""
echo "  SLURM Job ID:    ${SLURM_JOB_ID}"
echo "  Node:            $(hostname)"
echo "  Project:         ${PROJECT_ID}"
echo "  Project dir:     ${PROJECT_DIR}"
echo "  Work dir:        ${WORK_DIR}"
echo "  Pipeline:        ${PIPELINE_PATH}"
echo "  SLURM config:    ${SLURM_CONFIG}"
echo "  Genomes config:  ${GENOMES_CONFIG}"
echo "  Resource profile: $(basename ${RESOURCE_PROFILE})"
echo ""
echo "  Java:            $(java -version 2>&1 | grep -i version | head -1)"
echo "  Nextflow:        $(nextflow -version 2>&1 | grep version | head -1)"
echo "  Singularity:     $(singularity --version 2>/dev/null || apptainer --version 2>/dev/null)"
echo "  Date:            $(date)"
echo ""
echo "============================================="
echo ""


# =====================================================================
# PRE-FLIGHT CHECKS
# Verify all required files exist before launching the pipeline
# =====================================================================

echo "[Pre-flight] Checking required files..."
PREFLIGHT_PASS=true

# Check samplesheet
if [ -f "samplesheet.csv" ]; then
    SAMPLE_COUNT=$(tail -n +2 samplesheet.csv | grep -c '[^[:space:]]' || echo 0)
    echo "  ✅ samplesheet.csv (${SAMPLE_COUNT} sample entries)"
else
    echo "  ❌ samplesheet.csv NOT FOUND in ${PROJECT_DIR}"
    PREFLIGHT_PASS=false
fi

# Check params.yaml
if [ -f "params.yaml" ]; then
    ALIGNER=$(grep "^aligner:" params.yaml | awk '{print $2}' | tr -d '"' || echo "unknown")
    echo "  ✅ params.yaml (aligner: ${ALIGNER})"
else
    echo "  ❌ params.yaml NOT FOUND in ${PROJECT_DIR}"
    PREFLIGHT_PASS=false
fi

# Check pipeline main.nf
if [ -f "${PIPELINE_PATH}/main.nf" ]; then
    echo "  ✅ Pipeline main.nf"
else
    echo "  ❌ Pipeline main.nf NOT FOUND at ${PIPELINE_PATH}"
    PREFLIGHT_PASS=false
fi

# Check institutional configs
if [ -f "${SLURM_CONFIG}" ]; then
    echo "  ✅ SLURM config"
else
    echo "  ❌ SLURM config NOT FOUND: ${SLURM_CONFIG}"
    PREFLIGHT_PASS=false
fi

if [ -f "${GENOMES_CONFIG}" ]; then
    echo "  ✅ Genomes config"
else
    echo "  ❌ Genomes config NOT FOUND: ${GENOMES_CONFIG}"
    PREFLIGHT_PASS=false
fi

# Check resource profile
if [ -f "${RESOURCE_PROFILE}" ]; then
    echo "  ✅ Resource profile: $(basename ${RESOURCE_PROFILE})"
else
    echo "  ❌ Resource profile NOT FOUND: ${RESOURCE_PROFILE}"
    PREFLIGHT_PASS=false
fi

# Check reference files specified in params.yaml
if [ -f "params.yaml" ]; then
    FASTA=$(grep "^fasta:" params.yaml | awk '{print $2}' | tr -d '"' || echo "")
    GTF=$(grep "^gtf:" params.yaml | awk '{print $2}' | tr -d '"' || echo "")

    if [ -n "${FASTA}" ] && [ -f "${FASTA}" ]; then
        FASTA_SIZE=$(ls -lh "${FASTA}" | awk '{print $5}')
        echo "  ✅ Genome FASTA (${FASTA_SIZE})"
    elif [ -n "${FASTA}" ]; then
        echo "  ❌ Genome FASTA NOT FOUND: ${FASTA}"
        PREFLIGHT_PASS=false
    fi

    if [ -n "${GTF}" ] && [ -f "${GTF}" ]; then
        GTF_SIZE=$(ls -lh "${GTF}" | awk '{print $5}')
        echo "  ✅ GTF annotation (${GTF_SIZE})"
    elif [ -n "${GTF}" ]; then
        echo "  ❌ GTF annotation NOT FOUND: ${GTF}"
        PREFLIGHT_PASS=false
    fi
fi

# Abort if any pre-flight check failed
if [ "${PREFLIGHT_PASS}" = false ]; then
    echo ""
    echo "  ❌ PRE-FLIGHT CHECKS FAILED — fix the issues above and resubmit."
    exit 1
fi

echo ""
echo "  ✅ All pre-flight checks passed."
echo ""


# =====================================================================
# CREATE DIRECTORIES
# =====================================================================

mkdir -p ${WORK_DIR}
mkdir -p logs
mkdir -p ${BASE}/logs/pipeline_runs


# =====================================================================
# LAUNCH PIPELINE
#
# nextflow run <path_to_pipeline>     — run from local download [1]
# -params-file params.yaml           — project-specific parameters
# -profile singularity               — use Singularity containers
# -c <config>                        — institutional and resource configs
# -work-dir <path>                   — where intermediate files are stored
# -with-report/timeline/trace/dag    — execution monitoring reports
# -resume                            — resume from last checkpoint on rerun
#
# The pipeline supports multiple alignment and quantification routes [1]:
#   STAR -> Salmon, STAR -> RSEM, HiSAT2 -> NO QUANTIFICATION
#
# For reproducibility and clarity, we use the ability to stack
# Nextflow configurations using three distinct config files [2]:
#   1. slurm_hpc.config     — system-level (SLURM executor, resources)
#   2. genomes.config       — reference paths
#   3. resource profile     — project-size-specific tuning
# =====================================================================

echo "============================================="
echo "  Launching nf-core/rnaseq v${PIPELINE_VERSION}"
echo ""
echo "  Each pipeline task will be submitted as a separate"
echo "  SLURM job with dedicated resources."
echo ""
echo "  Monitor with:"
echo "    squeue -u $(whoami)"
echo "    tail -f logs/nextflow_run_*.log"
echo "============================================="
echo ""

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

nextflow run ${PIPELINE_PATH} \
    -params-file params.yaml \
    -profile singularity \
    -c ${SLURM_CONFIG} \
    -c ${GENOMES_CONFIG} \
    -c ${RESOURCE_PROFILE} \
    -work-dir ${WORK_DIR} \
    -with-report logs/execution_report.html \
    -with-timeline logs/timeline.html \
    -with-trace logs/trace.txt \
    -with-dag logs/dag.svg \
    -resume \
    2>&1 | tee logs/nextflow_run_${TIMESTAMP}.log

EXIT_CODE=$?


# =====================================================================
# POST-RUN LOGGING AND STATUS
# =====================================================================

echo ""
echo "============================================="
echo "  Pipeline finished"
echo "  Exit code:  ${EXIT_CODE}"
echo "  Completed:  $(date)"
echo "============================================="

# Log to centralized facility run log
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | ${PROJECT_ID} | EXIT:${EXIT_CODE} | SLURM:${SLURM_JOB_ID} | NODE:$(hostname) | SAMPLES:${SAMPLE_COUNT:-unknown}" \
    >> ${BASE}/logs/pipeline_runs/run_log.txt

# Update project metadata status
if [ -f "project_metadata.yaml" ]; then
    if [ ${EXIT_CODE} -eq 0 ]; then
        sed -i "s|^status:.*|status: \"completed\"|" project_metadata.yaml
        sed -i "s|^date_completed:.*|date_completed: \"$(date +%Y-%m-%d)\"|" project_metadata.yaml
    else
        sed -i "s|^status:.*|status: \"failed\"|" project_metadata.yaml
    fi
    sed -i "s|^slurm_job_id:.*|slurm_job_id: \"${SLURM_JOB_ID}\"|" project_metadata.yaml
    sed -i "s|^nextflow_version:.*|nextflow_version: \"$(nextflow -version 2>&1 | grep version | head -1)\"|" project_metadata.yaml
fi


# =====================================================================
# POST-RUN SUMMARY
# =====================================================================

if [ ${EXIT_CODE} -eq 0 ]; then
    echo ""
    echo "  ✅ Pipeline completed successfully!"
    echo ""

    # Show key output files
    echo "  Key outputs:"

    # Gene count matrix — primary deliverable [1]
    COUNTS=$(find results -name "*gene_counts*" -o -name "*salmon.merged*" 2>/dev/null | head -3)
    if [ -n "${COUNTS}" ]; then
        echo "    Gene counts:"
        echo "${COUNTS}" | while read f; do
            SIZE=$(ls -lh "$f" 2>/dev/null | awk '{print $5}')
            echo "      ${SIZE}  $(basename $f)"
        done
    fi

    # MultiQC report
    MULTIQC=$(find results -name "multiqc_report.html" 2>/dev/null | head -1)
    if [ -n "${MULTIQC}" ]; then
        echo "    MultiQC report:"
        echo "      ${MULTIQC}"
    fi

    # Trace summary
    if [ -f "logs/trace.txt" ]; then
        TOTAL_TASKS=$(tail -n +2 logs/trace.txt | wc -l)
        COMPLETED_TASKS=$(grep -c 'COMPLETED' logs/trace.txt 2>/dev/null || echo 0)
        FAILED_TASKS=$(grep -c 'FAILED' logs/trace.txt 2>/dev/null || echo 0)
        echo ""
        echo "  Task summary:"
        echo "    Total:     ${TOTAL_TASKS}"
        echo "    Completed: ${COMPLETED_TASKS}"
        echo "    Failed:    ${FAILED_TASKS}"
    fi

    echo ""
    echo "  Reports:"
    echo "    Execution: logs/execution_report.html"
    echo "    Timeline:  logs/timeline.html"
    echo "    Trace:     logs/trace.txt"
    echo "    DAG:       logs/dag.svg"
    echo ""
    echo "  Next steps:"
    echo "    1. Review MultiQC report in results/multiqc/"
    echo "    2. Complete QC checklist in qc_review/qc_checklist.md"
    echo "    3. Deliver results to PI"
    echo "    4. Archive project:"
    echo "       ${BASE}/scripts/project_management/archive_project.sh ${PROJECT_ID}"

else
    echo ""
    echo "  ❌ Pipeline failed (exit code: ${EXIT_CODE})"
    echo ""
    echo "  Troubleshooting steps:"
    echo "    1. Check Nextflow log for error details:"
    echo "       tail -100 logs/nextflow_run_${TIMESTAMP}.log"
    echo ""
    echo "    2. Check the .nextflow.log for detailed trace:"
    echo "       tail -100 .nextflow.log"
    echo ""
    echo "    3. Check execution report:"
    echo "       logs/execution_report.html"
    echo ""
    echo "    4. Find failed task work directory:"
    echo "       grep 'ERROR' .nextflow.log | tail -5"
    echo "       Then check .command.err in that work directory"
    echo ""
    echo "    5. After fixing the issue, resubmit:"
    echo "       sbatch launch_pipeline.sh"
    echo "       The -resume flag will skip completed tasks."
    echo ""
    echo "  Common failures:"
    echo "    Exit 137 = Out of memory (increase memory in slurm_hpc.config)"
    echo "    Exit 140 = Time limit exceeded (increase time in slurm_hpc.config)"
    echo "    Container error = Check singularity_cache for missing .img files"
    echo ""
    echo "  For help: https://nf-co.re/docs/usage/troubleshooting"
fi

echo ""
echo "============================================="

exit ${EXIT_CODE}

project_tracker update "${PROJECT_ID}" running "Pipeline launched"
