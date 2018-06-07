#!/bin/bash
#SBATCH --job-name		ReadIndex
#SBATCH --time			0-01:30:00
#SBATCH --mem			4G
#SBATCH --cpus-per-task	1
#SBATCH --error			slurm/RI_%j.out
#SBATCH --output		slurm/RI_%j.out

echo "$(date) on $(hostname)"

if [ -e $EXEDIR/baserefs.sh ]
then
	source $EXEDIR/baserefs.sh
else
	(echo "WARN: Eecuting without baserefs.sh" 1>&2)
fi


INPUT=${1}
OUTPUT=$([ "${2}" == "" ] && echo -ne "${INPUT%.bam}.bai" || echo -ne "${2}")
IDN=$(echo $SLURM_JOB_NAME | cut -d'_' -f2)

HEADER="RI"

echo "$HEADER: ${INPUT} -> ${OUTPUT}"

# Make sure input and target folders exists and that output file does not!
if ! inFile;  then exit $EXIT_IO; fi
if ! outDirs; then exit $EXIT_IO; fi
if ! outFile; then exit $EXIT_IO; fi

module purge
module load SAMtools

CMD="srun $(which samtools) index ${INPUT} ${JOB_TEMP_DIR}/${OUTPUT}"
echo "$HEADER: ${CMD}" | tee -a commands.txt

JOBSTEP=0

scontrol update jobid=${SLURM_JOB_ID} name=${IDN}_Indexing_Reads

if ! ${CMD}; then
	cmdFailed $?
	exit ${JOBSTEP}${EXIT_PR}
fi

# Move output to final location
if ! finalOut; then exit $EXIT_MV; fi

touch ${OUTPUT}.done

#if ! . ${SLSBIN}/transfer.sl ${IDN} ${OUTPUT}; then
#	echo "$HEADER: Transfer index failed!"
#	exit $EXIT_TF
#fi
