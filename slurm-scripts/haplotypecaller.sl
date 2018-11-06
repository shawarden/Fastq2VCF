#!/bin/bash -e
#SBATCH --job-name	HaplotypeCaller
#SBATCH --time		0-03:00:00
#SBATCH --mem		32G
#SBATCH --cpus-per-task	8
#SBATCH --array		1-84
#SBATCH --error		slurm/HC_%A_%a.out
#SBATCH --output	slurm/HC_%A_%a.out

echo "$(date) on $(hostname)"
echo "$0 $*"

if [ -e $EXEDIR/baserefs.sh ]
then
	source $EXEDIR/baserefs.sh
else
	(echo "WARN: Executing without baserefs.sh" 1>&2)
fi


function usage {
echo -e "\
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
* Required:
*   -s [IDLR]      Sample ID string: ID_DNAID_LIBRARY_RUN.
*                  This is used to determine individuals with multiple segments.
*                  If only an ID is given, multiple-runs cannot be processed.
*
* Optional:
*   -c [contig]    Run under specified contig.
*   -i [FILE]      Input file. Can be specified multiple times.
*                  Required for initial run or Entrypoint injection.
*   -p [PLATFORM]  Capture platform/Exome chip.
*                  List of .bed files is at \$PLATFORMS: ${PLATFORMS}
*   -h             Print help/usage information.
*   -r [FILE]      Full path to reference file.
*                  Default: \$REF_CORE ($REF_CORE)
*
*********************************"
}

ENTRY_POINT=RS

while getopts "p:s:c:e:f:g:i:hmo:r:" OPTION
do
	case $OPTION in
		s)
			export SAMPLE=${OPTARG}
			(printf "%-22s%s\n" "Sample ID" $SAMPLE 1>&2)
			;;
		c)
			export CONTIG=${OPTARG}
			(printf "%-22s%s (%s)\n" "Contig" $CONTIG>&2)
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
		p)
			if [ ! -e $PLATFORMS/$OPTARG.bed ]; then
				(echo "FAIL: Unable to located $PLATFORMS/$OPTARG.bed!" 1>&2)
				exit 1
			fi
			export PLATFORM=${OPTARG}
			(printf "%-22s%s (%s)\n" "Platform" $PLATFORM $(find $PLATFORMS/ -type f -iname "$PLATFORM.bed") 1>&2)
			;;
		?)
			(echo "FAILURE: ${OPTION} ${OPTARG} is not valid!" 1>&2)
			usage
			exit 1
			;;
	esac
done

if [ "$CONTIG" == "" ]; then
	CONTIG=${CONTIGBLOCKS[$SLURM_ARRAY_TASK_ID]}
fi

HEADER="HC"

inputList=""

# Did we send input files?
if [ "${#FILE_LIST[@]}" -lt "1" ]; then
	# No input files sent. Find the printreads/* file set.
	INPUT=printreads/${CONTIG%:*}.bam	# Strip any contig coordinates.
	if ! inFile; then exit $EXIT_IO; fi
	inputList="-I $INPUT"
else
	# Input files sent. Check list exists and create input var.
	for INPUT in ${FILE_LIST[@]}; do
		if ! inFile; then exit $EXIT_IO; fi
		inputList="$inputList -I $INPUT"
	done
fi

OUTPUT=haplo/${CONTIG}.${FINAL_TYPE}.gz

if [ -e coverage.sh ]; then
	# Gender file exists so obtain values from it.
	source coverage.sh
fi

# Calculate ploidy based on number of X and Y chromosomes.
if [ "$CONTIG" == "${XPAR1}" ] || [ "$CONTIG" == "${XPAR2}" ]; then
	# XPAR1 and XPAR2 ploidies are the number of X and Y chromosomes combines. 1+1=2, 2+0=2, etc.
	intervalPloidy=$(($X_CHROMOSOMES + $Y_CHROMOSOMES))
elif [ "$CONTIG" == "${TRUEX}" ]; then
	# TRUEX ploidy is the number of X chromosomes. 1, 2, etc. 0 should never happen as the gender determination job should fail on that.
	intervalPloidy=$X_CHROMOSOMES
elif [ "$CONTIG" == "Y" ] || [ "$CONTIG" == "${TRUEY}" ]; then
	# Y or TRUEY ploidy is the number of Y chromosomes or 1, whichever is higher. so 0=1, 1=1, 2=2, etc.
	[ $Y_CHROMOSOMES -gt 1 ] && intervalPloidy=$Y_CHROMOSOMES || intervalPloidy=1
else
	# Non Gender chromosome ploidy is 2.
	intervalPloidy=2
fi

echo "$HEADER: ${INPUT} + ${CONTIG}c + ${intervalPloidy}p -> ${OUTPUT}"


# Make sure input and target folders exists and that output file does not!
if ! outDirs; then exit $EXIT_IO; fi
if ! outFile; then exit $EXIT_IO; fi

INPUT_BAI=${INPUT%.*}.bai
if [ ! -e $INPUT_BAI ]; then
	echo "WARN: $INPUT_BAI does not exist. Indexing..."
	module load SAMtools
	scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${IDN}_Indexing_BAM_${CONTIG}_$SLURM_ARRAY_TASK_ID
	if ! samtools index $INPUT $INPUT_BAI; then
		echo "FAIL: Unable to index $INPUT"
		exit $EXIT_PR
	fi
fi

GATK_PROC=HaplotypeCaller
GATK_ARGS="-T ${GATK_PROC} \
-R ${REFA} \
-L ${CONTIG} \
--sample_ploidy ${intervalPloidy} \
--dbsnp ${DBSNP} \
-nct ${SLURM_JOB_CPUS_PER_NODE}"

[ "$FINAL_TYPE" == "g.vcf" ] && GATK_ARGS="$GATK_ARGS --emitRefConfidence GVCF"
[ "$FINAL_TYPE" == "vcf" ] && GATK_ARGS="$GATK_ARGS -variant_index_type LINEAR -variant_index_parameter 128000"

if [ -z $GATK_JAR ]
then
	echo "Loading GATK Module"
	module load GATK
	GATK_JAR=$EBROOTGATK/GenomeAnalysisTK.jar

fi

CMD="srun $(which java) ${JAVA_ARGS} -jar $GATK_JAR ${GATK_ARGS} ${inputList} -o ${JOB_TEMP_DIR}/${OUTPUT}"
echo "$HEADER ${CMD}" | tee -a commands.txt

JOBSTEP=0

scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${IDN}_Haplotyping_${CONTIG}_$SLURM_ARRAY_TASK_ID
if ! ${CMD}; then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi


# Move output to final location
if ! finalOut; then exit $EXIT_MV; fi

touch ${OUTPUT}.done
