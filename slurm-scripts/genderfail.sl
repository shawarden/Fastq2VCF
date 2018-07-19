#!/bin/bash
#SBATCH --job-name	GenderFail
#SBATCH --time		0-00:01:00
#SBATCH --mem		128
#SBATCH --cpus-per-task	1
#SBATCH --error		slurm/GF_%j.out
#SBATCH --output	slurm/GF_%j.out
#SBATCH --mail-type	FAIL

echo "$(date) on $(hostname)"
echo "Something about the gender failed: $SLURM_JOB_NAME"
exit 1