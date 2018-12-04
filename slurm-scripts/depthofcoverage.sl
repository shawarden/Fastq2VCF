#!/bin/bash
#SBATCH --job-name	DepthOfCoverage
#SBATCH --time		0-00:30:00
#SBATCH --mem		8G
#SBATCH --cpus-per-task	4
#SBATCH --array		1-84
#SBATCH --error		slurm/DC_%A_%a.out
#SBATCH --output	slurm/DC_%A_%a.out

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
* Required:
*   -p [PLATFORM]  Capture platform/Exome chip.
*                  List of .bed files is at \$PLATFORMS ($PLATFORMS)
*   -s [IDLR]      Sample ID string: ID_DNAID_LIBRARY_RUN.
*                  This is used to determine individuals with multiple segments.
*                  If only an ID is given, multiple-runs cannot be processed.
*
* Optional:
*   -h             Print help/usage information.
*   -i [FILE]      Input file. Can be specified multiple times.
*                  Required for initial run or Entrypoint injection.
*   -r [FILE]      Full path to reference file.
*                  Default: \$REF_CORE ($REF_CORE)
*
*********************************" 1>&2)
}

while getopts "p:s:b:c:e:f:g:i:hmo:r:" OPTION
do
	case $OPTION in
		s)
			export SAMPLE=${OPTARG}
			(printf "%-22s%s\n" "Sample ID" $SAMPLE 1>&2)
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
				(echo "FAIL: Input file \"$OPTARG\" does not exist!" 1>&2)
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

if [ "${SAMPLE}" == "" ] || [ "${PLATFORM}" == "" ]; then
	(echo "FAIL: Missing required parameter!" 1>&2)
	usage
	exit 1
fi

CONTIG=${CONTIGBLOCKS[$SLURM_ARRAY_TASK_ID]}

inputList=""

if [ "${#FILE_LIST[@]}" -lt "1" ]; then
	INPUT=printreads/${CONTIG}.bam
	if ! inFile;  then exit $EXIT_IO; fi
	inputList="-I $INPUT"
else
	for INPUT in ${FILE_LIST[@]}; do
		if ! inFile; then exit $EXIT_IO; fi
		inputList="$inputList -I $INPUT"
	done
fi

OUTPUT=${SAMPLE_PATH}/depth/${CONTIG}

HEADER="DC"
(echo "$HEADER: ${inputList} + ${PLATFORM} -> ${OUTPUT}" 1>&2)

# Make sure input and target folders exists and that output file does not!
if ! outFile; then exit $EXIT_IO; fi

platformBED=${PLATFORMS}/${PLATFORM}.bed
  genderBED=${PLATFORMS}/$([ "$PLATFORM" == "Genomic" ] && echo -ne "AV5" || echo -ne "$PLATFORM" ).bed
  
# Special cases for X and Y depth of covereage as the X/YPAR1 and X/YPAR2 regions are distorted.
# Genomic Y is rife with repeat sequences that inflate coverage so use AV5 region for that.
# X: █▄▄▄▄▄▄▄█
# Y: _▄▄▄▄▄▄▄_
if [ "${CONTIG}" == "X" ]; then
	platformFile=${genderBED}
	actualContig=${TRUEX}
elif [ "${CONTIG}" == "Y" ]; then
	platformFile=${genderBED}
	actualContig=${TRUEY}
else
	platformFile=${platformBED}
	actualContig=${CONTIG}
fi

GATK_PROC=DepthOfCoverage
GATK_ARGS="-T ${GATK_PROC} \
-R ${REFA} \
-L ${platformFile} \
-L ${actualContig} \
-isr INTERSECTION \
--omitLocusTable \
--omitDepthOutputAtEachBase \
--omitIntervalStatistics \
-nt ${SLURM_JOB_CPUS_PER_NODE}"

module load Java/1.8.0_144


if [ -z $GATK_JAR ]
then
	(echo "Loading GATK Module" 1>&2)
	module load GATK
	GATK_JAR=$EBROOTGATK/GenomeAnalysisTK.jar

fi

CMD="srun -J ${IDN}_Depth_${CONTIG}_$SLURM_ARRAY_TASK_ID $(which java) ${JAVA_ARGS} -jar $GATK_JAR ${GATK_ARGS} ${inputList} -o ${OUTPUT}"
(echo "$HEADER: ${CMD}" | tee -a commands.txt 1>&2)

JOBSTEP=0

scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} name=${IDN}_Depth_${CONTIG}_$SLURM_ARRAY_TASK_ID

if ! ${CMD}; then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi


touch ${OUTPUT}.done
