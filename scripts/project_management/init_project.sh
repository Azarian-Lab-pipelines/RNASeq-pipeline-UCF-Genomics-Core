#!/bin/bash
# =============================================================================
# Initialize a New RNA-seq Project
#
# Creates a complete project directory with all required files:
#   - Samplesheet template
#   - Pipeline parameters (organism-specific)
#   - SLURM launch script
#   - MultiQC custom config
#   - Project metadata
#   - QC review checklist
#   - README
#
# All template placeholders (__PROJECT_ID__, __PI_NAME__, etc.)
# are replaced with actual values.
#
# Usage:
#   ./init_project.sh <PROJECT_ID> <PI_NAME> <ORGANISM> <ANALYST>
#
# Examples:
#   ./init_project.sh PROJ-2026-001 "Dr.Smith" GRCh38 "Jane Doe"
#   ./init_project.sh PROJ-2026-002 "Dr.Jones" GRCm39 "John Doe"
#
# Supported organisms: GRCh38 (Human), GRCm39 (Mouse)
# =============================================================================

set -euo pipefail

# ---- Parse arguments ----
PROJECT_ID="${1:?ERROR: Provide PROJECT_ID (e.g., PROJ-2026-001)}"
PI_NAME="${2:?ERROR: Provide PI_NAME (e.g., Dr.Smith)}"
ORGANISM="${3:?ERROR: Provide ORGANISM (GRCh38 or GRCm39)}"
ANALYST="${4:?ERROR: Provide ANALYST name (e.g., Jane Doe)}"

DATE=$(date +%Y-%m-%d)
BASE="/home/ja581385/genomics_core"
PROJECT_DIR="${BASE}/projects/active/${PROJECT_ID}"
TEMPLATE_DIR="${BASE}/templates"

# ---- Validate organism ----
case ${ORGANISM} in
    GRCh38)
        ORGANISM_NAME="Human"
        ANNOTATION="GENCODE v44"
        ;;
    GRCm39)
        ORGANISM_NAME="Mouse"
        ANNOTATION="GENCODE vM33"
        ;;
    *)
        echo "ERROR: Unknown organism '${ORGANISM}'."
        echo "  Supported organisms:"
        echo "    GRCh38  — Human (GENCODE v44)"
        echo "    GRCm39  — Mouse (GENCODE vM33)"
        exit 1
        ;;
esac

# ---- Check if project already exists ----
if [ -d "${PROJECT_DIR}" ]; then
    echo "ERROR: Project already exists: ${PROJECT_DIR}"
    echo "  To recreate, first remove or rename the existing directory."
    exit 1
fi

echo "============================================="
echo "  Initializing RNA-seq Project"
echo "============================================="
echo ""
echo "  Project ID:  ${PROJECT_ID}"
echo "  PI:          ${PI_NAME}"
echo "  Organism:    ${ORGANISM} (${ORGANISM_NAME}, ${ANNOTATION})"
echo "  Analyst:     ${ANALYST}"
echo "  Date:        ${DATE}"
echo "  Location:    ${PROJECT_DIR}"
echo ""

# ---- Create project directory structure ----
echo "[1/8] Creating directory structure..."
mkdir -p ${PROJECT_DIR}/{data/fastq,results,logs,docs,qc_review}
echo "  ✅ Directories created"

# ---- Copy and customize samplesheet template ----
echo "[2/8] Setting up samplesheet template..."
cp ${TEMPLATE_DIR}/samplesheets/samplesheet_PE.csv ${PROJECT_DIR}/samplesheet.csv
echo "  ✅ samplesheet.csv (edit with your sample information)"

# ---- Copy and customize parameters template ----
echo "[3/8] Setting up pipeline parameters..."
cp ${TEMPLATE_DIR}/params/rnaseq_params_${ORGANISM}.yaml ${PROJECT_DIR}/params.yaml
sed -i "s|__PROJECT_ID__|${PROJECT_ID}|g" ${PROJECT_DIR}/params.yaml
sed -i "s|__PI_NAME__|${PI_NAME}|g" ${PROJECT_DIR}/params.yaml
sed -i "s|__ANALYST__|${ANALYST}|g" ${PROJECT_DIR}/params.yaml
sed -i "s|__DATE__|${DATE}|g" ${PROJECT_DIR}/params.yaml
echo "  ✅ params.yaml (${ORGANISM} — ${ORGANISM_NAME})"

# ---- Copy and customize launch script ----
echo "[4/8] Setting up SLURM launch script..."
cp ${TEMPLATE_DIR}/launch_scripts/launch_rnaseq.sh ${PROJECT_DIR}/launch_pipeline.sh
sed -i "s|__PROJECT_ID__|${PROJECT_ID}|g" ${PROJECT_DIR}/launch_pipeline.sh
sed -i "s|__PI_NAME__|${PI_NAME}|g" ${PROJECT_DIR}/launch_pipeline.sh
sed -i "s|__ANALYST__|${ANALYST}|g" ${PROJECT_DIR}/launch_pipeline.sh
sed -i "s|__DATE__|${DATE}|g" ${PROJECT_DIR}/launch_pipeline.sh
chmod +x ${PROJECT_DIR}/launch_pipeline.sh
echo "  ✅ launch_pipeline.sh"

