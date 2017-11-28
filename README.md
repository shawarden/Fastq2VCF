# About

- This is an alignment pipeline for use on a SLURM cluster. It uses BWA, SAMTools, Picard and GATK to carry paired end FASTQ files through to g.vcf
- Basic flow is FASTQ -> BWA primary alignment -> Picard SortSAM -> Picard Mark Duplicates -> GATK Base Recalibration -> GATK PrintReads -> GATK DepthOfCoverage -> GATK Haplotype caller
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

## 2016-11-18

### Removed
- Contig block merge as Picard MarkDuplicates takes multiple inputs and outputs correctly sorted BAM with no significant penalty.
- Removed array depedency correspondence from depCheck function as this doesn't work for cases of partial completion in array chains.

### Changed
- Begun migration to HG38 with Alt-Aware alignment.
- Switched alignment phase to use RAM disk instead of temp storage to minimize network traffic while not risking running out of node temp space.
- Java memory allocation due to ram-disk usage requirements.
- storeMetrics function to try and output job statistics (cpu,mem,etc usage) Not much luck here as sstat seem kinda broken and sacct is slow to update.
- Minor code cleanup.

### Added
- Job position tracking.
- Initial Job auto-restart mechanism.


## 2016-10-03

### Fixed
- Cleanup gzip command on folder structure.
- Extracted read-group from read files for alignment since readsplit doens't generate them any more.


## 2016-09-30

### Added
- Job cleanup step to roll up output and remove left-overs.

### Changed
- Transfer jobs will wait until transfer is complete before exiting.


## 2016-09-27

### Fixed
- Cancelling extra alignment blocks causes merge step to be cancelled.
- Removed piped output from ContigMerge to MarkDuplicates as this isn't handled well.

### Changed
- Merged ContigMerge and MarkDuplicate functions to cut task count in half: 1x84 vs 2x84
- Merged BQSR and PrintRead functions to cut task count in half: 1x84 vs 2x84

## 2016-09-19

### Changed
- Merged initial three steps into 1 to save BLOCKS x CONTIGS job submissions. ~30m Primary Alignment, ~30m SortSAM and 84x <10m Contig split takes <120m. Will padd to 240m as sometimes nodes are bogged.
- Migrated second phase Merge, MarkDup to CatVariants to main spool script as we don't have to collect contig split dependencies any more.


## 2016-09-08

### Fixed
- Exit code not being passed correctly by cmdFail function.

### Added
- Test module for picard GatherVcfs as an alternative to CatVariants. Nul cahar issues abound!


## 2016-09-06

### Added
- Workflow pdf

### Fixed
- Missing ! for file transfer failure detection.
- Missing error messages on job failure.


## 2016-08-19

### Added
- Automatic re-submission of job when SIGTERM detected as job is about to be killed for exceeding walltime. Resubmitted job has double the wall-time. This will still result in a failure unless I can dynamically update the subsequent process's dependency.

### Changed
- outFile function will exit cleanly if .done file exists. Will allow overwrite if output already exists but no done file found as likely interupted.

### Fixed
- ReadSplit awk system call missing a quote.


## 2016-08-18

### Changed
- Increase submissions delay to 6 seconds per submissions to hard block at 600/hour submissions limit of 6 seconds per submissions instead of 20/minutes's 3 seconds per job submission.
- SIGTERM trap incorporated into storeMetrics output as EXIT trap is called even on error exit.
- Reduced ContigSplit from 2 cores to 1.

### Fixed
- tieTaskDeps incorrectly unlocking child array elements repeatedly if current cycle found no match.
- ReadSplit not stopping on block spin-off failure.


## 2016-08-17

### Changed
- DepthOfCoverage runtime doubled from 30m to 60m as exceeding runtime allowance with ~4m to go.
- Set Gender haplotypecalling to correct array position. Cosmetic only as operational is defined via command-line.
- Rearranged ReadSplit logging output to more logical sequence.
- Merged Spool_Sample's file size detection for read pair to facilitate overall walltime multiplier based on input file size vs calibrated file size.
- Moved SIGTERM metric entry to end of line to maintain output consistency.
- Moved storeMetrics function to exit trap.

### Fixed
- Array elements that do not have a matching element in the previous array were left dependent on the entire previous array


## 2016-08-16

### Added
- ExitCodes. 10: IO error. 15: Pipeline command error. 20: File move error.
- Gender contig definition in baserefs to allow seemless haplotypecaller array.
- Base Walltime multiplier to baserefs to allow per-contig walltimes in dispatch function.
- Signal trap for pre-kill event detection and logging of processes that are about to be killed.

### Changed
- Runtime for ContigSplit increased to 30m as it seems to exceed 15m on some nodes.
- Walltime values converted to minutes for easy manipulation by dispatch function.

### Fixed
- Align & Sort purge taking purging one too many jobs.

### Removed
- Non arrayed list of contigs. No point in having the same data twice.


## 2016-08-12

### Fixed
- Printreads input validation missing a fi to close close the if.
- Check-blocks erroneous output.

