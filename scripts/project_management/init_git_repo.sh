#!/usr/bin/env bash
# =============================================================================
# Initialize Git repository for the genomics core
# =============================================================================

set -euo pipefail

# Configuration
readonly BASE_DIR="/home/ja581385/genomics_core"

# Logging helpers for better visibility
info()  { printf "\e[32m[INFO]\e[0m %s\n" "$*"; }
error() { printf "\e[31m[ERROR]\e[0m %s\n" "$*" >&2; exit 1; }

# 1. Directory Checks
if [[ ! -d "$BASE_DIR" ]]; then
    error "Target directory does not exist: $BASE_DIR"
fi

cd "$BASE_DIR" || error "Failed to change directory to $BASE_DIR"

# 2. Create .gitignore
info "Writing .gitignore rules..."
cat > .gitignore << 'GIEOF'
# Nextflow runtime files
.nextflow/
.nextflow.log*
.nextflow.*
work/
trace.*.txt
timeline.*.html
report.*.html
dag.*.{html,png,svg,jpg}
tower-run.*


# Data - NEVER commit
data/
projects/*/data/
projects/*/results/
projects/active/
projects/completed/
projects/failed/
*.fastq
*.fastq.gz
*.fq.gz
*.bam
*.bai
*.sam
*.cram
*.crai
*.bigWig
*.bw
*.bedGraph
*.vcf
*.vcf.gz
*.bcf
*.tbi
*.csi


# Reference files (too large for git)
references/genomes/
references/indices/
references/kraken2/
references/sortmerna/

# Singularity cache
singularity_cache/
*.sif
*.simg
singularity_cache/
apptainer_cache/
docker/
singularity/
*.img

# Temp and work
tmp/
work/
pipelines/

#env
envs/
logs/
null/
bin/
archive/
software/

# Test outputs
tests/*/test_output*/

# OS artifacts
.DS_Store
Thumbs.db
tmp/
temp/
*.tmp
*.bak
*.sw?
*~
.DS_Store
Thumbs.db
ehthumbs.db
.Apple*
Icon?
._*
.vscode/
.idea/
*.code-workspace
__pycache__/
*.py[cod]
*.egg-info/
.ipynb_checkpoints/

GIEOF

# 3. Initialize Repository
if [[ ! -d ".git" ]]; then
    info "Initializing new Git repository..."
    git init --initial-branch=main
else
    info "Git repository already exists. Skipping initialization."
fi

# 4. Stage and Commit
info "Staging files..."
git add .

# Check if there is actually anything to commit before trying
if git diff --cached --quiet; then
    info "No changes to commit."
else
    info "Creating initial commit..."
    git commit -m "chore: initial commit for Genomics Core RNA-seq infrastructure

- Directory structure for facility-wide RNA-seq processing
- Institutional SLURM configuration"
fi

echo "============================================="
info "Git initialization complete!"
echo "============================================="
