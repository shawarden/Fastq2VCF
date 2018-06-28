#!/bin/bash
#SBATCH --job-name		BlockAlign
#SBATCH --time			359
#SBATCH --mem			16G
#SBATCH --cpus-per-task	8
#SBATCH --array			0-999
#SBATCH --error			slurm/BA_%A_%a.out
#SBATCH --output		slurm/BA_%A_%a.out

echo "$(date) on $(hostname)"

export RAMDISK=2

if [ -e $EXEDIR/baserefs.sh ]
then
	source $EXEDIR/baserefs.sh
else
	(echo "WARN: Eecuting without baserefs.sh" 1>&2)
fi

function usage {
cat << EOF

*************************************
* This script will align FastQ files*
* Sorts them and splits by Contig   *
*************************************
*
* usage: $0 options:
*
*********************************
*
* Required:
*   -s [IDLR]      Sample ID string: ID_DNAID_LIBRARY_RUN.
*                  This is used to determine individuals with multiple segments.
*                  Any four unique markers per run is sufficient.
*
* Optional:
*   -i [FILE]      Input file. Specify twice for pair end reads.
*                  If this option is not present files will be sought from
*                  $(pwd)/blocks/...
*   -m             Set multiple runs for this sample ID.
*                  Omit this option on final run for sample.
*                  Final run will gather all matching IDs.
*   -r             Full path to reference file.
*                  Default: /resource/bundles/human_g1k_v37/human_g1k_v37_decoy
*   -o             WIP
*                  Path to final output location.
*                  Defaults to /scratch/$USER
*
*********************************
EOF
}

while getopts "s:i:r:o:m" OPTION
do
	FILE=
	case $OPTION in
		s)
			SAMPLE=${OPTARG}
			(printf "%-22s%s\n" "Sample ID" $SAMPLE 1>&2)
			;;
		m)
			MULTI_RUN="-m"
			(printf "%-22s%s (%s)\n" "Multiple runs" "Enabled" "Omit on final submission" 1>&2)
			;;
		i)
			if [ ! -e ${OPTARG} ]; then
				(echo "FAIL: Input file $OPTARG does not exist!" 1>&2)
				exit 1
			fi
			FILE_LIST=(${FILE_LIST[@]} ${OPTARG})
			(printf "%-22s%s\n" "Input file" $OPTARG 1>&2)
			;;
		r)
			REF=${OPTARG}
			if [ ! -e $REF ]; then
				(echo "FAIL: $REF does not exist" 1>&2)
				exit 1
			fi
			REFA=$REF.fasta
			(printf "%-22s%s\n" "Reference sequence" $REF 1>&2)
			;;
		o)
			OUTPUT_DIR=${OPTARG}
			(printf "%-22s%s\n" "Final datastore" $OUTPUT_DIR 1>&2)
			;;
		?)
			(echo "FAILURE: $0 ${OPTION} ${OPTARG} is not valid!" 1>&2)
			usage
			exit 1
			;;
	esac
done

if [ "${SAMPLE}" == "" ]; then
	echo "FAIL: Missing required parameter!"
	usage
	exit 1
fi

# Block depends on input or array id.
export BLOCK=$(printf "%0${FASTQ_MAXZPAD}d" $SLURM_ARRAY_TASK_ID)
   
OUTPUT=split/${BLOCK}/contig_split
mkdir -p $(dirname ${OUTPUT})

export HEADER="BA"

if [ "${#FILE_LIST[@]}" -eq 2 ]; then
	READ1=${FILE_LIST[0]}
	READ2=${FILE_LIST[1]}
elif [ "${#FILE_LIST[@]}" -eq 1 ]; then
	READ1=${FILE_LIST[0]}
else
	READ1=blocks/R1_${BLOCK}.fastq.gz
	[ -e blocks/R2_${BLOCK}.fastq.gz ] && READ2=blocks/R2_${BLOCK}.fastq.gz
fi

READGROUP=$($CAT_CMD $READ1 | head -1 | awk -F'[@:]' '{print $2"_"$3"_"$4"_"$5"_"$11}' )

echo "$HEADER: $READGROUP $BLOCK $READ1 $READ2 -> $OUTPUT"
jobStats


if [ $(echo "$READGROUP" | wc -w) -gt 1 ]; then
	echo "$HEADER: Too many read-groups!"
	exit 1
fi

# Make sure input and target folders exists and that output file does not!
if ! (INPUT=${READ1}; inFile); then exit $EXIT_IO; fi
if ! (INPUT=${READ2}; inFile); then exit $EXIT_IO; fi
if ! outDirs; then exit $EXIT_IO; fi
#if ! outFile; then exit $EXIT_IO; fi

