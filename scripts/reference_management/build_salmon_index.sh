#!/bin/bash
#SBATCH --job-name=build_salmon_idx
#SBATCH --output=/home/ja581385/genomics_core/logs/system/salmon_index_%j.out
#SBATCH --error=/home/ja581385/genomics_core/logs/system/salmon_index_%j.err
#SBATCH --time=04:00:00
#SBATCH --cpus-per-task=12
#SBATCH --mem=48G
#SBATCH --mail-type=ALL
#SBATCH --mail-user=ja581385@ucf.edu
# =============================================================================
# Build Salmon Decoy-Aware Index
#
# Salmon performs quantification in the STAR → Salmon alignment route,
# which is the default and recommended aligner for nf-core/rnaseq.
#
# A decoy-aware index uses the genome as decoy sequences to improve
# quantification accuracy. This prevents reads from spuriously mapping
# to the transcriptome when they originate from intergenic/intronic regions.
#
# The index is built from:
#   1. Transcript FASTA (from GENCODE)
#   2. Genome FASTA (used as decoy sequences)
#
# Usage:
#   sbatch build_salmon_index.sh <ORGANISM>
#
# Examples:
#   sbatch build_salmon_index.sh GRCh38
#   sbatch build_salmon_index.sh GRCm39
#
# Resources:
#   Human GRCh38: ~32-40 GB RAM, ~2 GB disk, 15-30 min with 12 CPUs
#   Mouse GRCm39: ~28-35 GB RAM, ~1.5 GB disk, 10-25 min with 12 CPUs
#
# After building, update genomes.config to uncomment the salmon_index path.
# =============================================================================

set -euo pipefail

ORGANISM="${1:?ERROR: Provide organism (GRCh38 or GRCm39)}"
BASE="/home/ja581385/genomics_core"
REF_DIR="${BASE}/references"
THREADS=${SLURM_CPUS_PER_TASK:-12}

# ---- Environment ----
module unload java 2>/dev/null || true
source ${BASE}/bin/activate_genomics_core.sh
module load singularity 2>/dev/null || module load apptainer 2>/dev/null || true

# ---- Set organism-specific paths ----
case ${ORGANISM} in
    GRCh38)
        FASTA="${REF_DIR}/genomes/GRCh38/GRCh38.primary_assembly.genome.fa"
        TRANSCRIPTS="${REF_DIR}/genomes/GRCh38/gencode.v44.transcripts.fa"
        ORGANISM_NAME="Human"
        ANNOTATION="GENCODE v44"
        ;;
    GRCm39)
        FASTA="${REF_DIR}/genomes/GRCm39/GRCm39.primary_assembly.genome.fa"
        TRANSCRIPTS="${REF_DIR}/genomes/GRCm39/gencode.vM33.transcripts.fa"
        ORGANISM_NAME="Mouse"
        ANNOTATION="GENCODE vM33"
        ;;
    *)
        echo "ERROR: Unknown organism '${ORGANISM}'."
        echo "  Supported: GRCh38, GRCm39"
        exit 1
        ;;
esac

OUTDIR="${REF_DIR}/indices/salmon/${ORGANISM}"
TMPDIR="${BASE}/tmp/salmon_index_${ORGANISM}_$$"

echo "============================================="
echo "  Building Salmon Decoy-Aware Index"
echo "============================================="
echo ""
echo "  Organism:      ${ORGANISM} (${ORGANISM_NAME})"
echo "  Annotation:    ${ANNOTATION}"
echo "  Threads:       ${THREADS}"
echo "  Genome FASTA:  ${FASTA}"
echo "  Transcripts:   ${TRANSCRIPTS}"
echo "  Output:        ${OUTDIR}"
echo ""
if [ -n "${SLURM_JOB_ID:-}" ]; then
    echo "  SLURM Job ID:  ${SLURM_JOB_ID}"
    echo "  Node:          $(hostname)"
    echo "  Memory:        ${SLURM_MEM_PER_NODE:-unknown} MB"
fi
echo "  Date:          $(date)"
echo ""
echo "============================================="
echo ""

# ---- Validate input files ----
echo "[1/6] Validating input files..."

if [ ! -f "${FASTA}" ]; then
    echo "  ❌ Genome FASTA not found: ${FASTA}"
    echo "  Run first: ./scripts/reference_management/download_references.sh ${ORGANISM}"
    exit 1
fi
FASTA_SIZE=$(ls -lh "${FASTA}" | awk '{print $5}')
echo "  ✅ Genome FASTA: ${FASTA_SIZE}"

if [ ! -f "${TRANSCRIPTS}" ]; then
    echo "  ❌ Transcript FASTA not found: ${TRANSCRIPTS}"
    echo "  Run first: ./scripts/reference_management/download_references.sh ${ORGANISM}"
    exit 1
fi
TX_SIZE=$(ls -lh "${TRANSCRIPTS}" | awk '{print $5}')
echo "  ✅ Transcript FASTA: ${TX_SIZE}"

# ---- Check if index already exists ----
echo ""
echo "[2/6] Checking for existing index..."

if [ -f "${OUTDIR}/info.json" ] && [ -f "${OUTDIR}/pos.bin" ]; then
    INDEX_SIZE=$(du -sh ${OUTDIR} 2>/dev/null | cut -f1)
    echo "  ⚠️  Salmon index already exists at: ${OUTDIR} (${INDEX_SIZE})"
    echo "  To force rebuild, remove the directory first:"
    echo "    rm -rf ${OUTDIR}"
    exit 0
else
    echo "  No existing index found. Building new index."
fi

# ---- Find Salmon binary ----
echo ""
echo "[3/6] Locating Salmon..."

