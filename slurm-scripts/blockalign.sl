#!/bin/bash
#SBATCH --job-name	BlockAlign
#SBATCH --time		359
#SBATCH --mem		32G
#SBATCH --cpus-per-task	8
#SBATCH --array		0-999
#SBATCH --error		slurm/BA_%A_%a.out
#SBATCH --output	slurm/BA_%A_%a.out

(echo "$(date) on $(hostname)" 1>&2)
(echo $0 $* 1>&2)

export RAMDISK=2

if [ -e $EXEDIR/baserefs.sh ]
then
	source $EXEDIR/baserefs.sh
else
	(echo "WARN: Executing without baserefs.sh" 1>&2)
fi

function usage {
(echo -e "\
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
*                  If only an ID is given, multiple-runs cannot be processed.
*
* Optional:
*   -i [FILE]      Input file. Specify twice for pair end reads.
*                  If this option is not present files will be sought from
*                  \$(pwd)/blocks/ ($(pwd)/blocks/)
*   -m             Set this sample as one of many for individual.
*                  Halts after contig split
*                  Omit for final sample for individual.
*                  ${ylw}Do not perform multiple runs simultaneously as final run will${nrm}
*                  ${ylw}merge all partial samples for individual.${nrm}
*   -r [FILE]      Full path to reference file.
*                  Default: /resource/bundles/human_g1k_v37/human_g1k_v37_decoy
*   ${bred}-o [PATH]      WIP${nrm}
*                  Path to final output location.
*                  Defaults to /scratch/\$USER (/scratch/$USER)
*
*********************************" 1>&2)
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
			if [[ " ${FILE_LIST[@]} " =~ " ${OPTARG} " ]]
			then
				(echo "FAIL: Input file $OPTARG already added. Perhaps you want Read 2?" 1>&2)
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
	(echo "FAIL: Missing required parameter!" 1>&2)
	usage
	exit 1
fi

# Block depends on input or array id.
export BLOCK=$(printf "%0${FASTQ_MAXZPAD}d" $SLURM_ARRAY_TASK_ID)

export BWA_OUT=${TMPDIR}/align_${BLOCK}.bam
export PIC_OUT=${TMPDIR}/sorted_${BLOCK}.bam
 OUTPUT=${RUN_PATH}/split/${BLOCK}/contig_split

mkdir -p $(dirname ${BWA_OUT}) || exit $EXIT_IO;
mkdir -p $(dirname ${PIC_OUT}) || exit $EXIT_IO;
mkdir -p $(dirname ${OUTPUT}) || exit $EXIT_IO;

(echo "Output locations sed" 1>&2)

export HEADER="BA"

if [ "${#FILE_LIST[@]}" -eq 2 ]; then
	READ1=${FILE_LIST[0]}
	READ2=${FILE_LIST[1]}
elif [ "${#FILE_LIST[@]}" -eq 1 ]; then
	READ1=${FILE_LIST[0]}
else
	READ1=${RUN_PATH}/blocks/R1_${BLOCK}.fastq.gz
	[ -e ${RUN_PATH}/blocks/R2_${BLOCK}.fastq.gz ] && READ2=${RUN_PATH}/blocks/R2_${BLOCK}.fastq.gz
fi

# Trim spaces from funny fastqs: illumina platinum collection
READGROUP=$($CAT_CMD $READ1 | head -1 | sed -e 's/ /\./g' | awk -F'[@:]' '{print $2"_"$3"_"$4"_"$5"_"$11}' )

(echo "$HEADER: $READGROUP $BLOCK $READ1 $READ2 -> $OUTPUT" 1>&2)
jobStats


if [ $(echo "$READGROUP" | wc -w) -gt 1 ]; then
	(echo "$HEADER: Too many read-groups!" 1>&2)
	exit 1
fi

# Make sure input and target folders exists and that output file does not!
if ! (INPUT=${READ1}; inFile); then exit $EXIT_IO; fi
if ! (INPUT=${READ2}; inFile); then exit $EXIT_IO; fi
if ! outDirs; then exit $EXIT_IO; fi
#if ! outFile; then exit $EXIT_IO; fi

# Get readgroup blocks from either INFO_INFO_INFO_.. or INFO INFO INFO ...
	INSTRUMENT=$(echo ${READGROUP} | awk -F'_' '{print $1}')
INSTRUMENT_RUN=$(echo ${READGROUP} | awk -F'_' '{print $2}')
	 FLOW_CELL=$(echo ${READGROUP} | awk -F'_' '{print $3}')
	 CELL_LANE=$(echo ${READGROUP} | awk -F'_' '{print $4}')
		 INDEX=$(echo ${READGROUP} | awk -F'_' '{print $5}')

if  [ -z $INSTRUMENT ] || \
	[ -z $INSTRUMENT_RUN ] || \
	[ -z $FLOW_CELL ] || \
	[ -z $CELL_LANE ] || \
	[ -z $INDEX ]
then
	(echo "$HEADER: FAILURE: Unable to pull readgroup: $READGROUP" 1>&2)
	exit 1
fi

RG_ID="ID:${INSTRUMENT}_${INSTRUMENT_RUN}_${FLOW_CELL}_${CELL_LANE}_${INDEX}"
RG_PL="PL:Illumina"
RG_PU="PU:${FLOW_CELL}.${CELL_LANE}"
RG_LB="LB:${SAMPLE}"
RG_SM="SM:$(echo ${SAMPLE} | awk -F'[[:blank:]_]' '{print $1}')"

echo $REFA | grep 38 && BWA_REF=$REFA || BWA_REF=$REF

HEADER="PA"
JOBSTEP=0
(echo "$HEADER: Aligning! $BWA_REF" 1>&2)

module load BWA
module load SAMtools

# Pipe output from alignment into sortsam
CMD="srun -J ${SAMPLE}_Aligning_${BLOCK} $(which bwa) mem -M -t ${SLURM_JOB_CPUS_PER_NODE} -Y -R @RG'\t'$RG_ID'\t'$RG_PL'\t'$RG_PU'\t'$RG_LB'\t'$RG_SM $BWA_REF $READ1 $READ2 | $(which samtools) view -bh - > $BWA_OUT"
(echo "$HEADER: ${CMD}" | tee -a ../commands.txt 1>&2)

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

module load picard

CMD="srun -J ${SAMPLE}_Sorting_${BLOCK} $(which java) ${JAVA_ARGS} -jar $EBROOTPICARD/picard.jar SortSam ${PIC_ARGS} ${SORT_ARGS} INPUT=$BWA_OUT OUTPUT=$PIC_OUT"
(echo "$HEADER: ${CMD}" | tee -a ../commands.txt 1>&2)

scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${SAMPLE}_Sorting_${BLOCK}

if ! ${CMD}; then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi

storeMetrics

rm $BWA_OUT && (echo "$HEADER: Purged aligned block: $SHM_DIR/align_${BLOCK}.bam" 1>&2)

HEADER="CS"
JOBSTEP=2
(echo "$HEADER: Splitting by contig" 1>&2)

module load SAMtools

scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${SAMPLE}_SplitByContig_${BLOCK}

# Run multiple samview splits at once. capped at cpus assigned. Initially slow but should speed up with time.
if ! for contig in ${CONTIGARRAY[@]}; do echo $contig; done | (
	srun -J ${SAMPLE}_SplitByContig_${BLOCK} xargs -I{} --max-procs ${SLURM_JOB_CPUS_PER_NODE} bash -c '{
		OUTPUT="${RUN_PATH}/split/${BLOCK}/{}.bam"
		CMD="$(which samtools) view -bh -o ${OUTPUT} ${PIC_OUT} {}"
		(echo "$HEADER: ${CMD}" | tee -a ../commands.txt 1>&2)
		${CMD}
		(echo "result: $?" 1>&2)
	}'
); then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi

storeMetrics
JOBSTEP=""
SECONDS=$(($SECONDS + $SS_SECONDS + $PA_SECONDS))

#df -ah $SHM_DIR
rm $PIC_OUT && (echo "$HEADER: Purged sorted block: $SHM_DIR/sorted_${BLOCK}.bam" 1>&2)

# Remove input files.
if [ "${#FILE_LIST[@]}" -lt "1" ]; then
	rm ${READ1} ${READ2} && (echo "$HEADER: Purged source read block files!" 1>&2)
fi

# Indicate completion.
touch ${OUTPUT}.done
