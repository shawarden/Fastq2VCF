# About

- This is an alignment pipeline for use on a SLURM cluster. It uses BWA, SAMTools, Picard and GATK to carry paired end FASTQ files through to g.vcf
- Basic flow is FASTQ -> BWA primary alignment -> Picard SortSAM -> SAMtools split -> Picard Mark Duplicates -> GATK Base Recalibration -> GATK PrintReads -> GATK DepthOfCoverage -> GATK Haplotype caller
- The FASTQ to BWA step involves breaking the input FASTQ up into an arbitrary number of chunks and passing each of these to their own alignment sequence.
- BWA uses the MEM algorith and passes the output straight to SAMTools to convert to BAM format as a space saving measure with minimal time impact.
- After Picard SortSAM the blocks are then split into separate contigs based on the reference sequence used in alignment and all subsequent steps.
- These contig blocks are then merged into full contigs prior to Picard Mark Duplicates running on each contig separately.
- The contigs travel down through GATK Base Recalibration and into GATK PrintReads.
- The GATK PrintReads function then splits into two separate paths: GATK DepthOfCoverage and SAMTools Cat.
- The SAMTools cat path combines the separate contig BAMs into a single file.
- GATK DepthOfCoverage provides basic Depth of Coverage information for all contigs. It also calculates overall coverage for all autosomal contigs and compares them to the Gender contig coverage to calculate correct X & Y coverage. This allows for correct sample ploidy settings in GATK HaplotypeCaller for X (X0), XY, XX, XXY XYY, XXX, XXXY, etc anueploidies in the event there are any sex chromosome specific disorders or if these disorders can affect expression it will be known.
- For all but the sex and mitochondrial chromosomes, GATK HaplotypeCaller uses a ploidy of 2 and will start immediately after GATK PrintReads is completed.
- The sex chromosomes will be start once all the GATK DepthOfCoverages have completed and are collated by the coverage comparison.
- The Mitochondiral chromosomes are not passed to GATK HaplotypeCaller as their ploidy is in the hundreds.
- The individual contigs from GATK HaplotypeCaller are then merged using GATK CatVariants once all contigs (barring MT) are completed.
- Primary output contains a merge BAM file from GATK PrintReads and a merged genomic VCF from GATK HaplotypeCaller.
- Secondary output contains the coverage map, command history and execution metrics.

# Update history

## 2017-11-29

-Initial commit