SALMON_IMG=$(find ${BASE}/singularity_cache ${BASE}/pipelines -name "*salmon*" -name "*.img" -type f 2>/dev/null | head -1)

if [ -n "${SALMON_IMG}" ]; then
    echo "  Using Salmon from container: $(basename ${SALMON_IMG})"
    SALMON_CMD="singularity exec ${SALMON_IMG} salmon"
    SALMON_VERSION=$(${SALMON_CMD} --version 2>&1 | head -1 || echo "unknown")
    echo "  Salmon version: ${SALMON_VERSION}"

    # grep is also needed for building decoys — check it exists in container
    GREP_CMD="singularity exec ${SALMON_IMG} grep"
    CUT_CMD="singularity exec ${SALMON_IMG} cut"
elif command -v salmon &> /dev/null; then
    echo "  Using Salmon from PATH: $(which salmon)"
    SALMON_CMD="salmon"
    SALMON_VERSION=$(salmon --version 2>&1 | head -1 || echo "unknown")
    echo "  Salmon version: ${SALMON_VERSION}"
    GREP_CMD="grep"
    CUT_CMD="cut"
else
    module load salmon 2>/dev/null || true
    if command -v salmon &> /dev/null; then
        echo "  Using Salmon from module: $(which salmon)"
        SALMON_CMD="salmon"
        SALMON_VERSION=$(salmon --version 2>&1 | head -1 || echo "unknown")
        echo "  Salmon version: ${SALMON_VERSION}"
        GREP_CMD="grep"
        CUT_CMD="cut"
    else
        echo "  ❌ Salmon not found."
        echo "  Options:"
        echo "    1. Let the pipeline build the index automatically"
        echo "    2. Install Salmon: conda install -c bioconda salmon"
        echo "    3. Load a module: module load salmon"
        exit 1
    fi
fi

# ---- Create decoy-aware gentrome ----
echo ""
echo "[4/6] Creating decoy-aware gentrome..."
echo "  This concatenates transcripts + genome and extracts chromosome names as decoys."

mkdir -p ${TMPDIR}

# Extract chromosome names from genome FASTA as decoy list
echo "  Extracting decoy sequence names from genome..."
grep "^>" ${FASTA} | cut -d " " -f 1 | sed 's/^>//' > ${TMPDIR}/decoys.txt
DECOY_COUNT=$(wc -l < ${TMPDIR}/decoys.txt)
echo "  ✅ Found ${DECOY_COUNT} decoy sequences (chromosomes/scaffolds)"

# Concatenate transcriptome + genome into gentrome FASTA
# Transcripts must come FIRST, genome second
echo "  Concatenating transcriptome + genome into gentrome..."
cat ${TRANSCRIPTS} ${FASTA} > ${TMPDIR}/gentrome.fa
GENTROME_SIZE=$(ls -lh ${TMPDIR}/gentrome.fa | awk '{print $5}')
echo "  ✅ Gentrome created: ${GENTROME_SIZE}"

# ---- Build index ----
echo ""
echo "[5/6] Building Salmon index..."
echo "  This will take 15-30 minutes and use ~32-40 GB RAM."
echo ""

mkdir -p ${OUTDIR}
BUILD_START=$(date +%s)

${SALMON_CMD} index \
    --transcripts ${TMPDIR}/gentrome.fa \
    --index ${OUTDIR} \
    --decoys ${TMPDIR}/decoys.txt \
    --threads ${THREADS} \
    --gencode

BUILD_EXIT=$?
BUILD_END=$(date +%s)
BUILD_DURATION=$(( (BUILD_END - BUILD_START) / 60 ))

echo ""

if [ ${BUILD_EXIT} -ne 0 ]; then
    echo "  ❌ Salmon index build failed (exit code: ${BUILD_EXIT})"
    rm -rf ${TMPDIR}
    exit ${BUILD_EXIT}
fi

# ---- Clean up temp files ----
echo "[6/6] Cleaning temporary files..."
rm -rf ${TMPDIR}
echo "  ✅ Temporary files removed"

# ---- Verify output ----
echo ""
echo "  Verifying index..."

REQUIRED_FILES=("info.json" "pos.bin" "complete_ref_lens.bin" "mphf.bin" "rank.bin")
ALL_PRESENT=true

for RF in "${REQUIRED_FILES[@]}"; do
    if [ -f "${OUTDIR}/${RF}" ]; then
        echo "    ✅ ${RF}"
    else
        echo "    ❌ ${RF} MISSING"
        ALL_PRESENT=false
    fi
done

INDEX_SIZE=$(du -sh ${OUTDIR} 2>/dev/null | cut -f1)

echo ""
echo "============================================="
echo "  Salmon Index Build Complete"
echo "============================================="
echo ""
echo "  Organism:      ${ORGANISM} (${ORGANISM_NAME})"
echo "  Index type:    Decoy-aware (gentrome)"
echo "  Index size:    ${INDEX_SIZE}"
echo "  Build time:    ${BUILD_DURATION} minutes"
echo "  Decoys:        ${DECOY_COUNT} sequences"
echo "  Location:      ${OUTDIR}"
echo ""

if [ "${ALL_PRESENT}" = true ]; then
    echo "  ✅ All index files present and verified"
    echo ""
    echo "  Update genomes.config to use this index:"
    echo "    Uncomment this line in configs/institutional/genomes.config:"
    echo "      salmon_index = '${OUTDIR}'"
else
    echo "  ❌ Some index files are missing — build may have been incomplete"
fi

echo ""
echo "============================================="

# ---- Log ----
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | SALMON_INDEX | ${ORGANISM} | ${BUILD_DURATION}min | ${INDEX_SIZE} | ${OUTDIR}" \
    >> ${BASE}/logs/system/reference_builds.log
