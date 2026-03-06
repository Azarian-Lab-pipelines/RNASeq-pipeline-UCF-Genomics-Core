#!/bin/bash
#SBATCH --job-name=build_star_idx
#SBATCH --output=/home/ja581385/genomics_core/logs/system/star_index_%j.out
#SBATCH --error=/home/ja581385/genomics_core/logs/system/star_index_%j.err
#SBATCH --time=12:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --mail-type=ALL
#SBATCH --mail-user=ja581385@ucf.edu
# =============================================================================
# Build STAR Genome Index
#
# STAR is bundled inside a mulled multi-tool container (STAR + SAMtools + gawk)
# in the nf-core pipeline. The container has a hashed name like
# blobs-sha256-*.img rather than a name containing "star".
#
# This script searches all available .img files to find the one
# containing STAR, then uses it to build the genome index.
#
# Usage:
#   sbatch build_star_index.sh <ORGANISM> [SJDB_OVERHANG]
#
# Examples:
#   sbatch build_star_index.sh GRCh38 149
#   sbatch build_star_index.sh GRCm39 149
# =============================================================================

set -euo pipefail

ORGANISM="${1:?ERROR: Provide organism (GRCh38 or GRCm39)}"
OVERHANG="${2:-149}"
BASE="/home/ja581385/genomics_core"
REF_DIR="${BASE}/references"
THREADS=${SLURM_CPUS_PER_TASK:-16}

# ---- Environment ----
module unload java 2>/dev/null || true
source ${BASE}/bin/activate_genomics_core.sh
module load singularity 2>/dev/null || module load apptainer 2>/dev/null || true

# ---- Set organism-specific paths ----
case ${ORGANISM} in
    GRCh38)
        FASTA="${REF_DIR}/genomes/GRCh38/GRCh38.primary_assembly.genome.fa"
        GTF="${REF_DIR}/genomes/GRCh38/gencode.v44.primary_assembly.annotation.gtf"
        ORGANISM_NAME="Human"
        ANNOTATION="GENCODE v44"
        ;;
    GRCm39)
        FASTA="${REF_DIR}/genomes/GRCm39/GRCm39.primary_assembly.genome.fa"
        GTF="${REF_DIR}/genomes/GRCm39/gencode.vM33.primary_assembly.annotation.gtf"
        ORGANISM_NAME="Mouse"
        ANNOTATION="GENCODE vM33"
        ;;
    *)
        echo "ERROR: Unknown organism '${ORGANISM}'."
        echo "  Supported: GRCh38, GRCm39"
        exit 1
        ;;
esac

OUTDIR="${REF_DIR}/indices/star/${ORGANISM}"

echo "============================================="
echo "  Building STAR Genome Index"
echo "============================================="
echo ""
echo "  Organism:      ${ORGANISM} (${ORGANISM_NAME})"
echo "  Annotation:    ${ANNOTATION}"
echo "  sjdbOverhang:  ${OVERHANG} (ReadLength - 1)"
echo "  Threads:       ${THREADS}"
echo "  FASTA:         ${FASTA}"
echo "  GTF:           ${GTF}"
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
echo "[1/5] Validating input files..."

if [ ! -f "${FASTA}" ]; then
    echo "  ❌ Genome FASTA not found: ${FASTA}"
    echo "  Run first: ./scripts/reference_management/download_references.sh ${ORGANISM}"
    exit 1
fi
FASTA_SIZE=$(ls -lh "${FASTA}" | awk '{print $5}')
echo "  ✅ Genome FASTA: ${FASTA_SIZE}"

if [ ! -f "${GTF}" ]; then
    echo "  ❌ GTF annotation not found: ${GTF}"
    echo "  Run first: ./scripts/reference_management/download_references.sh ${ORGANISM}"
    exit 1
fi
GTF_SIZE=$(ls -lh "${GTF}" | awk '{print $5}')
echo "  ✅ GTF annotation: ${GTF_SIZE}"

# ---- Check if index already exists ----
echo ""
echo "[2/5] Checking for existing index..."

if [ -f "${OUTDIR}/SA" ] && [ -f "${OUTDIR}/Genome" ] && [ -f "${OUTDIR}/genomeParameters.txt" ]; then
    EXISTING_OVERHANG=$(grep "sjdbOverhang" ${OUTDIR}/genomeParameters.txt 2>/dev/null | awk '{print $2}' || echo "unknown")
    echo "  ⚠️  STAR index already exists at: ${OUTDIR}"
    echo "     sjdbOverhang in existing index: ${EXISTING_OVERHANG}"
    echo "     Requested sjdbOverhang: ${OVERHANG}"

    if [ "${EXISTING_OVERHANG}" == "${OVERHANG}" ]; then
        echo "  Existing index matches. Skipping build."
        echo "  To force rebuild: rm -rf ${OUTDIR}"
        exit 0
    else
        echo "  ⚠️  Overhang mismatch. Rebuilding..."
        rm -rf ${OUTDIR}
    fi
else
    echo "  No existing index found. Will build new index."
fi

# ---- Find STAR in Singularity containers ----
echo ""
echo "[3/5] Locating STAR in Singularity containers..."
echo ""
echo "  STAR is packaged inside a mulled multi-tool container (STAR + SAMtools + gawk)"
echo "  alongside other tools. The container has a hashed name, not 'star.img'."
echo "  Searching all available .img files..."
echo ""

STAR_CONTAINER=""

