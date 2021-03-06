#!/bin/bash

#############################################################
# Generates job sequence for a given individual/sample list #
#############################################################

# Get base values
export EXEDIR=$(dirname $0)

source $EXEDIR/baserefs.sh

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
*   -h             Print full help/usage information.
*
* Required:
*   -i [FILE]      Input file. Can be specified multiple times.
*                  Required for initial run or Entrypoint injection.
*   -s [IDLR]      Sample ID string: ID_DNAID_LIBRARY_RUN.
*                  This is used to determine individuals with multiple segments.
*                  If only an ID is given, multiple-runs cannot be processed.
*   -p [PLATFORM]  Capture platform/Exome chip.
*                  Platforms in \$PLATFORMS: ${PLATFORMS}/
$(for file in ${PLATFORMS}/*.bed; do platFile=$(basename $file); platName=${platFile%.bed}; [ -e "${file%.*}.sh" ] && echo "*                  $platName"; done)
*
* Optional:
*   -b [NUM]       Number of split block so create.
*                  Default: \$FASTQ_SPLITNM ($FASTQ_SPLITNM)
*   -c [STRING]    Force HaplotypeCaller on X & Y with specified ploidy.
*                  Entered as XY combination: XX, XY, XXY, XYY, XXYY, etc.
*                  Default: Automatic
*   -e [STEP]      Entry point for script. Inputs must conform to entry point.
*                  RS: Split Reads (default) (Input: 2x .fastq[.gz])
*                  BA: Alignment, Sort & Split to Contigs (Input: 2x .fastq[.gz])
*                  MM: Merge Contig & Markduplicates (Input: 1x .bam)
*                  RC: BQSR & Printreads (Input: 1x .bam)
*                  DC: Depth of coverage (Input: 1x .bam)
*                  HC: Haplotype calling (Input: 1x .bam) Runs from DC.
*                  GD: Gender Determination (Input: 1x .bam) Runs from DC.
*                  CV: Concatonate Variants (Why tho?)
*                  Default: RS
*   -f [email]     Email address to alert on job failures to address other than
*                  address listed in /etc/slurm/userlist.
*                  ${ylw}Required if address list is unavailable.${nrm}
*   ${ylw}-g [Gender]    WIP${nrm}
*                  Gender Alert: Male/Female/Unknown
*                  Specifying a gender will trigger a warning if automatch fails.
*                  Job will continue with automatically detected Gender.
*                  Use -c to enforce specified chromosomal gender.  
*                  Default: Automatic
*   -m             Set this sample as one of many for individual.
*                  Halts after contig split
*                  Omit for final sample for individual.
*                  You can submit multiple segments simultaneously but...
*                  ${ylw}Do not perform final run simultaneously as it will${nrm}
*                  ${ylw}merge all partial samples for individual.${nrm}
*   ${bred}-o [PATH]      WIP (not working)${nrm}
*                  Path to final output location.
*                  Default: $WORK_PATH
*   -r [FILE]      Full path to reference file.
*                  Default: \$REF_CORE ($REF_CORE)
*   -t [EXT]       Final output type: g.vcf, vcf. Will always end in .gz
*                  Default: g.vcf
*
*********************************" 1>&2)
}

while getopts "b:c:e:f:g:hi:mo:p:r:s:t:" OPTION
do
	case $OPTION in
		b)
			export FASTQ_SPLITNM="${OPTARG}"
			(printf "%-22s%s\n" "Split Blocks" $FASTQ_SPLITNM 1>&2)
			;;
		c)
			export SEXCHR=${OPTARG}
			(printf "%-22s%s (%s)\n" "Sex Chromosomes" $SEXCHR "Warns on Autodetermination mismatch!"1>&2)
			;;
		e)
			if [ "${SB[$OPTARG]}" == "" ]; then
				(echo "FAIL: Invalid Entry-point" 1>&2)
				# Print out entry-point usage section.
				usage | head -n 42 | tail -n 11
				exit 1
			fi
			
			export ENTRY_POINT=${OPTARG}
			(printf "%-22s%s (%s)\n" "Entry point" $ENTRY_POINT ${SB[$ENTRY_POINT]} 1>&2)
			;;
		f)
			export MAIL_USER=${OPTARG}
			(printf "%-22s%s (%s)\n" "Email target" $MAIL_USER $MAIL_TYPE 1>&2)
			;;
		g)
			case ${OPTARG,,} in
				m*)
					export GENDER=Male
					;;
				f*)
					export GENDER=Female
					;;
				?)
					export GENDER=Unknown
					;;
			esac
			(printf "%-22s%s (%s)\n" "Gender" $GENDER "Warns on Autodetermination mismatch!" 1>&2)
			;;
		h)
			usage
			exit 0
			;;
		i)
			if [ ! -e ${OPTARG} ]; then
				(echo "FAIL: Input file $OPTARG does not exist!" 1>&2)
				# Print out input usage section.
				usage | head -n 15 | tail -n 2
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
		m)
			export MULTI_RUN="-m"
			(printf "%-22s%s (%s)\n" "Multiple runs" "Enabled" "Omit on final submission" 1>&2)
			;;
		o)
			export OUTPUT_DIR=${OPTARG}
			(printf "%-22s%s\n" "Final datastore" $OUTPUT_DIR 1>&2)
			;;
		p)
			if [ ! -e $PLATFORMS/$OPTARG.bed ]; then
				(echo "FAIL: Unable to located $PLATFORMS/$OPTARG.bed!" 1>&2)
				# Print out platform usage section.
				usage | head -n 31 | tail -n 13
				exit 1
			fi
			export PLATFORM=${OPTARG}
			(printf "%-22s%s (%s)\n" "Platform" $PLATFORM $(find $PLATFORMS/ -type f -iname "$PLATFORM.bed") 1>&2)
			;;
		r)
			export REF=${OPTARG}
			if [ ! -e $REF ]; then
				(echo "FAIL: $REF does not exist" 1>&2)
				# Print out Reference usage section 
				usage | head -n 55 | tail -n 2
				exit 1
			fi
			export REFA=$REF.fasta
			(printf "%-22s%s\n" "Reference sequence" $REF 1>&2)
			;;
		s)
			export SAMPLE=${OPTARG}
			(printf "%-22s%s\n" "Sample ID" $SAMPLE 1>&2)
			;;
		t)
			case ${OPTARG} in
				g.vcf|vcf)
					export FINAL_TYPE=${OPTARG}
					(printf "%-22s%s (.gz)\n" "Final type" $FINAL_TYPE 1>&2)
					;;
				*)
					(echo "FAIL: Invalid final type: ${OPTARG}." 1>&2)
					# Print out final type usage section
					usage | tail -n 4 | head -n 2
					exit 1
					;;
			esac
			;;
		*)
			usage
			exit 1
			;;
	esac
done

[ "$FINAL_TYPE" == "" ] && export FINAL_TYPE="g.vcf"
[ "$ENTRY_POINT" == "" ] && export ENTRY_POINT=RS

if [ "${SAMPLE}" == "" ] || [ "${PLATFORM}" == "" ]; then
	(echo "FAIL: Missing required parameter!" 1>&2)
	# Print out required section.
	usage # | head -n 20
	exit 1
fi

if [ "$MAIL_USER" == "" ]; then
	if [ -e /etc/slurm/userlist.txt ]
	then
		oldIFS=$IFS
		IFS=$'\n'
		userList=($(cat /etc/slurm/userlist.txt | grep $USER))
		for entry in ${userList[@]}; do
			testUser=$(echo $entry | awk -F':' '{print $1}')
			if [ "$testUser" == "$USER" ]; then
				export MAIL_USER=$(echo $entry | awk -F':' '{print $3}')
				break
			fi
		done
		IFS=$oldIFS
	fi
	
	if [ "$MAIL_USER" == "" ]; then
		(echo "FAIL: Unable to locate email address for $USER or /etc/slurm/userlist.txt does not exist!" 1>&2)
		# Print out email address usage section.
		usage | tail -n 18 | head -n 2
		exit 1
	else
		export MAIL_TYPE=FAIL,TIME_LIMIT,TIME_LIMIT_90
		(printf "%-22s%s (%s)\n" "Email address" "${MAIL_USER}" "$MAIL_TYPE" 1>&2)
	fi
fi

export IDN=$(echo ${SAMPLE} | awk -F'[[:blank:]_]' '{print $1}')
export DNA=$(echo ${SAMPLE} | awk -F'[[:blank:]_]' '{print $2}')
export LIB=$(echo ${SAMPLE} | awk -F'[[:blank:]_]' '{print $3}')
export RUN=$(echo ${SAMPLE} | awk -F'[[:blank:]_]' '{print $4}')

export SAMPLE_PATH=${WORK_PATH}/${IDN}
export RUN_PATH=${SAMPLE_PATH}/${DNA}_${LIB}_${RUN}

if ! mkdir -p ${RUN_PATH}/slurm; then
	(echo "FAIL: Error creating output folder!" 1>&2)
	exit 1
fi

if ! mkdir -p ${SAMPLE_PATH}/slurm; then
	(echo "FAIL: Error creating output folder!" 1>&2)
	exit 1
fi

(printf "%-22s%s\n" "Blocks" "$FASTQ_SPLITNM" 1>&2)
(printf "%-22s%s\n" "Location" "${WORK_PATH}" 1>&2)

(printf "%-22s" "Command" 1>&2)
echo $0 ${@} | tee ${SAMPLE_PATH}/jobReSubmit.sh
chmod +x ${SAMPLE_PATH}/jobReSubmit.sh

date '+%Y%m%d_%H%M%S' >> ${WORK_PATH}/${IDN}/starttime.txt

case $ENTRY_POINT in
	RS)
		##################################
		# Split read 1 and 2 into chunks #
		##################################
		
		cd $RUN_PATH
		
		(printf "%-22s" "ReadSplitter" 1>&2)
		
		splitReadArray=""
		
		for i in $(seq 1 2); do
			# Cycle through reads.
			if [ ! -e ${RUN_PATH}/${SAMPLE}_R${i}_split.done ]; then
				# Read# split isn't complete. Add to array.
				splitReadArray=$(appendList "$splitReadArray" ${i} ",")
			fi
		done
		
		############################
		# Launch needed split jobs #
		############################
		
		if [ "$splitReadArray" != "" ]; then
			if echo $splitReadArray | grep 1 1>/dev/null;
			then
				if [ ! -e ${FILE_LIST[0]} ]
				then
					echo "FAIL Read 1 ${FILE_LIST[0]} file does not exist!"
					exit 1
				fi
				read1Size=$(ls -lah ${FILE_LIST[0]} | awk '{print $5}')
			else
				read1Size=0
			fi
			
			if echo $splitReadArray | grep 2 1>/dev/null;
			then
				if [ ! -e ${FILE_LIST[1]} ]
				then
					echo "FAIL Read 1 ${FILE_LIST[1]} file does not exist!"
					exit 1
				fi
				read2Size=$(ls -lah ${FILE_LIST[1]} | awk '{print $5}')
			else
				read2Size=0
			fi
			
			if [ "$SMART_READS" != "" ]; then
				# Split reads into SMART_READS number of blocks.
				# Count lines in read file (LONG!)
				FASTQ_MAXREAD=$(echo $(unpigz -cd ${FILE_LIST[0]} | wc -l) 4 $SMART_READS | awk '{printf "%d", ((($1/$2)/$3)+(($1/$2)%$3))}')
			fi
			
			# Split array contains data so run the missing split function.
			DEP_RS=$(sbatch $(dispatch "RS") -J RS_${SAMPLE}_${read1Size}_${read2Size} -a ${splitReadArray}${ARRAYTHROTTLE} $SLSBIN/readsplit.sl -s $SAMPLE -i ${FILE_LIST[0]} -i ${FILE_LIST[1]} -b $FASTQ_SPLITNM $MULTI_RUN -p $PLATFORM | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_RS" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				(printf "%sx%-4d [%s] Logs @ %s\n" "${DEP_RS}" $(splitByChar "$splitReadArray" "," | wc -w) "$splitReadArray" "${RUN_PATH}/slurm/RS_${DEP_RS}_*.out" 1>&2)
				echo $DEP_RS > ../lastJob.txt
			fi
		else
			(printf "done\n" 1>&2)
			#${PBIN}/spool_sample.sh -e BA -s $SAMPLE -p $PLATFORM $MULTI_RUN -e BA
		fi
		;&
	BA)
		##########################
		# Generate Block Alignment
		##########################
		
		cd $RUN_PATH	# Make sure we're in the right folder.
		
		(printf "%-22s" "Align->Sort->Split" 1>&2)
		
		if [ "$ENTRY_POINT" == "BA" ]; then
			if [ "${#FILE_LIST[@]}" -lt "2" ]; then
				alignInput=""
				readBlocks=$(find $RUN_PATH/blocks -type f -iname "R1_*.fastq.gz" | wc -l)
			elif [ "${#FILE_LIST[@]}" -eq "2" ]; then
				alignInput="-i ${FILE_LIST[0]} -i ${FILE_LIST[1]}"
				readBlocks="1"
			fi
		else
			alignInput=""
			readBlocks=${FASTQ_SPLITNM}
		fi
		
		for i in $(seq 1 $readBlocks); do
			if [ ! -e ${RUN_PATH}/split/$(printf "%0${FASTQ_MAXZPAD}d" $i)/contig_split.done ]; then
				# This contig block hasn't been split yet.
				alignArray=$(appendList "$alignArray" $i ",")
			fi
		done
		
		if [ "$alignArray" != "" ]; then
			DEP_BA=$(sbatch $(dispatch "BA") -J BA_${SAMPLE} --array=${alignArray}${ARRAYTHROTTLE} $(depCheck $DEP_RS) $SLSBIN/blockalign.sl -s $SAMPLE $alignInput $MULTI_RUN | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_BA" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				echo $ALIGNMESG
				exit 1
			else
				(printf "%sx%-4d [%s] Logs @ %s\n" "${DEP_BA}" $(splitByChar "$alignArray" "," | wc -w) $(condenseList "$alignArray") "${RUN_PATH}/slurm/BA_${DEP_BA}_*.out" 1>&2)
				echo $DEP_BA > ../lastJob.txt
			fi
		else
			(printf "done\n" 1>&2)
		fi
		
		if [ "$MULTI_RUN" != "" ]
		then
			(echo "Mutliple run mode. Stopping at alignment." 1>&2)
			(echo "Launch last run without multi-run mode enabled to complete." 1>&2)
			exit 0
		fi
		;&
	MM)
		############################################
		# Merge Contig blocks and mark duplicates. #
		############################################
		
		cd $SAMPLE_PATH	# Make sure we're in the right folder.
		
		(printf "%-22s" "Merge and Mark"  1>&2)
		
		if [ "$ENTRY_POINT" == "MM" ]; then
			mergeInput="-i ${FILE_LIST[0]}"
			mergeArray="1"
		else
			mergeInput=""
			mergeArray=""
			for i in $(seq 1 ${NUMCONTIGS}); do
				contig=${CONTIGARRAY[$i]}	# Does bash do array lookups every time too?
				#printf "%04d %-22s " $i $contig
				mergeOutput=${SAMPLE_PATH}/markdup/${contig}.bam
				mkdir -p $(dirname $mergeOutput)
				if [ ! -e ${mergeOutput}.done ]; then
					mergeArray=$(appendList "$mergeArray"  $i ",")
					#printf "MD "
				fi
			done
		fi
		
		if [ "$mergeArray" != "" ]; then
			#echo "CMD: sbatch $(dispatch \"MM\") -J MM_${IDN} --array $mergeArray $(depCheck $DEP_BA) $SLSBIN/mergeandmark.sl"
			DEP_MM=$(sbatch $(dispatch "MM") -J MM_${IDN} --array ${mergeArray}${ARRAYTHROTTLE} $(depCheck $DEP_BA) $SLSBIN/mergeandmark.sl $mergeInput | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_MM" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				(printf "%sx%-4d [%s] Logs @ %s\n" "$DEP_MM" $(splitByChar "$mergeArray" "," | wc -w) $(condenseList "$mergeArray") "${SAMPLE_PATH}/slurm/MM_${DEP_MM}_*.out" 1>&2)
			fi
		else
			(printf "done\n" 1>&2)
		fi
		;&
	RC)
		#####################
		# BQSR & PrintReads #
		#####################
		
		cd $SAMPLE_PATH	# Make sure we're in the right folder.
		
		(printf "%-22s" "Recalibration" 1>&2)
		
		if [ "$ENTRY_POINT" == "RC" ]; then
			recalInput="-i ${FILE_LIST[0]}"
		else
			recalInput=""
		fi
		
		recalArray=""
		for i in $(seq 1 ${NUMCONTIGS}); do
			contig=${CONTIGARRAY[$i]}	# Does bash do array lookups every time too?
			#printf "%04d %-22s " $i $contig
			recalOutput=${SAMPLE_PATH}/printreads/${contig}.bam
			catReadsInputs=$(appendList "$catReadsInputs" "-i ${recalOutput}" " ")
			mkdir -p $(dirname $recalOutput)
			
			if [ ! -e ${recalOutput}.done ]; then
				recalArray=$(appendList "$recalArray" $i ",")
				#printf "PR "
			fi
		done
		
		if [ "$recalArray" != "" ]; then
			DEP_RC=$(sbatch $(dispatch "RC") -J RC_${IDN} --array ${recalArray}${ARRAYTHROTTLE} $(depCheck $DEP_MM) $SLSBIN/recalibration.sl $recalInput | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_RC" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				# Tie each task to the matching task in the previous array.
				tieTaskDeps "$recalArray" "$DEP_RC" "$mergeArray" "$DEP_MM"
				(printf "%sx%-4d [%s] Logs @ %s\n" "$DEP_RC" $(splitByChar "$recalArray" "," | wc -w) $(condenseList "$recalArray") "${SAMPLE_PATH}/slurm/RC_${DEP_RC}_*.out" 1>&2)
			fi
		else
			(printf "done\n" 1>&2)
		fi
		
		######################################
		# Concatonate Reads into single BAM. #
		######################################
		
		cd $SAMPLE_PATH	# Make sure we're in the right folder.
		
		(printf "%-22s" "ConcatReads" 1>&2)
		
		catReadsOutput=${SAMPLE_PATH}/${IDN}.bam
		
		# Merge print-read bams.
		if [ ! -e ${catReadsOutput}.done ]; then
			DEP_CR=$(sbatch $(dispatch "CR") -J CR_${IDN} $(depCheck $DEP_RC) $SLSBIN/catreads.sl $catReadsInputs -o $catReadsOutput | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_CR" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				(printf "%s Log @ %s\n" "$DEP_CR"  "${SAMPLE_PATH}/slurm/CR_${DEP_CR}.out" 1>&2)
			fi
		else
			(printf "done\n" 1>&2)
		fi
		
		#################################
		# Index Concatonated Reads BAM. #
		#################################
		
		cd $SAMPLE_PATH	# Make sure we're in the right folder.
		
		(printf "%-22s" "Index Reads" 1>&2)
		
		if [ ! -e ${catReadsOutput%.bam}.bai.done ]; then
			DEP_RI=$(sbatch $(dispatch "RI") -J RI_${IDN} $(depCheck $DEP_CR) $SLSBIN/catreadsindex.sl -i $catReadsOutput -o ${catReadsOutput%.bam}.bai | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_RI" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				(printf "%s Log @ %s\n" "$DEP_RI" "${SAMPLE_PATH}/slurm/RI_${DEP_RI}.out" 1>&2)
			fi
		else
			(printf "done\n" 1>&2)
		fi
		;&
	DC|HC|GD)
		#####################
		# Depth of Coverage #
		#####################
		# Gender specific HaplotypeCaller and Gender Determination require depth
		# of coverage data to all three steps will start from this point.
		
		depthInput=""
		case $ENTRY_POINT in
			DC|HC|GD)
				if [ "${#FILE_LIST[@]}" -ge "1" ]; then
					for file in ${FILE_LIST[@]}; do
						if [ ! -e ${file%.*}.bai ]; then
							# BAM index doesn't exist!
							(printf "%-22s" "Indexing Reads" 1>&2)
							DEP_RC=$(sbatch $(dispatch "RI") -J RI_$IDN $SLSBIN/catreadsindex.sl $file ${file%.bam}.bai | awk '{print $4}')
							if [ $? -ne 0 ] || [ "$DEP_RC" == "" ]; then
								(printf "FAILED!\n" 1>&2)
								exit 1
							else
								(printf "%s Log @ %s\n" "$DEP_RC" "${SAMPLE_PATH}/slurm/RI_${DEP_RC}.out" 1>&2)
							fi
						fi
						depthInput="$depthInput -i ${FILE_LIST[0]}"
					done
				fi
				;;
		esac
			
		cd $SAMPLE_PATH	# Make sure we're in the right folder.
		
		depthArray=""
		for i in $(seq 1 ${NUMCONTIGS}); do
			contig=${CONTIGARRAY[$i]}	# Does bash do array lookups every time too?
			#printf "%04d %-22s " $i $contig
			
			depthOutput=${SAMPLE_PATH}/depth/${contig} #.sample_summary
			
			mkdir -p $(dirname $depthOutput)
			
			if [ "$contig" != "MT" ] && [ "$contig" != "hs37d5" ] && [ "$contig" != "NC_007605" ] && [[ $contig != GL* ]]; then	# skip non relevant contigs.
				if [ ! -e ${depthOutput}.done ]; then
					depthArray=$(appendList "$depthArray" $i ",")
					#printf "DC "
				fi
			fi
		done
		
		(printf "%-22s" "Depth of Coverage" 1>&2)
		
		if [ "$depthArray" != "" ]; then
			DEP_DC=$(sbatch $(dispatch "DC") -J DC_${IDN} --array ${depthArray}${ARRAYTHROTTLE} $(depCheck $DEP_RC) $SLSBIN/depthofcoverage.sl -p $PLATFORM $depthInput | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_DC" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				# Tie each task to the matching task in the previous array.
				tieTaskDeps "$depthArray" "$DEP_DC" "$recalArray" "$DEP_RC"
				(printf "%sx%-4d [%s] Logs @ %s\n" "$DEP_DC" $(splitByChar "$depthArray" "," | wc -w) $(condenseList "$depthArray") "${SAMPLE_PATH}/slurm/DC_${DEP_DC}_*.out" 1>&2)
			fi
		else
			(printf "done\n" 1>&2)
		fi
		
#		;&
#	HC)
		##################################
		# HaplotypeCaller on Final BAMs. #
		##################################
		# Runs from Depth of Coverage as Gender determination and Gender
		# specific HaplotypeCaller require Depth of Coverage output.
		
		cd $SAMPLE_PATH	# Make sure we're in the right folder.
		
		# Gather CatVariants Dependencies.
		CatVarDeps=""
		
		# List of incomplete jobs.
		haploArray=""
		
		# Loop though number of contigs in reference sequence.
		# Build list of incomplete merged contigs.
		for i in $(seq 1 ${NUMCONTIGS}); do
			# Build input/output file names
			contig=${CONTIGARRAY[$i]}	# Does bash do array lookups every time too?
			#printf "%04d %-22s " $i $contig
			
			haploOutput=${SAMPLE_PATH}/haplo/${contig}.${FINAL_TYPE}.gz
			
			mkdir -p $(dirname $haploOutput)
			
			if [ "$contig" != "X" ] && [ "$contig" != "Y" ] && [ "$contig" != "MT" ] && [ "$contig" != "hs37d5" ] && [ "$contig" != "NC_007605" ]; then	#Skip sex and mitochondrial chromosomes
				if [ ! -e ${haploOutput}.done ]; then
					haploArray=$(appendList "$haploArray" $i ",")
					#printf "HC "
				fi
			fi
			#printf "\n"
		done
		
		(printf "%-22s" "HaplotypeCaller" 1>&2)
		
		if [ "$haploArray" != "" ]; then
			DEP_HC=$(sbatch $(dispatch "HC") -J HC_${IDN} --array ${haploArray}${ARRAYTHROTTLE} $(depCheck $DEP_RC) $SLSBIN/haplotypecaller.sl -p ${PLATFORM} $depthInput | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_HC" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				# Tie each task to the matching task in the previous array.
				tieTaskDeps "$haploArray" "$DEP_HC" "$recalArray" "$DEP_RC"
				(printf "%sx%-4d [%s] Logs @ %s\n" "$DEP_HC" $(splitByChar "$haploArray" "," | wc -w) $(condenseList "$haploArray") "${SAMPLE_PATH}/slurm/HC_${DEP_HC}_*.out" 1>&2)
				CatVarDeps=$(appendList "$CatVarDeps" "${DEP_HC}" ":")
			fi
		else
			(printf "done\n" 1>&2)
		fi
		
#		;&
#	GD)
		##############################################
		# Automatic Chromosomal Gender Determination #
		##############################################
		# Runs from Depth of Coverage as Gender determination and Gender
		# specific HaplotypeCaller require Depth of Coverage output.

		cd $SAMPLE_PATH	# Make sure we're in the right folder.
		
		(printf "%-22s" "Gender Determination" 1>&2)

		if [ ! -e ${SAMPLE_PATH}/coverage.sh.done ]; then
			DEP_GD=$(sbatch $(dispatch "GD") -J GD_${IDN} $(depCheck $DEP_DC) $SLSBIN/coverage.sl -s $IDN -p $PLATFORM $([ "$GENDER" != "" ] && echo "-g $GENDER") $([ "$SEXCHR" != "" ] && echo "-c $SEXCHR") | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_GD" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				(printf "%s Log @ %s\n" "$DEP_GD" "${SAMPLE_PATH}/slurm/GD_${DEP_GD}.out" 1>&2)
			fi
		else
			(printf "done\n" 1>&2)
		fi
		
		haploXInput=printreads/X.bam
		haploYInput=printreads/Y.bam
		
		haploXPar1Output=haplo/${XPAR1}.${FINAL_TYPE}.gz
		haploTRUEXOutput=haplo/${TRUEX}.${FINAL_TYPE}.gz
		haploXPar2Output=haplo/${XPAR2}.${FINAL_TYPE}.gz
		    haploYOutput=haplo/Y.${FINAL_TYPE}.gz
		
		mkdir -p $(dirname ${haploXPar1Output})
		mkdir -p $(dirname ${haploTRUEXOutput})
		mkdir -p $(dirname ${haploXPar2Output}) 
		mkdir -p $(dirname ${haploYOutput})
		
		(printf "%-22s" "HaplotypeCaller XPAR1" 1>&2)
		
		if [ ! -e ${SAMPLE_PATH}/${haploXPar1Output}.done ]; then
			DEP_HCXPAR1=$(sbatch $(dispatch "HC") -J HC_${IDN}_XPAR1 --array=996 $(depCheck $DEP_GD) $SLSBIN/haplotypecaller.sl  -c "$XPAR1" $depthInput | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_HCXPAR1" == "" ]; then
				(printf "FAILED!\n"  1>&2)
				exit 1
			else
				(printf "%s Log @ %s\n" "$DEP_HCXPAR1" "${SAMPLE_PATH}/slurm/HC_${DEP_HCXPAR1}_90.out" 1>&2)
				CatVarDeps=$(appendList "$CatVarDeps" "${DEP_HCXPAR1}" ":")
			fi
		else
			(printf "done\n" 1>&2)
		fi
		
		(printf "%-22s" "HaplotypeCaller TRUEX" 1>&2)
		
		if [ ! -e ${SAMPLE_PATH}/${haploTRUEXOutput}.done ]; then
			DEP_HCTRUEX=$(sbatch $(dispatch "HC") -J HC_${IDN}_TRUEX --array=997 $(depCheck $DEP_GD) $SLSBIN/haplotypecaller.sl -c "$TRUEX" $depthInput | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_HCTRUEX" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				(printf "%s Log @ %s\n" "$DEP_HCTRUEX" "${SAMPLE_PATH}/slurm/HC_${DEP_HCTRUEX}_91.out" 1>&2)
				CatVarDeps=$(appendList "$CatVarDeps" "${DEP_HCTRUEX}" ":")
			fi
		else
			(printf "done\n" 1>&2)
		fi
		
		(printf "%-22s" "HaplotypeCaller XPAR2" 1>&2)
		
		if [ ! -e ${SAMPLE_PATH}/${haploXPar2Output}.done ]; then
			DEP_HCXPAR2=$(sbatch $(dispatch "HC") -J HC_${IDN}_XPAR2 --array=998 $(depCheck $DEP_GD) $SLSBIN/haplotypecaller.sl -c "$XPAR2" $depthInput | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_HCXPAR2" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				(printf "%s Log @ %s\n" "$DEP_HCXPAR2" "${SAMPLE_PATH}/slurm/HC_${DEP_HCXPAR2}_92.out" 1>&2)
				CatVarDeps=$(appendList "$CatVarDeps" "${DEP_HCXPAR2}" ":")
			fi
		else
			(printf "done\n" 1>&2)
		fi
		
		(printf "%-22s" "HaplotypeCaller Y" 1>&2)
		
		if [ ! -e ${SAMPLE_PATH}/${haploYOutput}.done ]; then
			DEP_HCY=$(sbatch $(dispatch "HC") -J HC_${IDN}_Y --array=999 $(depCheck $DEP_GD) ${SLSBIN}/haplotypecaller.sl -c "Y" $depthInput | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_HCY" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				(printf "%s Log @ %s\n" "$DEP_HCY"  "${SAMPLE_PATH}/slurm/HC_${DEP_HCY}_93.out" 1>&2)
				CatVarDeps=$(appendList "$CatVarDeps" "${DEP_HCY}" ":")
			fi
		else
			(printf "done\n" 1>&2)
		fi
		;&
	CV)
		#############################
		# Concatonate Variants VCFs #
		#############################
		
		cd $SAMPLE_PATH	# Make sure we're in the right folder.
		
		(printf "%-22s" "CatVariants" 1>&2)
		
		catVarOutput=${SAMPLE_PATH}/${IDN}.${FINAL_TYPE}.gz
		CatVarInputs=""
		
		for contig in ${CONTIGARRAY[@]}; do
			if [ "$contig" == "MT" ] || [ "$contig" == "hs37d5" ] || [ "$contig" == "NC_007605" ]; then
				continue	# Skip Mitochondria, hs37d5 decoys and NC_007605 decoy since we don't call them.
			elif [ "$contig" == "X" ]; then
				CatVarInputs=$(appendList "$CatVarInputs" "-i haplo/${XPAR1}.${FINAL_TYPE}.gz")
				CatVarInputs=$(appendList "$CatVarInputs" "-i haplo/${TRUEX}.${FINAL_TYPE}.gz")
				CatVarInputs=$(appendList "$CatVarInputs" "-i haplo/${XPAR2}.${FINAL_TYPE}.gz")
			else
				CatVarInputs=$(appendList "$CatVarInputs" "-i haplo/${contig}.${FINAL_TYPE}.gz")
			fi
		done
		
		if [ ! -e ${catVarOutput}.done ]; then
			DEP_CV=$(sbatch $(dispatch "CV") -J CV_${IDN} $(depCheck $CatVarDeps) $SLSBIN/catvar.sl $CatVarInputs -o $catVarOutput | awk '{print $4}')
			if [ $? -ne 0 ] || [ "$DEP_CV" == "" ]; then
				(printf "FAILED!\n" 1>&2)
				exit 1
			else
				(printf "%s Log @ %s\n" "$DEP_CV" "${SAMPLE_PATH}/slurm/CV_${DEP_CV}.out" 1>&2)
			fi
		else
			(printf "done\n"  1>&2)
		fi
		;;
	?)
		(echo "But why? How? What is going on here!!" 1>&2)
		usage
		exit 1
		;;
esac
