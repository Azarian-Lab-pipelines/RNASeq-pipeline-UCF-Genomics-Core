#!/bin/bash
# =============================================================================
# Monitor all active RNA-seq pipeline runs
#
# Shows:
#   - Current SLURM jobs from nf-core pipelines
#   - Status of all active projects
#   - Disk usage for work directories and caches
#
# Usage: ./monitor_runs.sh
# =============================================================================

BASE="/home/ja581385/genomics_core"
ACTIVE_DIR="${BASE}/projects/active"

echo ""
echo "============================================="
echo "  Genomics Core — Pipeline Monitor"
echo "  $(date)"
echo "============================================="

# ---- SLURM jobs ----
echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  SLURM Jobs                                             │"
echo "└─────────────────────────────────────────────────────────┘"

RUNNING_JOBS=$(squeue -u $(whoami) --noheader 2>/dev/null | wc -l)
echo "  Total active jobs: ${RUNNING_JOBS}"
echo ""

if [ ${RUNNING_JOBS} -gt 0 ]; then
    squeue -u $(whoami) \
        --format="  %.10i  %.25j  %.10T  %.10M  %.4C  %.8m  %R" \
        --sort=-S 2>/dev/null | head -30
    
    if [ ${RUNNING_JOBS} -gt 30 ]; then
        echo "  ... and $((RUNNING_JOBS - 30)) more jobs"
    fi
else
    echo "  No active SLURM jobs."
fi

# ---- Active projects ----
echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  Active Projects                                        │"
echo "└─────────────────────────────────────────────────────────┘"
echo ""

if [ -d "${ACTIVE_DIR}" ] && [ "$(ls -A ${ACTIVE_DIR} 2>/dev/null)" ]; then
    printf "  %-22s %-12s %-8s %-12s %-10s\n" "PROJECT" "STATUS" "SAMPLES" "ORGANISM" "CREATED"
    printf "  %-22s %-12s %-8s %-12s %-10s\n" "───────────────────" "──────────" "───────" "──────────" "────────"

    for proj_dir in ${ACTIVE_DIR}/*/; do
        if [ -d "${proj_dir}" ]; then
            proj_id=$(basename ${proj_dir})
            status="unknown"
            samples="-"
            organism="-"
            created="-"

            # Read metadata
            if [ -f "${proj_dir}/project_metadata.yaml" ]; then
                status=$(grep "^status:" ${proj_dir}/project_metadata.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "unknown")
                organism=$(grep "^organism:" ${proj_dir}/project_metadata.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "-")
                created=$(grep "^date_received:" ${proj_dir}/project_metadata.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "-")
            fi

            # Count samples from samplesheet
            if [ -f "${proj_dir}/samplesheet.csv" ]; then
                samples=$(tail -n +2 ${proj_dir}/samplesheet.csv 2>/dev/null | grep -c '[^[:space:]]' || echo 0)
            fi

            # Check if actively running (Nextflow process or recent SLURM job)
            if squeue -u $(whoami) --name="nfcore_${proj_id}" --noheader 2>/dev/null | grep -q .; then
                status="RUNNING"
            fi

            printf "  %-22s %-12s %-8s %-12s %-10s\n" \
                "${proj_id}" "${status}" "${samples}" "${organism}" "${created}"
        fi
    done
else
    echo "  No active projects."
fi

# ---- Disk usage ----
echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  Disk Usage                                             │"
echo "└─────────────────────────────────────────────────────────┘"
echo ""
printf "  %-40s %s\n" "Directory" "Size"
printf "  %-40s %s\n" "────────────────────────────────────────" "────────"

# Work directories (intermediate files — can be large)
WORK_SIZE=$(du -sh ${BASE}/work/ 2>/dev/null | cut -f1 || echo "0")
printf "  %-40s %s\n" "work/ (intermediate files)" "${WORK_SIZE}"

# Active projects
ACTIVE_SIZE=$(du -sh ${ACTIVE_DIR} 2>/dev/null | cut -f1 || echo "0")
printf "  %-40s %s\n" "projects/active/" "${ACTIVE_SIZE}"

# Singularity cache
CACHE_SIZE=$(du -sh ${BASE}/singularity_cache/ 2>/dev/null | cut -f1 || echo "0")
CACHE_COUNT=$(find ${BASE}/singularity_cache -name "*.img" -type f 2>/dev/null | wc -l)
printf "  %-40s %s (%s images)\n" "singularity_cache/" "${CACHE_SIZE}" "${CACHE_COUNT}"

# References
REF_SIZE=$(du -sh ${BASE}/references/ 2>/dev/null | cut -f1 || echo "0")
printf "  %-40s %s\n" "references/" "${REF_SIZE}"

# Per-project work directories
echo ""
echo "  Work directories per project:"
if [ -d "${BASE}/work" ] && [ "$(ls -A ${BASE}/work 2>/dev/null)" ]; then
    for wdir in ${BASE}/work/*/; do
        if [ -d "${wdir}" ]; then
            WSIZE=$(du -sh "${wdir}" 2>/dev/null | cut -f1 || echo "0")
            printf "    %-35s %s\n" "$(basename ${wdir})" "${WSIZE}"
        fi
    done
else
    echo "    No project work directories."
fi

# ---- Facility job limit ----
echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  Account Usage                                          │"
echo "└─────────────────────────────────────────────────────────┘"
echo ""
echo "  Account: tazarian"
echo "  Active jobs: ${RUNNING_JOBS} / 250 (max)"
echo "  Available slots: $((250 - RUNNING_JOBS))"

echo ""
echo "============================================="

echo "=== Project Tracker Summary ==="
project_tracker summary