# Search directories where containers might be
SEARCH_DIRS=(
    "${BASE}/singularity_cache"
    "${BASE}/pipelines/nf-core/rnaseq-3.23.0/singularity-images"
)

for SEARCH_DIR in "${SEARCH_DIRS[@]}"; do
    if [ ! -d "${SEARCH_DIR}" ]; then
        continue
    fi

    echo "  Searching: ${SEARCH_DIR}"

    for img in ${SEARCH_DIR}/*.img; do
        if [ ! -f "$img" ]; then
            continue
        fi

        # Quick check: try running STAR --version inside the container
        STAR_CHECK=$(singularity exec "$img" STAR --version 2>/dev/null || echo "")

        if [ -n "${STAR_CHECK}" ]; then
            STAR_CONTAINER="$img"
            echo "  ✅ STAR found in: $(basename $img)"
            echo "     STAR version: ${STAR_CHECK}"
            echo "     Full path: ${img}"
            break 2
        fi
    done
done

# If not found in .img files, try system STAR
if [ -z "${STAR_CONTAINER}" ]; then
    echo ""
    echo "  STAR not found in any .img container."
    echo "  Checking system PATH and modules..."

    # Try loading module
    module load star 2>/dev/null || module load STAR 2>/dev/null || true

    if command -v STAR &> /dev/null; then
        echo "  ✅ STAR found on system: $(which STAR)"
        echo "     Version: $(STAR --version 2>/dev/null || echo 'unknown')"
        STAR_CMD="STAR"
    else
        echo ""
        echo "  ❌ STAR not found anywhere."
        echo ""
        echo "  SOLUTIONS:"
        echo ""
        echo "  Option 1 (RECOMMENDED): Let the pipeline build the index automatically."
        echo "    Simply do not set star_index in params.yaml."
        echo "    The pipeline will build it on the first run."
        echo "    Add 'save_reference: true' to save it for future projects."
        echo ""
        echo "  Option 2: Install STAR via conda"
        echo "    conda create -n star -c bioconda star=2.7.11b"
        echo "    conda activate star"
        echo "    Then re-run this script."
        echo ""
        echo "  Option 3: Pull the STAR container manually"
        echo "    singularity pull star_samtools.sif docker://quay.io/biocontainers/mulled-v2-1fa26d1ce03c295fe2fdcf85831a92fbcbd7e8c2:af29ef53ba508c24832e94ecd5c8d17ef57e6621-0"
        echo "    Then update this script with the container path."
        echo ""
        exit 1
    fi
fi

# Set the STAR command based on what we found
if [ -n "${STAR_CONTAINER}" ]; then
    STAR_CMD="singularity exec -B /lustre/fs1 -B /tmp ${STAR_CONTAINER} STAR"
    echo ""
    echo "  Will use: singularity exec $(basename ${STAR_CONTAINER}) STAR"
fi

# Verify STAR actually works
echo ""
echo "  Verifying STAR executes correctly..."
STAR_VERSION=$(${STAR_CMD} --version 2>/dev/null || echo "FAILED")
if [ "${STAR_VERSION}" == "FAILED" ]; then
    echo "  ❌ STAR command failed to execute."
    echo "  Command tried: ${STAR_CMD}"
    exit 1
fi
echo "  ✅ STAR ${STAR_VERSION} — ready to build index"

# ---- Build index ----
echo ""
echo "[4/5] Building STAR index..."
echo "  This will take 30-60 minutes and use ~40-64 GB RAM."
echo ""

mkdir -p ${OUTDIR}
BUILD_START=$(date +%s)

${STAR_CMD} --runMode genomeGenerate \
    --genomeDir ${OUTDIR} \
    --genomeFastaFiles ${FASTA} \
    --sjdbGTFfile ${GTF} \
    --sjdbOverhang ${OVERHANG} \
    --runThreadN ${THREADS}

BUILD_EXIT=$?
BUILD_END=$(date +%s)
BUILD_DURATION=$(( (BUILD_END - BUILD_START) / 60 ))

echo ""

if [ ${BUILD_EXIT} -ne 0 ]; then
    echo "  ❌ STAR genomeGenerate failed (exit code: ${BUILD_EXIT})"
    exit ${BUILD_EXIT}
fi

# ---- Verify output ----
echo "[5/5] Verifying index..."

REQUIRED_FILES=("SA" "Genome" "genomeParameters.txt" "SAindex" "chrName.txt" "chrLength.txt")
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
echo "  STAR Index Build Complete"
echo "============================================="
echo ""
echo "  Organism:      ${ORGANISM} (${ORGANISM_NAME})"
echo "  STAR version:  ${STAR_VERSION}"
echo "  sjdbOverhang:  ${OVERHANG}"
echo "  Index size:    ${INDEX_SIZE}"
echo "  Build time:    ${BUILD_DURATION} minutes"
echo "  Location:      ${OUTDIR}"
echo ""

if [ "${ALL_PRESENT}" = true ]; then
    echo "  ✅ All index files present and verified"
    echo ""
    echo "  Next step — update genomes.config:"
    echo "    Uncomment this line in configs/institutional/genomes.config:"
    echo "      star_index = '${OUTDIR}'"
else
    echo "  ❌ Some index files missing — build may be incomplete"
fi

echo ""
echo "============================================="

# Log
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | STAR_INDEX | ${ORGANISM} | STAR_${STAR_VERSION} | overhang=${OVERHANG} | ${BUILD_DURATION}min | ${INDEX_SIZE} | ${OUTDIR}" \
    >> ${BASE}/logs/system/reference_builds.log