# ---- Copy and customize MultiQC config ----
echo "[5/8] Setting up MultiQC configuration..."
cp ${TEMPLATE_DIR}/multiqc/multiqc_config.yaml ${PROJECT_DIR}/multiqc_config.yaml
sed -i "s|__PROJECT_ID__|${PROJECT_ID}|g" ${PROJECT_DIR}/multiqc_config.yaml
sed -i "s|__PI_NAME__|${PI_NAME}|g" ${PROJECT_DIR}/multiqc_config.yaml
sed -i "s|__ORGANISM__|${ORGANISM} (${ORGANISM_NAME})|g" ${PROJECT_DIR}/multiqc_config.yaml
sed -i "s|__ANALYST__|${ANALYST}|g" ${PROJECT_DIR}/multiqc_config.yaml
sed -i "s|__DATE__|${DATE}|g" ${PROJECT_DIR}/multiqc_config.yaml
echo "  ✅ multiqc_config.yaml"

# ---- Generate project metadata ----
echo "[6/8] Setting up project metadata..."
cp ${TEMPLATE_DIR}/metadata/project_metadata.yaml ${PROJECT_DIR}/project_metadata.yaml
sed -i "s|__PROJECT_ID__|${PROJECT_ID}|g" ${PROJECT_DIR}/project_metadata.yaml
sed -i "s|__PI_NAME__|${PI_NAME}|g" ${PROJECT_DIR}/project_metadata.yaml
sed -i "s|__ANALYST__|${ANALYST}|g" ${PROJECT_DIR}/project_metadata.yaml
sed -i "s|__ORGANISM__|${ORGANISM}|g" ${PROJECT_DIR}/project_metadata.yaml
sed -i "s|__DATE__|${DATE}|g" ${PROJECT_DIR}/project_metadata.yaml
echo "  ✅ project_metadata.yaml"

# ---- Copy QC review checklist ----
echo "[7/8] Setting up QC review checklist..."
cp ${TEMPLATE_DIR}/metadata/qc_checklist.md ${PROJECT_DIR}/qc_review/qc_checklist.md
sed -i "s|__PROJECT_ID__|${PROJECT_ID}|g" ${PROJECT_DIR}/qc_review/qc_checklist.md
sed -i "s|__PI_NAME__|${PI_NAME}|g" ${PROJECT_DIR}/qc_review/qc_checklist.md
sed -i "s|__ANALYST__|${ANALYST}|g" ${PROJECT_DIR}/qc_review/qc_checklist.md
echo "  ✅ qc_review/qc_checklist.md"

# ---- Create project README ----
echo "[8/8] Creating project README..."
cat > ${PROJECT_DIR}/README.md << READMEEOF
# ${PROJECT_ID}

| Field | Value |
|---|---|
| PI | ${PI_NAME} |
| Organism | ${ORGANISM} (${ORGANISM_NAME}) |
| Annotation | ${ANNOTATION} |
| Analyst | ${ANALYST} |
| Date Created | ${DATE} |
| Pipeline | nf-core/rnaseq v3.23.0 |
| Aligner | STAR → Salmon |
| Status | Initialized |

## Directory Structure

\`\`\`
${PROJECT_ID}/
├── samplesheet.csv          # Input sample information
├── params.yaml              # Pipeline parameters
├── launch_pipeline.sh       # SLURM submission script
├── multiqc_config.yaml      # Custom MultiQC report config
├── project_metadata.yaml    # Project tracking metadata
├── data/
│   └── fastq/               # Raw FASTQ files (symlinked)
├── results/                  # Pipeline output
├── logs/                     # Execution logs and reports
├── docs/                     # Project-specific documentation
└── qc_review/
    └── qc_checklist.md      # QC review checklist
\`\`\`

## Quick Start

\`\`\`bash
# 1. Place FASTQ files
ln -s /path/to/your/*.fastq.gz data/fastq/

# 2. Generate samplesheet from FASTQ directory
python ${BASE}/scripts/validation/generate_samplesheet.py \\
    --input_dir data/fastq/ \\
    --output samplesheet.csv

# 3. Validate samplesheet
python ${BASE}/scripts/validation/validate_samplesheet.py samplesheet.csv

# 4. Review parameters
vim params.yaml

# 5. Launch pipeline
sbatch launch_pipeline.sh

# 6. Monitor
squeue -u \$(whoami)
tail -f logs/nextflow_run_*.log
\`\`\`
READMEEOF
echo "  ✅ README.md"

# ---- Log project creation to facility audit log ----
mkdir -p ${BASE}/logs/audits
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | CREATED | ${PROJECT_ID} | PI:${PI_NAME} | ${ORGANISM} | ANALYST:${ANALYST}" \
    >> ${BASE}/logs/audits/project_audit.log

# ---- Summary ----
echo ""
echo "============================================="
echo "  ✅ Project initialized successfully!"
echo "============================================="
echo ""
echo "  Project directory: ${PROJECT_DIR}"
echo ""
echo "  Files created:"
ls -la ${PROJECT_DIR}/ | grep -v "^total\|^\.\." | sed 's/^/    /'
echo ""
echo "  Next steps:"
echo "    1. Place FASTQ files:"
echo "       ln -s /path/to/your/*.fastq.gz ${PROJECT_DIR}/data/fastq/"
echo ""
echo "    2. Generate samplesheet from FASTQ directory:"
echo "       python ${BASE}/scripts/validation/generate_samplesheet.py \\"
echo "           --input_dir ${PROJECT_DIR}/data/fastq/ \\"
echo "           --output ${PROJECT_DIR}/samplesheet.csv"
echo ""
echo "    3. Validate samplesheet:"
echo "       python ${BASE}/scripts/validation/validate_samplesheet.py \\"
echo "           ${PROJECT_DIR}/samplesheet.csv"
echo ""
echo "    4. Review parameters:"
echo "       vim ${PROJECT_DIR}/params.yaml"
echo ""
echo "    5. Launch pipeline:"
echo "       cd ${PROJECT_DIR} && sbatch launch_pipeline.sh"
echo ""
echo "============================================="
