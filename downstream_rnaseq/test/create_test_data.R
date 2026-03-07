#!/usr/bin/env Rscript

# =============================================================================
# Create minimal test dataset for pipeline validation
# =============================================================================

set.seed(42)

outdir <- "testdata"
dir.create(outdir, showWarnings = FALSE)

# --- Simulate count matrix ---
n_genes <- 2000
n_samples <- 6
gene_ids <- paste0("ENSG", sprintf("%011d", 1:n_genes))
gene_names <- paste0("Gene", 1:n_genes)
sample_names <- c("Ctrl_1", "Ctrl_2", "Ctrl_3", "Treat_1", "Treat_2", "Treat_3")

# Base expression
base_counts <- matrix(
  rnbinom(n_genes * n_samples, mu = 500, size = 1),
  nrow = n_genes
)

# Add differential expression for first 200 genes
base_counts[1:100, 4:6] <- base_counts[1:100, 4:6] * 4  # upregulated
base_counts[101:200, 4:6] <- round(base_counts[101:200, 4:6] * 0.25)  # downregulated

colnames(base_counts) <- sample_names
count_df <- data.frame(
  gene_id = paste0(gene_ids, ".1"),  # with version
  gene_name = gene_names,
  base_counts
)

write.table(count_df, file.path(outdir, "salmon.merged.gene_counts.tsv"),
            sep = "\t", quote = FALSE, row.names = FALSE)

# --- Create metadata ---
metadata <- data.frame(
  sample_id = sample_names,
  condition = rep(c("Control", "Treatment"), each = 3),
  replicate = rep(1:3, 2)
)
write.csv(metadata, file.path(outdir, "samplesheet.csv"), row.names = FALSE)

cat("Test data created in:", file.path(getwd(), outdir), "\n")
cat("  - salmon.merged.gene_counts.tsv\n")
cat("  - samplesheet.csv\n")
