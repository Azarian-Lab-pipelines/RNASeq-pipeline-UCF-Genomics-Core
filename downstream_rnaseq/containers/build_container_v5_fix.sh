#!/bin/bash
#SBATCH --job-name=build_v5fix
#SBATCH --output=build_v5fix_%j.out
#SBATCH --error=build_v5fix_%j.err
#SBATCH --time=03:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=4
#SBATCH --mail-type=ALL
#SBATCH --mail-user=ja581385@ucf.edu

set -euo pipefail

cd /home/ja581385/genomics_core/downstream_rnaseq/containers

module load apptainer 2>/dev/null || module load singularity 2>/dev/null

export APPTAINER_TMPDIR=/home/ja581385/genomics_core/tmp
export SINGULARITY_TMPDIR=/home/ja581385/genomics_core/tmp
mkdir -p $APPTAINER_TMPDIR

echo "=== Container build v5-fix at $(date) ==="
echo ""
echo "Only change from v5: cleanup line fixed"
echo "  OLD: rm -rf /tmp/*"
echo "  NEW: rm -rf /tmp/Rtmp* /tmp/quarto* 2>/dev/null || true"
echo ""
echo "Previous v5 build verified all 54 packages successfully."
echo "It only failed on cleanup of host /tmp files."
echo ""

rm -f rnaseq_report.sif

apptainer build \
    --fakeroot \
    rnaseq_report.sif \
    rnaseq_report_v5_fix.def

BUILD_EXIT=$?

if [ $BUILD_EXIT -ne 0 ]; then
    echo "=== BUILD FAILED at $(date) ==="
    rm -rf $APPTAINER_TMPDIR
    exit $BUILD_EXIT
fi

echo ""
echo "=== Build completed at $(date) ==="
echo "Container: $(ls -lh rnaseq_report.sif)"
echo ""

echo "=== Post-build verification ==="
apptainer exec rnaseq_report.sif R --no-save --no-restore -e "
    pkgs <- c(
        'DESeq2','clusterProfiler','enrichplot',
        'ReactomePA','fgsea','ggrepel','plotly',
        'heatmaply','DT','ggtree','ggtangle',
        'ggiraph','org.Hs.eg.db','org.Mm.eg.db',
        'msigdbr','apeglm','ComplexHeatmap',
        'EnhancedVolcano','crosstalk','htmlwidgets',
        'dplyr','tidyr','ggplot2','pheatmap',
        'RColorBrewer','viridis','matrixStats',
        'bslib','knitr','rmarkdown'
    )
    failed <- c()
    for (p in pkgs) {
        ok <- tryCatch({
            suppressPackageStartupMessages(library(p, character.only=TRUE))
            cat(sprintf('  OK: %-20s v%s\n', p, packageVersion(p)))
            TRUE
        }, error = function(e) {
            cat(sprintf('  FAIL: %s\n', p))
            FALSE
        })
        if (!ok) failed <- c(failed, p)
    }
    if (length(failed) > 0) {
        cat(sprintf('\nFAILED: %s\n', paste(failed, collapse=', ')))
        quit(status=1)
    }
    cat('\n=== ALL TESTS PASSED ===\n')
"

apptainer exec rnaseq_report.sif quarto --version

rm -rf $APPTAINER_TMPDIR

echo ""
echo "=========================================="
echo "  CONTAINER READY: rnaseq_report.sif"
echo "  $(date)"
echo "=========================================="
