#!/bin/bash
# =============================================================================
# Archive a Completed RNA-seq Project
#
# This script:
#   1. Copies results, configs, logs, and metadata to the archive directory
#   2. Does NOT copy raw FASTQ files (they remain in original location)
#   3. Removes the Nextflow work directory (largest disk consumer)
#   4. Moves the project from active/ to completed/
#   5. Generates an archive manifest
#   6. Logs the archival to the facility audit log
#
# Usage: ./archive_project.sh <PROJECT_ID>
# Example: ./archive_project.sh PROJ-2026-001
#
# The archive preserves everything needed to understand and reproduce
# the analysis: parameters, samplesheet, configs, results, QC reports,
# metadata, and execution logs.
# =============================================================================

set -euo pipefail

PROJECT_ID="${1:?ERROR: Provide PROJECT_ID (e.g., PROJ-2026-001)}"
BASE="/home/ja581385/genomics_core"
ACTIVE_DIR="${BASE}/projects/active/${PROJECT_ID}"
COMPLETED_DIR="${BASE}/projects/completed"
YEAR=$(date +%Y)
ARCHIVE_DIR="${BASE}/archive/${YEAR}/${PROJECT_ID}"
WORK_DIR="${BASE}/work/${PROJECT_ID}"

# ---- Validate project exists ----
if [ ! -d "${ACTIVE_DIR}" ]; then
    echo "ERROR: Active project not found: ${ACTIVE_DIR}"
    echo ""
    echo "  Active projects:"
    ls ${BASE}/projects/active/ 2>/dev/null || echo "  (none)"
    exit 1
fi

# ---- Check pipeline completed ----
STATUS="unknown"
if [ -f "${ACTIVE_DIR}/project_metadata.yaml" ]; then
    STATUS=$(grep "^status:" ${ACTIVE_DIR}/project_metadata.yaml | awk '{print $2}' | tr -d '"' || echo "unknown")
fi

echo "============================================="
echo "  Archive Project: ${PROJECT_ID}"
echo "============================================="
echo ""
echo "  Source:         ${ACTIVE_DIR}"
echo "  Archive:        ${ARCHIVE_DIR}"
echo "  Work dir:       ${WORK_DIR}"
echo "  Current status: ${STATUS}"
echo ""

# Warn if not completed
if [ "${STATUS}" != "completed" ]; then
    echo "  ⚠️  WARNING: Project status is '${STATUS}', not 'completed'."
    echo ""
fi

# ---- Show what will be archived ----
echo "  Files to archive (excluding raw FASTQ and work directory):"
ACTIVE_SIZE=$(du -sh ${ACTIVE_DIR} --exclude='data/fastq' 2>/dev/null | cut -f1 || echo "unknown")
echo "    Project size (excl. FASTQ): ${ACTIVE_SIZE}"

if [ -d "${WORK_DIR}" ]; then
    WORK_SIZE=$(du -sh ${WORK_DIR} 2>/dev/null | cut -f1 || echo "unknown")
    echo "    Work directory size: ${WORK_SIZE} (WILL BE DELETED)"
fi

echo ""

# ---- MultiQC report check ----
MULTIQC=$(find ${ACTIVE_DIR}/results -name "multiqc_report.html" 2>/dev/null | head -1)
if [ -n "${MULTIQC}" ]; then
    echo "  ✅ MultiQC report found — results appear complete"
else
    echo "  ⚠️  MultiQC report NOT found — results may be incomplete"
fi

# ---- Gene counts check ----
COUNTS=$(find ${ACTIVE_DIR}/results -name "*gene_counts*" -o -name "*salmon.merged*" 2>/dev/null | head -1)
if [ -n "${COUNTS}" ]; then
    echo "  ✅ Gene count matrix found"
else
    echo "  ⚠️  Gene count matrix NOT found"
fi

echo ""

# ---- Confirm ----
read -p "  Proceed with archival? (yes/no): " CONFIRM
if [ "${CONFIRM}" != "yes" ]; then
    echo "  Cancelled."
    exit 0
