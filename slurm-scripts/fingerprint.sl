#!/bin/bash
#SBATCH --job-name	FingerPrintCaller
#SBATCH --time		0-06:00:00
#SBATCH --mem		32G
#SBATCH --cpus-per-task	8
#SBATCH --error		slurm/FPH_%j.out
#SBATCH --output	slurm/FPH_%j.out

echo "$(date) on $(hostname)"

if [ -e $EXEDIR/baserefs.sh ]
then
	source $EXEDIR/baserefs.sh
else
	(echo "WARN: Executing without baserefs.sh" 1>&2)
fi


IDN=${1}
INPUT=${2}
OUTPUT=${INPUT%.bam}.vcf.gz

HEADER="FHC"

echo "$HEADER: ${INPUT} -> ${OUTPUT}"


# Make sure input and target folders exists and that output file does not!
if ! inFile;  then exit $EXIT_IO; fi
if ! outDirs; then exit $EXIT_IO; fi
if ! outFile; then exit $EXIT_IO; fi

GATK_PROC=HaplotypeCaller
GATK_ARGS="-T ${GATK_PROC} \
-R ${REFA} \
-L ${COMMON} \
-nct ${SLURM_JOB_CPUS_PER_NODE}"

module load ${MOD_JAVA}

CMD="srun $(which java) ${JAVA_ARGS} -jar $GATK ${GATK_ARGS} -I ${INPUT} -o ${JOB_TEMP_DIR}/${OUTPUT}"
echo "$HEADER: ${CMD}" | tee -a commands.txt

JOBSTEP=0

if ! ${CMD}; then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi


# Move output to final location
if ! finalOut; then exit $EXIT_MV; fi

touch ${OUTPUT}.done

sbatch -J FPS_${IDN} ${SLSBIN}/selectvariants.sl ${OUTPUT} ${3}