### Changed
- Metrics logging output format


## 2016-08-11

### Changed
- Moved file transfer script into main script body to prevent un-needed extra job submissions. The transfers are handed off to Globus so take virtually no time. This happens after the file has been moved to the storage folder so if transfer fails, you don't have to start from scratch.
- Changed in-script --array definition to more accurately reflect their general/ideal submission state. The array is still generated dynamically by the submission script.

### Fixed
- CheckBlock reading 1 block to far when restarted a from a point after ReadSplit had completed: blocks - 1 cuz they start at 0

### Added
- Submission delay mechanism so we don't submit a job within a certain amount of time of the previous.

### Removed
- File transfer scripts from main check_block script.


## 2016-08-10

### Changed
- Increased ReadSplit block size and run-times by 50% to try and fit under NeSI submission rate limits.

### Added
- Global job category resource definitions. Second attempt.
- Delay on script re-start to reduce failures due to job submission rate limit.

## 2016-08-09

### Changed
- SortSam runtime reduced from 3 hours to 1 hour as highest seen runtime is 45 minutes.
- Replaced Align and Sort with array variant.

### Fixed
- Alignment array not collecting read-group header info for file-name pickup: cat block/readgroup.file in job script.
- Minimum meory being exceeded in java VM: specified memory is 1gb less than allocated.
- Sort array not copying .bai file to storage area after job completion.

## 2016-08-08

### Changed
- Moved files to their own repo folder for commandline commits etc.
- Moved BWA alignment command to variable then execute with eval. This allows seemless echoing to log on changes.
- Format of ReadSplit block number passed to check_block to allow array manipulation. Can't have five digit element counts can we?
- ReadSplit runtime reduced from 5 hours to 2.5 hours as highest seen runtime is 2 hours.
- PrimaryAlign runtime reduced 2 hours to 45 minutes as highest seen runtime is 20 minutes.
- Moved Alignment and Sort array dispatch to be above ReadSplit so we can pass ReadSplit the array job ids.

### Added
- Alignment and Sort arrays submitted at start point. 1000 elements each that are purged of excess jobs once ReadSplit completes.

### Fixed
- cmdFailed function doesn't function as expected. Reverted to if ! ${CMD}; then...


## 2016-08-04

### Changed
- HaplotypeCaller array elements tied to PrintReads array elements.
- Migrated file IO validation to baserefs.sh
- Large output files are first written to local node's tmp space, then moved to output folder on completion.
- ReadSplit launches as array job.

### Fixed
- BaseRecalibrator array job using singleton out and err file definitions.
- Job output not printing job/array ids correctly.

### Added
- File exist checking to each sbatch script with detailed output.
- Clean up sorted block output when all contig splitting has completed after any mergecontig runs


## 2016-08-03

### Fixed
- DepthOfCoverage and HaplotypeCaller input and output incorrectly defined.
- DepthOfCoverage no being passed the capture platform correctly.
- Array element linker throwing errors when previous array is empty which occurs when all previous array was alread completed. Gotta quote those possibly empty inputs!
- HaplotypeCaller seeking incorrect input for non-arrayed Sex chromosome jobs

### Changed
- Array element linker can accept non numerical values to compare. Never know if/when that'll come in handy.

### Added
- Late stage sample fingerprinting sequence. (haplotypecaller -> selectvariants)

### Removed
- Readgroup variable from coverage mapping. Doesn't do anything.
- HaplotypeCaller array (autosomal and centromere contigs) to DepthOfCoverage array output and delayed start-time as no dependency tying required.


## 2016-08-02

### Changed
- MarkDuplicates, BaseRecalibrator, PrintReads, DepthOfCoverage and Haplotype caller (non MT or sex Chr) to array submission and tied array element dependency to matching element in previous array. Testing shows individual array element will wait only for their own dependency before starting.
- Separated CatReads from ReadIndex to allow job chaining.
- CatReads to sequential job chain for catting -> transfer reads & ReadIndex.
- ReadIndex to sequential job chain for indexing -> transfer index.
- CatVariants to sequential job chain for catting -> transfer variants & transfer index.

### Added
- Function comments, because everyone loves comments.
- tieTaskDeps function to tie a given task array's dependencies to the previous task array's matching element via SCONTROL UPDATE.
- Start-time delay for subsequent arrays so they cannot start until per-array-element dependencies are set correctly.

### Removed
- Initial job dependencies for subsequent arrays as these will prevent the entire array from starting until the entire previous array has completed.

### Fixed
- MergeContig not collecting ContigSplit array dependencies.
- MergeContig trying to write to wrong location.


## 2016-08-01

### Changed
- Reformatted changelog/readme for github display.
- MergeContig converted to array submission method.
- Logging output method to sequencial instead of buffered to more accurately represent submission rate.
- File path simplification to enable better clean-up later on.

### Added
- About section to README.md
- Delay on each contig for markdup to haplotype segment as job submission rate exceeded limits.
- Skip message for X, Y and MT contigs in primary calling loop.


