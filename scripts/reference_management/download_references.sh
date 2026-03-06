#!/bin/bash
#SBATCH --job-name=download_refs
#SBATCH --output=/home/ja581385/genomics_core/logs/system/download_refs_%j.out
#SBATCH --error=/home/ja581385/genomics_core/logs/system/download_refs_%j.err
#SBATCH --time=06:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G

# =============================================================================
# Download Reference Genomes and Annotations
#
# Downloads genome FASTA and GTF annotation files from GENCODE for use
# with nf-core/rnaseq. The pipeline takes a samplesheet with FASTQ files
# as input, performs quality control, trimming and alignment, and produces
# a gene expression matrix and extensive QC report [1].
#
# Usage (interactive — from login node with internet):
#   ./download_references.sh GRCh38
#   ./download_references.sh GRCm39
#   ./download_references.sh all
#
# Usage (SLURM — from compute node):
#   sbatch download_references.sh GRCh38
#   sbatch download_references.sh GRCm39
#   sbatch download_references.sh all
#
# What is downloaded for each organism:
#   - Primary assembly genome FASTA (soft-masked)
#   - Primary assembly GTF annotation
#   - Transcript sequences FASTA
#   - MD5 checksums for verification
#
# GENCODE is the recommended annotation source for nf-core/rnaseq
# because it provides comprehensive gene models and the pipeline
# has a --gencode flag for proper handling of GENCODE-specific
# transcript ID formatting.
# =============================================================================

set -euo pipefail

BASE="/home/ja581385/genomics_core"
REF_DIR="${BASE}/references"
CHECKSUM_DIR="${REF_DIR}/checksums"
ORGANISM="${1:-all}"

# ---- Environment ----
# Source genomics core environment if running as SLURM job
if [ -n "${SLURM_JOB_ID:-}" ]; then
    module unload java 2>/dev/null || true
    source ${BASE}/bin/activate_genomics_core.sh 2>/dev/null || true
fi

mkdir -p ${CHECKSUM_DIR}
mkdir -p ${BASE}/logs/system

echo "============================================="
echo "  Reference Genome Download"
echo "  $(date)"
echo "============================================="
echo ""

