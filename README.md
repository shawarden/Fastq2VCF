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

## 2019-09-12

### Fixed

- Illumina platinum readgroups have spaces in funny places.

## 2019-09-02

### Fixed

- Contig blocks sort order

### Added

- PCR Free option via local contigs

## 2018-11-05

### Fixed

- Legacy reference to MemPerCore
- split dir referencing root.
- File pathing

### Added

- Manually settable GATK_JAR path.

## 2018-10-10

### Changed

- Increased core use per contig from 7 to 8 as to not choke the cluster.
- Decreased FASTQ_MAXREAD to 40m to decrease chunk size, increasing number of chunks, decreasing time to complete each chunk.
- converted catreadindex script to bash argument format.

### Fixed

- Specifying the same input file throws an error.

## 2018-07-20

### Changed
- baserefs export order to suit external per usercfg file settings
- script tarball named after script folder.
- script folder now automatically determined via dirname
- Tidied up usage output.

### Added
- Exclude version folders from tarball

### Fixed
- Reference dictionary location. 

## 2018-06-11

### Changed
- Rearranged baserefs for better per user config.

## 2018-06-08

### Fixed
- Final output type (-t) not being respected.

### Changed
- MaxWallTime value set appropriately.
- Baseref source from absolute to relative pathing.
- Increased default usage output.

### Added
- Requeue to email list since it results in a failure overall.
- Added mechanism for localized, per user settings via $HOME/fq2vcf.sh file

## 2018-03-14

### Changed
- CPUs Per Task from 8 to 7 to fill Nodes.
- printTime functions to allow usage with stdin.

### Removed
- Annotation from HaplotypeCaller as generates excessive errors in combining phase.

### Fixed
- Spelling mistakes in coverage script.

## 2017-12-13

### Added
- Alternate Max-Walltime for Exome captures
- Variable array task throttle setting.

### Fixed
- Allow REF to retain previous value instead of resetting to default.

## 2017-12-11

### Fixed
- Final out being blank!
- HaplotypeCaller output missing.

### Added
- Pre-Haplotyping Index attempt if .bai missing can fail correctly.
- Platform list to usage page.
- Final output type specification.

### Changed
- Cleaned up log output for gender determination.
- Relevant usage output on incorrect parameter settings.

## 2017-12-04

### Changed
- Switched from mem-per-cpu (--mem-per-cpu) to mem-per-node (--mem)
- Gender determination alert notification contains more information.

### Added
- Automatic email detection can handle ID aliases

## 2017-11-29

-Initial commit
