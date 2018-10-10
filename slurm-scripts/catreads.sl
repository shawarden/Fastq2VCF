#!/bin/bash
#SBATCH --job-name	CatReads
#SBATCH --time		60
#SBATCH --mem		4G
#SBATCH --cpus-per-task	1
#SBATCH --error		slurm/CR_%j.out
#SBATCH --output	slurm/CR_%j.out

echo "$(date) on $(hostname)"

if [ -e $EXEDIR/baserefs.sh ]
then
	source $EXEDIR/baserefs.sh
else
	(echo "WARN: Executing without baserefs.sh" 1>&2)
fi

function usage {
echo -e "\
****************************************
* This script will concatonate multple *
* BAM files into a single BAM using    *
* header from the first BAM file       *
****************************************
*
* usage: $0 options:
*
*********************************
*
* Required:
*   -i [FILE]      Input file. Can be specified multiple times.
*   -o [FILE]      Output file.
* Optional:
*   -r [FILE]      Full path to reference file.
*                  Default: \$REF_CORE ($REF_CORE)
*
*********************************"
}

while getopts "i:r:o:" OPTION
do
	FILE=
	case $OPTION in
		i)
			if [ ! -e ${OPTARG} ]; then
				echo "FAIL: Input file $OPTARG does not exist!"
				exit 1
			fi
			if [[ " ${FILE_LIST[@]} " =~ " ${OPTARG} " ]]
			then
				(echo "FAIL: Input file $OPTARG already added. Perhaps you want Read 2?" 1>&2)
				exit 1
			fi
			export FILE_LIST=(${FILE_LIST[@]} ${OPTARG})
			(echo "input files \"$OPTARG\"" 1>&2)
			;;
		r)
			export REF=${OPTARG}
			if [ ! -e $REF ]; then
				echo "FAIL: $REF does not exist"
				exit 1
			fi
			export REFA=$REF.fasta
			( echo "reference $REF" 1>&2)
			;;
		o)
			export OUTPUT=${OPTARG}
			(echo "output $OUTPUT_DIR" 1>&2)
			;;
		?)
			echo "FAILURE: $0 ${OPTION} ${OPTARG} is not valid!"
			usage
			exit 1
			;;
	esac
done

if [ "${#FILE_LIST[@]}" -lt "1" ] || [ "${OUTPUT}" == "" ]; then
	echo "FAIL: Missing required parameter!"
	usage
	exit 1
fi

IDN=$(echo $SLURM_JOB_NAME | cut -d'_' -f2)

BAMHEAD=${FILE_LIST[0]}

HEADER="CR"

# Get local node freespace for /tmp and /scratch
DF_OUT=$(df)
DF_TMP=$(echo "$DF_OUT" | grep " /tmp" | awk '{printf "%.0f", $4/1024/1024}')
DF_SCRATCH=$(echo "$DF_OUT" | grep " /scratch" | awk '{printf "%.0f", $4/1024/1024}')

# If node's temp folder has enough space, write output locally, otherwise leave at main destination.
if [ "$DF_TMP" -gt "250" ]; then
	echo "$HEADER: Writing to local node /tmp folder. $DF_TMP"
	OUTDIR=$JOB_TEMP_DIR
elif [ "$DF_SCRATCH" -gt "250" ]; then
	echo "$HEADER: Not enough space on local node. Writing to scratch. $DF_SCRATCH"
	OUTDIR=$SCRATCH_DIR
else
	echo "$HEADER: No enough space on local node or scratch disk for write. Writing to final destination."
	df -h
fi

echo "$HEADER: ${FILE_LIST[@]} + Header($BAMHEAD) ->" $OUTPUT

for INPUT in ${FILE_LIST[@]}; do
	if ! inFile; then exit $EXIT_IO; fi
done

if ! outDirs; then exit $EXIT_IO; fi
if ! outFile; then exit $EXIT_IO; fi

module load SAMtools

CMD="srun $(which samtools) cat -h ${BAMHEAD} -o ${OUTDIR}/${OUTPUT} ${FILE_LIST[@]}"
echo "$HEADER: ${CMD}" | tee -a commands.txt

JOBSTEP=0

scontrol update jobid=${SLURM_JOB_ID} name=${IDN}_ConcatReads

if ! ${CMD}; then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi

# Move output to final location
if [ "$OUTDIR" == "$JOB_TEMP_DIR" ]; then
	if ! finalOut; then exit $EXIT_MV; fi
elif [ "$OUTDIR" == "$SCRATCH_DIR" ]; then
	if ! scratchOut; then exit $EXIT_MV; fi
fi

touch ${OUTPUT}.done
