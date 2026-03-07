# ============================================================
# COMPLETE EXECUTION GUIDE
# Run these commands in order on your HPC
# ============================================================

# 1. Navigate to your working directory
cd /home/ja581385/genomics_core/

# 2. Create all directories (Step 1 script)
bash 01_setup_directories.sh

# 3. Create all the files above
# (You should have already created all the files from Steps 2-8)
# Verify everything is in place:
echo "=== Checking file structure ==="
find downstream_rnaseq -type f | sort

# 4. Build the container (CRITICAL - do this first, takes 30-90 min)
cd downstream_rnaseq/containers
sbatch build_container.sh

# Monitor build progress:
squeue -u ja581385
# Check logs:
tail -f build_container_*.out

# 5. Verify container works (after build completes)
module load apptainer
apptainer exec rnaseq_report.sif R -e "
  library(DESeq2); library(clusterProfiler); library(plotly)
  cat('All critical packages OK\n')
"
apptainer exec rnaseq_report.sif quarto --version

# 6. Create test data (optional but recommended)
cd /home/ja581385/genomics_core/downstream_rnaseq/test
apptainer exec ../containers/rnaseq_report.sif Rscript create_test_data.R

# 7. Run test analysis
cd /home/ja581385/genomics_core/downstream_rnaseq
./run_analysis.sh \
  --counts test/testdata/salmon.merged.gene_counts.tsv \
  --metadata test/testdata/samplesheet.csv \
  --organism human \
  --project "Test_Run" \
  --outdir test/test_output

# Monitor:
squeue -u ja581385
tail -f downstream_*.out

# 8. Check output
ls -la test/test_output/report/

# ============================================================
# FOR REAL DATA (after nf-core rnaseq completes):
# ============================================================

# Find your nf-core output count matrix:
# Typically at: <nfcore_outdir>/star_salmon/salmon.merged.gene_counts.tsv

# Create your metadata file (must have sample_id and condition columns):
# sample_id,condition
# Sample1,Control
# Sample2,Control
# Sample3,Treatment
# Sample4,Treatment

# Run the pipeline:
./run_analysis.sh \
  --counts /path/to/nfcore_results/star_salmon/salmon.merged.gene_counts.tsv \
  --metadata /path/to/my_samplesheet.csv \
  --organism human \
  --project "My_Actual_Project" \
  --pi "Dr. Smith" \
  --outdir /path/to/results/downstream
