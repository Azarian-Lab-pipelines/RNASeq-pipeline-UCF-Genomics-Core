#!/bin/bash
# =============================================================================
# Clean up test run directories and work files
# Usage: ./scripts/clean_test.sh
# =============================================================================

set -euo pipefail

BASE="/home/ja581385/genomics_core"

echo "============================================="
echo "  Cleaning up test files"
echo "  $(date)"
echo "============================================="
echo ""

# ---- Show what will be cleaned ----
echo "Directories to remove:"
echo ""

# Test run directories
if ls -d ${BASE}/tests/test_run_* 1>/dev/null 2>&1; then
    for d in ${BASE}/tests/test_run_*; do
        SIZE=$(du -sh "$d" 2>/dev/null | cut -f1)
        echo "  ${SIZE}  ${d}"
    done
else
    echo "  No test run directories found."
fi

# Test work directory
if [ -d "${BASE}/work/test_validation" ]; then
    SIZE=$(du -sh ${BASE}/work/test_validation 2>/dev/null | cut -f1)
    echo "  ${SIZE}  ${BASE}/work/test_validation"
fi

# Old test logs
echo ""
echo "Log files to remove:"
if ls ${BASE}/logs/system/test_*.out 1>/dev/null 2>&1; then
    ls -lh ${BASE}/logs/system/test_*.out ${BASE}/logs/system/test_*.err 2>/dev/null | \
        awk '{print "  " $5 "  " $NF}'
fi

# ---- Calculate total ----
TOTAL_TEST=$(du -sh ${BASE}/tests/test_run_* 2>/dev/null | tail -1 | cut -f1)
TOTAL_WORK=$(du -sh ${BASE}/work/test_validation 2>/dev/null | cut -f1)
echo ""
echo "  Total test results: ${TOTAL_TEST:-0}"
echo "  Total work dir:     ${TOTAL_WORK:-0}"

# ---- Confirm ----
echo ""
read -p "Remove all test files? (yes/no): " CONFIRM
if [ "${CONFIRM}" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

# ---- Clean ----
echo ""
echo "Removing test run directories..."
rm -rf ${BASE}/tests/test_run_* 2>/dev/null
echo "  Done."

echo "Removing test work directory..."
rm -rf ${BASE}/work/test_validation 2>/dev/null
echo "  Done."

echo "Removing test log files..."
rm -f ${BASE}/logs/system/test_*.out 2>/dev/null
rm -f ${BASE}/logs/system/test_*.err 2>/dev/null
echo "  Done."

# ---- Also clean Nextflow cache files from tests ----
echo "Cleaning Nextflow temporary files..."
rm -rf ${BASE}/tests/.nextflow* 2>/dev/null
rm -rf ${BASE}/tests/test_run_*/.nextflow* 2>/dev/null
echo "  Done."

echo ""
echo "============================================="
echo "  ✅ Cleanup complete"
echo ""
echo "  Disk recovered:"
echo "    Tests dir:  $(du -sh ${BASE}/tests 2>/dev/null | cut -f1)"
echo "    Work dir:   $(du -sh ${BASE}/work 2>/dev/null | cut -f1)"
echo "    Logs dir:   $(du -sh ${BASE}/logs 2>/dev/null | cut -f1)"
echo ""
echo "  Your installation is verified and ready."
echo "  Next steps:"
echo "    1. Download references:"
echo "       ./scripts/reference_management/download_references.sh GRCh38"
echo "    2. Initialize a project:"
echo "       ./scripts/project_management/init_project.sh PROJ-2026-001 'Dr.Smith' GRCh38 'ja581385'"
echo "============================================="
