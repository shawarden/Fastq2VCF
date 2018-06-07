#!/bin/bash
#SBATCH --job-name		CatVariants
#SBATCH --time			359
#SBATCH --mem			16G
#SBATCH --cpus-per-task	1
#SBATCH --error			slurm/CV_%j.out
#SBATCH --output		slurm/CV_%j.out

echo "$(date) on $(hostname)"

if [ -e $EXEDIR/baserefs.sh ]
then
	source $EXEDIR/baserefs.sh
else
	(echo "WARN: Eecuting without baserefs.sh" 1>&2)
fi


function usage {
cat << EOF

****************************************
* This script will concatonate multple *
* VCF files into a single VCF file     *
****************************************
*
* usage: $0 options:
*
*********************************
*
* Required:
*   -i [file]      Input file. Can be specified multiple times.
*   -o [file]      Output file.
* Optional:
*   -r             Full path to reference file.
*                  Default: /resource/bundles/human_g1k_v37/human_g1k_v37_decoy
*
*********************************
EOF
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

HEADER="CV"

echo $HEADER $FILES "->" $OUTPUT

mergeList=""
for INPUT in ${FILE_LIST[@]}; do
	if ! inFile; then
		exit $EXIT_IO
	else 
		mergeList="${mergeList} -V ${INPUT}"
	fi
done

# Make sure input and target folders exists and that output file does not!
if ! outDirs; then exit $EXIT_IO; fi
if ! outFile; then exit $EXIT_IO; fi

GATK_PROC=org.broadinstitute.gatk.tools.CatVariants
GATK_ARGS="${GATK_PROC} \
-R ${REFA} \
--assumeSorted"

module purge
module load GATK

CMD="srun $(which java) ${JAVA_ARGS} -cp $EBROOTGATK/GenomeAnalysisTK.jar ${GATK_ARGS} ${mergeList} -out ${SCRATCH_DIR}/${OUTPUT}"
echo "$HEADER ${CMD}" | tee -a commands.txt

JOBSTEP=0

scontrol update jobid=${SLURM_JOB_ID} name=${IDN}_ConcatVariants

if ! ${CMD}; then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi


# Move output to final location
if ! scratchOut; then exit $EXIT_MV; fi

#rm $FILES && echo "$HEADER: Purged input files!"

touch ${OUTPUT}.done

CV_OUTPUT=${OUTPUT}

# Start transfers for variants file and index.
#if ! . ${SLSBIN}/transfer.sl ${IDN} ${CV_OUTPUT}; then
#	echo "$HEADER: Transfer failed!"
#	exit $EXIT_TF
#fi

#if ! . ${SLSBIN}/transfer.sl ${IDN} ${CV_OUTPUT}.tbi; then
#	echo "$HEADER: Transfer index failed!"
#	exit $EXIT_TF
#fi
