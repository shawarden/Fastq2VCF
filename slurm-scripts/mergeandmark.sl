#!/bin/bash
#SBATCH --job-name		MergeAndMark
#SBATCH --time			359
#SBATCH --mem			32G
#SBATCH --cpus-per-task	8
#SBATCH --array			1-84
#SBATCH --error			slurm/MM_%A_%a.out
#SBATCH --output		slurm/MM_%A_%a.out

echo "$(date) on $(hostname)"

if [ -e $EXEDIR/baserefs.sh ]
then
	source $EXEDIR/baserefs.sh
else
	(echo "WARN: Eecuting without baserefs.sh" 1>&2)
fi


function usage {
cat << EOF

*************************************
* This script will merge BAM files  *
* and mark duplicate entries        *
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
*                  $(pwd)/split/...
*   -o             WIP
*                  Path to final output location.
*                  Defaults to /scratch/$USER
*
*********************************
EOF
}

while getopts "s:i:r:o:" OPTION
do
	FILE=
	case $OPTION in
		s)
			SAMPLE=${OPTARG}
			(printf "%-22s%s\n" "Sample ID" $SAMPLE 1>&2)
			;;
		i)
			if [ ! -e ${OPTARG} ]; then
				(echo "FAIL: Input file $OPTARG does not exist!" 1>&2)
				exit 1
			fi
			FILE_LIST=(${FILE_LIST[@]} ${OPTARG})
			(printf "%-22s%s\n" "Input file" $OPTARG 1>&2)
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

CONTIG=${CONTIGBLOCKS[$SLURM_ARRAY_TASK_ID]}
MERGED=$SHM_DIR/merged.bam
OUTPUT=markdup/${CONTIG}.bam

HEADER="MM"

echo "$HEADER: ${CONTIG} -> merged -> ${OUTPUT}"


# Blocks do not need to be sequential do they?
#contigMerBlocks=$(find . -type f -iwholename "*/split/*/${CONTIG}.bam") -printf '%h\0%d\0%p\n' | sort -t '\0' -n | awk -F '\0' '{print $3}')
# Get list of blocks of the base contig and all alternates.
contigMerBlocks=$(find . -type f -iwholename "*/split/*/${CONTIG}.bam"; find . -type f -iwholename "*/split/*/${CONTIG}_*.bam"; find . -type f -iwholename "*/split/*/${CONTIG}\**.bam" | tr '\n' ' ')

numcontigMerBlocks=$(echo "$contigMerBlocks" | wc -l)

echo "$contigMerBlocks"

if [ $numcontigMerBlocks -eq 0 ]; then
	echo "$HEADER: Merge contig ${CONTIG} contains $numcontigMerBlocks files!"
#	scriptFailed
	exit $EXIT_IO
else
	echo $HEADER: Merge contig ${CONTIG} will run $numcontigMerBlocks files: \"${contigMerBlocks}\"
fi

mergeList=""
for INPUT in ${contigMerBlocks}; do
	if inFile; then
		mergeList="${mergeList} INPUT=${INPUT}"
	else
		exit $EXIT_IO
	fi
done

if [ "$mergeList" == "" ]; then
	echo "$HEADER: No inputs defined!"
	exit $EXIT_IO
fi

# Make sure input and target folders exists and that output file does not!
if ! outDirs; then exit $EXIT_IO; fi
if ! outFile; then exit $EXIT_IO; fi

module purge
module load picard

#HEADER="MC"
#CMD="srun $(which java) ${JAVA_ARGS} -jar $EBROOTPICARD/picard.jar MergeSamFiles ${PIC_ARGS} ${MERGE_ARGS} ${mergeList} OUTPUT=${MERGED}"
#echo "$HEADER: ${CMD}" | tee -a commands.txt

JOBSTEP=0

#if ! ${CMD}; then
#	cmdFailed $?
#	exit ${JOBSTEP}${EXIT_PR}
#fi

#MC_SECONDS=$SECONDS
SECONDS=0
HEADER="MD"
CMD="srun $(which java) ${JAVA_ARGS} -jar $EBROOTPICARD/picard.jar MarkDuplicates ${PIC_ARGS} ${MARK_ARGS} ${mergeList} OUTPUT=${OUTPUT}" 
#CMD="srun $(which java) ${JAVA_ARGS} -jar $EBROOTPICARD/picard.jar MarkDuplicates ${PIC_ARGS} ${MARK_ARGS} INPUT=${MERGED} OUTPUT=${OUTPUT}" 
echo "$HEADER: ${CMD}" | tee -a commands.txt

#JOBSTEP=1

scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${IDN}_MergeMarkDup_${CONTIG}_$SLURM_ARRAY_TASK_ID
if ! ${CMD}; then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi

#SECONDS=$(($SECONDS + $MC_SECONDS))

JOBSTEP=""

# rm $contigMerBlocks && echo "$HEADER: Purging $numcontigMerBlocks contig merge blocks!"

touch ${OUTPUT}.done