# =====================================================================
# Function: Download Human GRCh38 (GENCODE v44)
# =====================================================================
download_grch38() {
    local DIR="${REF_DIR}/genomes/GRCh38"
    local GENCODE_VERSION="44"
    local GENCODE_BASE="https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_${GENCODE_VERSION}"

    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  Downloading Human GRCh38 (GENCODE v${GENCODE_VERSION})              │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
    echo "  Source: ${GENCODE_BASE}"
    echo "  Target: ${DIR}"
    echo ""

    mkdir -p ${DIR}
    cd ${DIR}

    # ---- Genome FASTA ----
    # Primary assembly: excludes alternate haplotypes and patches
    # This is the recommended FASTA for RNA-seq alignment
    local FASTA="GRCh38.primary_assembly.genome.fa"
    if [ -f "${FASTA}" ]; then
        local FASTA_SIZE=$(ls -lh "${FASTA}" | awk '{print $5}')
        echo "  [1/4] Genome FASTA: EXISTS (${FASTA_SIZE}) — skipping"
    else
        echo "  [1/4] Downloading genome FASTA..."
        echo "        ${FASTA}.gz (~800 MB)"
        wget -c -q --show-progress "${GENCODE_BASE}/${FASTA}.gz"
        echo "        Decompressing..."
        gunzip "${FASTA}.gz"
        local FASTA_SIZE=$(ls -lh "${FASTA}" | awk '{print $5}')
        echo "        ✅ Done (${FASTA_SIZE})"
    fi

    # ---- GTF Annotation ----
    # Primary assembly annotation: matches the primary assembly FASTA
    local GTF="gencode.v${GENCODE_VERSION}.primary_assembly.annotation.gtf"
    if [ -f "${GTF}" ]; then
        local GTF_SIZE=$(ls -lh "${GTF}" | awk '{print $5}')
        echo "  [2/4] GTF annotation: EXISTS (${GTF_SIZE}) — skipping"
    else
        echo "  [2/4] Downloading GTF annotation..."
        echo "        ${GTF}.gz (~50 MB)"
        wget -c -q --show-progress "${GENCODE_BASE}/${GTF}.gz"
        echo "        Decompressing..."
        gunzip "${GTF}.gz"
        local GTF_SIZE=$(ls -lh "${GTF}" | awk '{print $5}')
        echo "        ✅ Done (${GTF_SIZE})"
    fi

    # ---- Transcript FASTA ----
    # Used by Salmon for transcriptome-level quantification
    local TRANSCRIPTS="gencode.v${GENCODE_VERSION}.transcripts.fa"
    if [ -f "${TRANSCRIPTS}" ]; then
        local TX_SIZE=$(ls -lh "${TRANSCRIPTS}" | awk '{print $5}')
        echo "  [3/4] Transcript FASTA: EXISTS (${TX_SIZE}) — skipping"
    else
        echo "  [3/4] Downloading transcript FASTA..."
        echo "        ${TRANSCRIPTS}.gz (~100 MB)"
        wget -c -q --show-progress "${GENCODE_BASE}/${TRANSCRIPTS}.gz"
        echo "        Decompressing..."
        gunzip "${TRANSCRIPTS}.gz"
        local TX_SIZE=$(ls -lh "${TRANSCRIPTS}" | awk '{print $5}')
        echo "        ✅ Done (${TX_SIZE})"
    fi

    # ---- Generate checksums ----
    echo "  [4/4] Generating MD5 checksums..."
    md5sum ${FASTA} ${GTF} ${TRANSCRIPTS} > ${CHECKSUM_DIR}/GRCh38_md5sums.txt 2>/dev/null
    echo "        ✅ Checksums saved to ${CHECKSUM_DIR}/GRCh38_md5sums.txt"

    echo ""
    echo "  GRCh38 download summary:"
    ls -lh ${DIR}/*.fa ${DIR}/*.gtf 2>/dev/null | awk '{printf "    %-10s %s\n", $5, $NF}'
    echo ""

    # ---- Log ----
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | DOWNLOADED | GRCh38 | GENCODE v${GENCODE_VERSION} | ${DIR}" \
        >> ${BASE}/logs/system/reference_builds.log
}


# =====================================================================
# Function: Download Mouse GRCm39 (GENCODE vM33)
# =====================================================================
download_grcm39() {
    local DIR="${REF_DIR}/genomes/GRCm39"
    local GENCODE_VERSION="M33"
    local GENCODE_BASE="https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_mouse/release_${GENCODE_VERSION}"

    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  Downloading Mouse GRCm39 (GENCODE v${GENCODE_VERSION})               │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
    echo "  Source: ${GENCODE_BASE}"
    echo "  Target: ${DIR}"
    echo ""

    mkdir -p ${DIR}
    cd ${DIR}

    # ---- Genome FASTA ----
    local FASTA="GRCm39.primary_assembly.genome.fa"
    if [ -f "${FASTA}" ]; then
        local FASTA_SIZE=$(ls -lh "${FASTA}" | awk '{print $5}')
        echo "  [1/4] Genome FASTA: EXISTS (${FASTA_SIZE}) — skipping"
    else
        echo "  [1/4] Downloading genome FASTA..."
        echo "        ${FASTA}.gz (~700 MB)"
        wget -c -q --show-progress "${GENCODE_BASE}/${FASTA}.gz"
        echo "        Decompressing..."
        gunzip "${FASTA}.gz"
        local FASTA_SIZE=$(ls -lh "${FASTA}" | awk '{print $5}')
        echo "        ✅ Done (${FASTA_SIZE})"
    fi

    # ---- GTF Annotation ----
    local GTF="gencode.v${GENCODE_VERSION}.primary_assembly.annotation.gtf"
    if [ -f "${GTF}" ]; then
        local GTF_SIZE=$(ls -lh "${GTF}" | awk '{print $5}')
        echo "  [2/4] GTF annotation: EXISTS (${GTF_SIZE}) — skipping"
    else
        echo "  [2/4] Downloading GTF annotation..."
        echo "        ${GTF}.gz (~40 MB)"
        wget -c -q --show-progress "${GENCODE_BASE}/${GTF}.gz"
        echo "        Decompressing..."
        gunzip "${GTF}.gz"
        local GTF_SIZE=$(ls -lh "${GTF}" | awk '{print $5}')
        echo "        ✅ Done (${GTF_SIZE})"
    fi

    # ---- Transcript FASTA ----
    local TRANSCRIPTS="gencode.v${GENCODE_VERSION}.transcripts.fa"
    if [ -f "${TRANSCRIPTS}" ]; then
        local TX_SIZE=$(ls -lh "${TRANSCRIPTS}" | awk '{print $5}')
        echo "  [3/4] Transcript FASTA: EXISTS (${TX_SIZE}) — skipping"
    else
        echo "  [3/4] Downloading transcript FASTA..."
        echo "        ${TRANSCRIPTS}.gz (~70 MB)"
        wget -c -q --show-progress "${GENCODE_BASE}/${TRANSCRIPTS}.gz"
        echo "        Decompressing..."
        gunzip "${TRANSCRIPTS}.gz"
        local TX_SIZE=$(ls -lh "${TRANSCRIPTS}" | awk '{print $5}')
        echo "        ✅ Done (${TX_SIZE})"
    fi

    # ---- Generate checksums ----
    echo "  [4/4] Generating MD5 checksums..."
    md5sum ${FASTA} ${GTF} ${TRANSCRIPTS} > ${CHECKSUM_DIR}/GRCm39_md5sums.txt 2>/dev/null
    echo "        ✅ Checksums saved to ${CHECKSUM_DIR}/GRCm39_md5sums.txt"

    echo ""
    echo "  GRCm39 download summary:"
    ls -lh ${DIR}/*.fa ${DIR}/*.gtf 2>/dev/null | awk '{printf "    %-10s %s\n", $5, $NF}'
    echo ""

    # ---- Log ----
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | DOWNLOADED | GRCm39 | GENCODE v${GENCODE_VERSION} | ${DIR}" \
        >> ${BASE}/logs/system/reference_builds.log
}


# =====================================================================
# Main execution
# =====================================================================

case ${ORGANISM} in
    GRCh38)
        download_grch38
        ;;
    GRCm39)
        download_grcm39
        ;;
    all)
        download_grch38
        download_grcm39
        ;;
    *)
        echo "ERROR: Unknown organism '${ORGANISM}'"
        echo ""
        echo "Usage: $0 [GRCh38|GRCm39|all]"
        echo ""
        echo "  GRCh38  — Human (GENCODE v44)"
        echo "  GRCm39  — Mouse (GENCODE vM33)"
        echo "  all     — Download both"
        exit 1
        ;;
esac


# =====================================================================
# Final summary
# =====================================================================

echo "============================================="
echo "  Reference Download Summary"
echo "============================================="
echo ""

echo "  Downloaded genomes:"
for ORG_DIR in ${REF_DIR}/genomes/*/; do
    if [ -d "${ORG_DIR}" ]; then
        ORG_NAME=$(basename ${ORG_DIR})
        FILE_COUNT=$(find ${ORG_DIR} -maxdepth 1 -type f | wc -l)
        DIR_SIZE=$(du -sh ${ORG_DIR} 2>/dev/null | cut -f1)
        if [ ${FILE_COUNT} -gt 0 ]; then
            echo "    ✅ ${ORG_NAME}: ${FILE_COUNT} files (${DIR_SIZE})"
        else
            echo "    ⚠️  ${ORG_NAME}: empty (not yet downloaded)"
        fi
    fi
done

echo ""
echo "  Checksum files:"
ls -la ${CHECKSUM_DIR}/*.txt 2>/dev/null | awk '{printf "    %s\n", $NF}' || echo "    None"

echo ""
echo "  Next steps:"
echo "    1. Build STAR index:"
echo "       sbatch scripts/reference_management/build_star_index.sh GRCh38 149"
echo "       sbatch scripts/reference_management/build_star_index.sh GRCm39 149"
echo ""
echo "    2. Build Salmon index:"
echo "       sbatch scripts/reference_management/build_salmon_index.sh GRCh38"
echo "       sbatch scripts/reference_management/build_salmon_index.sh GRCm39"
echo ""
echo "    3. Or skip index building and let the pipeline build them"
echo "       automatically on the first run (slower but simpler)."
echo "       Enable --save_reference to save the built indices."
echo ""
echo "  Completed: $(date)"
echo "============================================="