fi

echo ""
echo "  Archiving..."

# ---- Create archive ----
mkdir -p ${ARCHIVE_DIR}

# Copy everything EXCEPT raw FASTQs (they stay in original location)
echo "  [1/5] Copying project files to archive..."
rsync -a --progress \
    --exclude='data/fastq/' \
    --exclude='.nextflow/' \
    --exclude='.nextflow.log*' \
    ${ACTIVE_DIR}/ ${ARCHIVE_DIR}/

# ---- Update metadata ----
echo "  [2/5] Updating metadata..."
if [ -f "${ARCHIVE_DIR}/project_metadata.yaml" ]; then
    sed -i "s|^date_completed:.*|date_completed: \"$(date +%Y-%m-%d)\"|" ${ARCHIVE_DIR}/project_metadata.yaml
    sed -i "s|^status:.*|status: \"archived\"|" ${ARCHIVE_DIR}/project_metadata.yaml
    sed -i "s|^archive_location:.*|archive_location: \"${ARCHIVE_DIR}\"|" ${ARCHIVE_DIR}/project_metadata.yaml
fi

# ---- Generate archive manifest ----
echo "  [3/5] Generating archive manifest..."
cat > ${ARCHIVE_DIR}/ARCHIVE_MANIFEST.txt << MANEOF
# =============================================================================
# Archive Manifest
# =============================================================================
Project:       ${PROJECT_ID}
Archived:      $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Archived by:   $(whoami)
Source:        ${ACTIVE_DIR}
Archive:       ${ARCHIVE_DIR}
Pipeline:      nf-core/rnaseq v3.23.0

Files:
MANEOF

find ${ARCHIVE_DIR} -type f | sort | \
    while read f; do
        SIZE=$(ls -lh "$f" | awk '{print $5}')
        REL=$(echo "$f" | sed "s|${ARCHIVE_DIR}/||")
        echo "  ${SIZE}  ${REL}" >> ${ARCHIVE_DIR}/ARCHIVE_MANIFEST.txt
    done

ARCHIVE_SIZE=$(du -sh ${ARCHIVE_DIR} 2>/dev/null | cut -f1)
echo "" >> ${ARCHIVE_DIR}/ARCHIVE_MANIFEST.txt
echo "Total archive size: ${ARCHIVE_SIZE}" >> ${ARCHIVE_DIR}/ARCHIVE_MANIFEST.txt

# ---- Remove work directory ----
echo "  [4/5] Cleaning work directory..."
if [ -d "${WORK_DIR}" ]; then
    WORK_SIZE=$(du -sh ${WORK_DIR} 2>/dev/null | cut -f1)
    rm -rf ${WORK_DIR}
    echo "    Removed ${WORK_SIZE} from ${WORK_DIR}"
else
    echo "    No work directory found."
fi

# ---- Move from active to completed ----
echo "  [5/5] Moving project to completed..."
mkdir -p ${COMPLETED_DIR}
mv ${ACTIVE_DIR} ${COMPLETED_DIR}/${PROJECT_ID}

# ---- Log to facility audit ----
mkdir -p ${BASE}/logs/audits
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | ARCHIVED | ${PROJECT_ID} | ARCHIVE:${ARCHIVE_DIR} | BY:$(whoami)" \
    >> ${BASE}/logs/audits/project_audit.log

echo ""
echo "============================================="
echo "  ✅ Archive complete"
echo "============================================="
echo ""
echo "  Archive location:    ${ARCHIVE_DIR}"
echo "  Archive size:        ${ARCHIVE_SIZE}"
echo "  Completed project:   ${COMPLETED_DIR}/${PROJECT_ID}"
echo "  Work dir cleaned:    ${WORK_DIR}"
echo "  Manifest:            ${ARCHIVE_DIR}/ARCHIVE_MANIFEST.txt"
echo ""
echo "============================================="