if [ ! -e sorted/${BLOCK}.done ]; then
	# Get readgroup blocks from either INFO_INFO_INFO_.. or INFO INFO INFO ...
	     INTRUMENT=$(echo ${READGROUP} | awk -F'[[:blank:]_]' '{print $1}')
	INSTRUMENT_RUN=$(echo ${READGROUP} | awk -F'[[:blank:]_]' '{print $2}')
	     FLOW_CELL=$(echo ${READGROUP} | awk -F'[[:blank:]_]' '{print $3}')
	     CELL_LANE=$(echo ${READGROUP} | awk -F'[[:blank:]_]' '{print $4}')
	         INDEX=$(echo ${READGROUP} | awk -F'[[:blank:]_]' '{print $5}')
	
	RG_ID="ID:${INTRUMENT}_${INSTRUMENT_RUN}_${FLOW_CELL}_${CELL_LANE}_${INDEX}"
	RG_PL="PL:Illumina"
	RG_PU="PU:${FLOW_CELL}.${CELL_LANE}"
	RG_LB="LB:${SAMPLE}"
	RG_SM="SM:$(echo ${SAMPLE} | awk -F'[[:blank:]_]' '{print $1}')"
	
	echo $REFA | grep 38 && BWA_REF=$REFA || BWA_REF=$REF
	
	HEADER="PA"
	JOBSTEP=0
	echo "$HEADER: Aligning! $BWA_REF"
	
	module purge
	module load BWA SAMtools
	
	# Pipe output from alignment into sortsam
	CMD="srun $(which bwa) mem -M -t ${SLURM_JOB_CPUS_PER_NODE} -R @RG'\t'$RG_ID'\t'$RG_PL'\t'$RG_PU'\t'$RG_LB'\t'$RG_SM $BWA_REF $READ1 $READ2 | $(which samtools) view -bh - > $SHM_DIR/align_${BLOCK}.bam"
	echo "$HEADER: ${CMD}" | tee -a ../commands.txt
	
	scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${SAMPLE}_Aligning_${BLOCK}
	
	if ! eval ${CMD}; then
		cmdFailed $?
		exit ${JOBSTEP}${EXIT_PR}
	fi
	
	storeMetrics
	
	PA_SECONDS=$SECONDS
	SECONDS=0
	
	HEADER="SS"
	JOBSTEP=1
	
	module purge
	module load picard
	
	CMD="srun $(which java) ${JAVA_ARGS} -jar $EBROOTPICARD/picard.jar SortSam ${PIC_ARGS} ${SORT_ARGS} INPUT=$SHM_DIR/align_${BLOCK}.bam OUTPUT=$SHM_DIR/sorted_${BLOCK}.bam"
	echo "$HEADER: ${CMD}" | tee -a ../commands.txt
	
	scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${SAMPLE}_Sorting_${BLOCK}
	
	if ! ${CMD}; then
		cmdFailed $?
		exit ${JOBSTEP}${EXIT_PR}
	fi
	
	storeMetrics
	
	rm $SHM_DIR/align_${BLOCK}.bam && echo "$HEADER: Purged aligned block: $SHM_DIR/align_${BLOCK}.bam"
else
	echo "$HEADER: Alignment already completed!"
	SS_SECONDS=$SECONDS
	SECONDS=0
fi

HEADER="CS"
JOBSTEP=2
echo "$HEADER: Splitting by contig"

module purge
module load SAMtools

scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${SAMPLE}_SplitByContig_${BLOCK}

# Run multiple samview splits at once. capped at cpus assigned. Initially slow but should speed up with time.
if ! for contig in ${CONTIGARRAY[@]}; do echo $contig; done | (
	srun xargs -I{} --max-procs ${SLURM_JOB_CPUS_PER_NODE} bash -c '{
		OUTPUT="split/${BLOCK}/{}.bam"
		CMD="$(which samtools) view -bh -o ${OUTPUT} $SHM_DIR/sorted_${BLOCK}.bam {}"
		echo "$HEADER: ${CMD}" | tee -a ../commands.txt
		${CMD}
		echo "result: $?"
	}'
); then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi

storeMetrics
JOBSTEP=""
SECONDS=$(($SECONDS + $SS_SECONDS + $PA_SECONDS))

df -ah $SHM_DIR
rm $SHM_DIR/sorted_${BLOCK}.bam && echo "$HEADER: Purged sorted block: $SHM_DIR/sorted_${BLOCK}.bam"

# Remove input files.
if [ "${#FILE_LIST[@]}" -lt "1" ]; then 
	rm ${READ1} ${READ2} && echo "$HEADER: Purged source read block files!"
fi

# Indicate completion.
touch ${OUTPUT}.done