## 2016-07-29

### Changed
- ContigSplit function to be array job. Now submits 1 job array per block instead of 84. Array is dynamically created based on .done file existence.
- Log output header to 2 character combos. RS: Read Split, PA: Primary alignment, SS: SortSAM, etc...
- Log output to single line per post-merge contig.
- changelot.txt to README.md so changelog is visible.

### Merged
- CatReads and CatReadsIndex jobs into 1. Increase walltime to accomodate both jobs. ~30m cat, 45m index.


## 2016-7-28

### Added
- Contig Count to baserefs.sh


## 2016-7-27

### Fixed
- ASP seeing a failed grep as a failed ssh connection. grep failure is ExitCode 1, ssh network failure exitcode is > 1


## 2016-07-25

### Added
- Check for job submission failures. Pipeline will exit 1 in that event.
- Local spooler lauching sequencial jobs without input.


## 2016-07-22:

### Fixed
- X sub contigs not being linked correctly in their folders .../X/X:1-2699520.g.vxf.gz, etc.
- MT contig being included in HaplotypeCaller after removing input collection from primary loop.


## 2016-07-21:

### Changed
- CatVarInputs to generate independent of main cycle so X&Y don't need to be resorted by CatVar.
- Global temp directory to be SLURM provided one so minimize chances of job fail due to temp directory failure.
- CatPrintReads walltime from 3 hours to 1. 6x to 2x 30m known run-time.
- CatPrintReadsIndex walltime from 1 hour to 1.5. 1.25x to 2x 45m known run-time.
- HaplotypeCaller walltime from 6 hours to 3 as parallelization with -nct has proven effective and cpus-per-task & mem-per-cpu from 4x8192 to 8x4096.
- CatVariants walltime to 3 hours as longest runtime is ~2 hours
- SortSam walltime from 3 hours to 1.5 as longest runtime is 30 minutes
- Mark Duplicates memory allocation from 32G to 16G as no different in runtime and walltime from 6 hours to 2 as longest runtime is just over 1 hour.

### Added
- scriptFailed function to all non-0 exit points.
- scontrol show job $SLURM_JOBID to scriptFailed function.
- Reads file size to job name to size-vs-speed filtering.
- Automatic sample progression. (ASP)


## 2016-07-20:

### Added
- scriptFailed function to collect basic node data when a job fails for any reason.

### Fixed
- Coverage & Gender Determination not collecting GL* PrintRead dependencies.

### Changed
- HaplotypeCaller cpu-per-task & mem-per-cpu from 2x32 to 4x8 to boost parallelization but reduce overall memory requirement as this extra memory no longer affects run-time.
- SortSam mem-per-cpu from 32G to 16G as this has no effect on runtime.


## 2016-07-19:

### Created
- CatPrintReads & Index scripts to replace MergeReads. Picard MergeSamFiles takes 6 to 10 hours to complete. SAMTools Cat takes 30 minutes.

### Added
- Global temp directory definition to minimise network thrashing.


## 2016-07-18:

### Changed
- HaplotypeCaller cpu-per-task from 1 to 2 to test if -nct parallelization has been resolved in this version of GATK.


## 2016-07-15:

### Added
- SLURM based parallelization calculation to GATK arguments.

### Changed
- HaplotypeCaller mem-per-cpu from 16G to 32G to test if extra memory decreases run-time


## 2016-07-14:

### Added
- parallelization option to HaplotypeCaller function as this has been resolved in GATK and it will reduce runtime.


## 2016-07-12:

### Added
- duplicate metrics storage for sample.


## 2016-07-11:

### Added
- global module version definitions.


## 2016-07-07:

### Added
- check for previously finished jobs.


## 2016-07-05:

### Added
- SLURM based memory calculation to java arguments.


## 2016-07-01:

### Added
- FASTQ scan definitions.


## 2016-06-28:

### Added
- contig definition to for automation.


## 2016-06-13:

### Added
- base reference file to reduce data replication across multiple scripts.


## 2016-06-08:

### Removed
- trimming process as BWA & GATK tools can handle quality based trimming and adapters.


## 2016-06-02:

### Added
- Cluster project.

# To do

## Minimal
- Continue to work out minimum requirement to obtain 1 hour max runtimme per segment within high partition.
- Build list of wall-time ratios for each job type and contig to set per-contig wall-times.
- Determine sample coverage based wall-times for dynamic allocation.

## Multi-sample
- Build multi-sample pipeline with identity comparison and merge function.

## Fingerprint
- Add fingerprinting function post bam collection?

## Auto-recovery
- Add ability to re-try a job if it fails because of a node issues. Could trigger a chain of dependant jobs to take it as far as it can outwith the overall process. This will minimize delay on restarting the job later on.
- Migrate input file collection to slurm script. This will allow failed jobs to possibly be run in time for the catvar or catreads functions to collect them. Still wont be 100% effective as job execution depends on cluster availability. Should work well for smaller contigs.

## Tidy up
- Re-write everything. Check-Blocks is a bloated mess.
