#!/bin/bash

source /mnt/hcs/WCHP_Clinical_Genetics/Resources/bin/DSMC_2FastqToCall/baserefs.sh

   SAMPLE=${1}
READGROUP=${2}
  READNUM=${3}
    BLOCK=${4}
     NEXT=${5}
 ALIGNARR=${6}
 MERGEARR=${7}
  
ZPADBLOCK=$(printf "%0${FASTQ_MAXZPAD}d" $BLOCK)
#ZPADNEXT=$(printf "%0${FASTQ_MAXZPAD}d" $NEXT)

curRead1File=blocks/${READGROUP}_R1_${ZPADBLOCK}.fastq.gz
curRead2File=blocks/${READGROUP}_R2_${ZPADBLOCK}.fastq.gz

IDN=$(echo ${SAMPLE} | awk -F'[[:blank:]_]' '{print $1}')
DNA=$(echo ${SAMPLE} | awk -F'[[:blank:]_]' '{print $2}')
LIB=$(echo ${SAMPLE} | awk -F'[[:blank:]_]' '{print $3}')
RUN=$(echo ${SAMPLE} | awk -F'[[:blank:]_]' '{print $4}')
PLATFORM=Genomic

function spoolAlign {
	alignBlockOutput=split/contig_split_${ZPADBLOCK}.done
	
	mkdir -p $(dirname ${alignBlockOutput})
	
	printf "%-16s" "Alignment"
	
	if [ ! -e ${alignBlockOutput} ]; then
		scontrol update JobId=${ALIGNARR}_${BLOCK} StartTime=now Dependency=
		if [ $? -ne 0 ]; then
			printf "FAILED!\n"
			exit 1
		else
			printf "%s\n" ${ALIGNARR}_${BLOCK}
		fi
	else
		printf "done\n"
	fi
	
	if [ "$BLOCK" == "$NEXT" ]; then	# This is the final chunk so we can spool up the next step
		echo "CB: $BLOCK of $NEXT block$([ $NEXT -gt 1 ] && echo -ne "s") completed!"
		purgeList="$((${NEXT}+1))-$FASTQ_MAXJOBZ"
		# Purge extra align and sort array elements.
		scancel ${ALIGNARR}_[${purgeList}] && echo "CB: Purged ${ALIGNARR}_[${purgeList}]!"
	fi
}

if [ "$READNUM" == "R1" ]; then	# BLOCK Read1 has completed!
	if [ -e ${curRead2File}.done ]; then	# NEXT Read2 exists so BLOCK Read2 has completed!
		echo "CB: Both R1 and R2 ${BLOCK} completed!" #| tee -a check_${BLOCK}.txt
		spoolAlign
#	else	# NEXT Read2 doesn't exist yet so BLOCK Read2 hasn't completed!
#		echo "CB: R1 ${BLOCK} completed but R2 not done yet!" #| tee -a check_${BLOCK}.txt
	fi
elif [ "$READNUM" == "R2" ]; then	# BLOCK Read2 has completed!
	if [ -e ${curRead1File}.done ]; then		# NEXT Read1 exists so BLOCK Read1 has completed!
		echo "CB: Both R1 and R2 ${BLOCK} completed!" #| tee -a check_${BLOCK}.txt
		spoolAlign
#	else	# NEXT Read1 doesn't exist yet so BLOCK Read1 hasn't completed!
#		echo "CB: R2 ${BLOCK} complete but R1 not done yet!" #| tee -a check_${BLOCK}.txt
	fi
fi
