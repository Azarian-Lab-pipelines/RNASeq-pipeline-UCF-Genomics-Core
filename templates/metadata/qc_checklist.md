# QC Review Checklist

**Project:** __PROJECT_ID__
**PI:** __PI_NAME__
**Analyst:** __ANALYST__
**Date reviewed:** _______________

---

## Pre-Analysis Checks
- [ ] Samplesheet validated (no errors from validate_samplesheet.py)
- [ ] FASTQ files verified (correct count, naming, gzip integrity)
- [ ] Correct genome and annotation selected
- [ ] Pipeline parameters reviewed and appropriate
- [ ] Library type confirmed with PI (polyA / riboZero / totalRNA)

## Raw Read QC (FastQC)
- [ ] Per-base quality scores acceptable (>Q30 for most bases)
- [ ] No significant adapter contamination
- [ ] GC content distribution looks normal for organism
- [ ] No overrepresented sequences of concern
- [ ] Total read count sufficient for downstream analysis

## Trimming (Trim Galore)
- [ ] Adapter removal successful
- [ ] Minimal read loss after trimming (<10% typical)
- [ ] Post-trimming quality scores improved

## Alignment (STAR)
- [ ] Mapping rate >70% for all samples
- [ ] Uniquely mapped reads >60%
- [ ] Multi-mapped reads within expected range
- [ ] No samples with abnormally low alignment rate
- [ ] Consistent mapping rates across replicates

## Quantification (Salmon)
- [ ] Assigned gene rate >50%
- [ ] Gene count matrix generated successfully
- [ ] TPM matrix generated successfully
- [ ] Consistent library sizes across replicates

## Alignment QC
- [ ] Duplication rate acceptable (<60% for RNA-seq)
- [ ] Gene body coverage uniform (5' to 3')
- [ ] Strandedness consistent across all samples
- [ ] Read distribution shows expected exonic enrichment
- [ ] Library complexity adequate (Preseq)

## Sample QC
- [ ] PCA shows expected grouping by condition (DESeq2 QC)
- [ ] No unexpected batch effects
- [ ] No outlier samples
- [ ] Replicate correlation is high

## Contamination (if Kraken2 enabled)
- [ ] No unexpected organisms detected
- [ ] Expected organism is dominant

## Overall Assessment

**Decision:** [ ] PASS  [ ] FAIL  [ ] CONDITIONAL PASS  [ ] RERUN NEEDED

**Notes:**

_____________________________________________________________

_____________________________________________________________

**Reviewer signature:** ____________________  **Date:** ________
