#!/bin/bash
#SBATCH --job-name	Recalibration
#SBATCH --time		359
#SBATCH --mem		32G
#SBATCH --cpus-per-task	8
#SBATCH --array		1-84
#SBATCH --error		slurm/RC_%A_%a.out
#SBATCH --output	slurm/RC_%A_%a.out

(echo "$(date) on $(hostname)" 1>&2)
(echo $0 $* 1>&2)

if [ -e $EXEDIR/baserefs.sh ]
then
	source $EXEDIR/baserefs.sh
else
	(echo "WARN: Executing without baserefs.sh" 1>&2)
fi

function usage {
(echo -e "\
*************************************
* This script spool up an alignment *
* run for the specified patient ID  *
* on the DSMC cluster.              *
*************************************
*
* usage: $0 options:
*
*********************************
*
* Optional:
*   -h             Print help/usage information.
*   -i [FILE]      Input file.
*                  If no input specified will search in ${pwd}/markdup/${CONTIG}.bam
*   ${bred}-o [PATH]      WIP${nrm}
*                  Path to final output location.
*                  Defaults to /scratch/$USER
*   -r [FILE]      Full path to reference file.
*                  Default: \$REF_CORE ($REF_CORE)
*
*********************************" 1>&2)
}

while getopts "hi:o:r:" OPTION
do
	case $OPTION in
		h)
			usage
			exit 0
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
			export FILE_LIST=(${FILE_LIST[@]} ${OPTARG})
			(printf "%-22s%s\n" "Input file" $OPTARG 1>&2)
			;;
		o)
			export OUTPUT_DIR=${OPTARG}
			(printf "%-22s%s\n" "Final datastore" $OUTPUT_DIR 1>&2)
			;;
		r)
			export REF=${OPTARG}
			if [ ! -e $REF ]; then
				(echo "FAIL: $REF does not exist" 1>&2)
				exit 1
			fi
			export REFA=$REF.fasta
			(printf "%-22s%s\n" "Reference sequence" $REF 1>&2)
			;;
		?)
			(echo "FAILURE: ${OPTION} ${OPTARG} is not valid!" 1>&2)
			usage
			exit 1
			;;
	esac
done

CONTIG=${CONTIGARRAY[$SLURM_ARRAY_TASK_ID]}

# INPUT is either specified single file or contig dependent entry.
[ "${#FILE_LIST[@]}" -lt "1" ] && \
	INPUT=markdup/${CONTIG}.bam || \
	INPUT=${FILE_LIST[0]}

  BQSR=${TMPDIR}/${CONTIG}.firstpass
OUTPUT=${SAMPLE_PATH}/printreads/${CONTIG}.bam

mkdir -p $(dirname $BQSR)
mkdir -p $(dirname $OUTPUT)

HEADER="RC"

(echo "$HEADER: ${INPUT} -> ${BQSR} -> ${OUTPUT}" 1>&2)


# Make sure input and target folders exists and that output file does not!
if ! inFile;  then exit $EXIT_IO; fi
if ! outDirs; then exit $EXIT_IO; fi
if ! outFile; then exit $EXIT_IO; fi

INPUT_BAI=${INPUT%.*}.bai
if [ ! -e $INPUT_BAI ]; then
	(echo "WARN: $INPUT_BAI does not exist. Creating..." 1>&2)
	module load SAMtools
	scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${IDN}_Indexing_BAM_${CONTIG}_$SLURM_ARRAY_TASK_ID
	srun -j ${IDN}_Indexing_BAM_${CONTIG}_$SLURM_ARRAY_TASK_ID samtools index $INPUT $INPUT_BAI
fi


module load Java/1.8.0_144

if [ -z $GATK_JAR ]
then
	(echo "Loading GATK Module" 1>&2)
	module load GATK
	GATK_JAR=$EBROOTGATK/GenomeAnalysisTK.jar
fi

HEADER="BR"

CMD="srun -J =${IDN}_BaseRecal_${CONTIG}_$SLURM_ARRAY_TASK_ID $(which java) ${JAVA_ARGS} -jar $GATK_JAR ${GATK_BSQR} -L ${CONTIG} ${GATK_ARGS} -I ${INPUT} -o ${BQSR}"
(echo "$HEADER: ${CMD}" | tee -a commands.txt 1>&2)

JOBSTEP=0
 
scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${IDN}_BaseRecal_${CONTIG}_$SLURM_ARRAY_TASK_ID

if ! ${CMD}; then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi

BR_SECONDS=$SECONDS
SECONDS=0

HEADER="PR"

CMD="srun -J ${IDN}_Printing_${CONTIG} $(which java) ${JAVA_ARGS} -jar $GATK_JAR ${GATK_READ} -L ${CONTIG} ${GATK_ARGS} -I ${INPUT} -BQSR ${BQSR} -o ${OUTPUT}"
(echo "$HEADER: ${CMD}" | tee -a commands.txt 1>&2)

JOBSTEP=1

scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${IDN}_Printing_${CONTIG}

if ! ${CMD}; then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi

SECONDS=$(($SECONDS + $BR_SECONDS))
JOBSTEP=""

if [ "${#FILE_LIST[@]}" -lt "1" ]; then
	# We're here from a split job.
	rm ${INPUT} ${INPUT%.bam}.bai && echo "$HEADER: Purged input files!"
fi

touch ${OUTPUT}.done
