#!/bin/bash -e
#SBATCH --job-name	GenderDetermination
#SBATCH --time		0-00:10:00
#SBATCH --mem		512
#SBATCH --cpus-per-task	1
#SBATCH --error		slurm/GD_%j.out
#SBATCH --output	slurm/GD_%j.out

echo "$(date) on $(hostname)"

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
*   -p [PLATFORM]  Capture platform/Exome chip.
*                  List of .bed files is at \$PLATFORMS ($PLATFORMS)
*
* Optional:
*   ${ylw}-c [STRING]    WIP${nrm}
*                  Force HaplotypeCaller on X & Y with specified ploidy.
*                  Entered as XY combination: XX, XY, XXY, XYY, XXYY, etc.
*                  Default: Automatic detection.
*   ${ylw}-g [Gender]    WIP${nrm}
*                  Gender: Male/Female/Unknown
*                  Default: automatic detection.
*   -h             Print help/usage information.
*   -i [FILE]      Input file. Can be specified multiple times.
*                  Required for initial run or Entrypoint injection.
*   -r [FILE]      Full path to reference file.
*                  Default: \$REF_CORE ($REF_CORE)
*   -s [IDLR]      Sample ID string: ID_DNAID_LIBRARY_RUN.
*                  This is used to determine individuals with multiple segments.
*                  If only an ID is given, multiple-runs cannot be processed.
*
*
*********************************"
}

while getopts "p:c:g:hi:r:s:" OPTION
do
	case $OPTION in
		c)
			export SEXCHR=${OPTARG}
			(printf "%-22s%s (%s)\n" "#Sex Chromosomes" $SEXCHR "Warns on Autodetermination mismatch!"1>&2)
			;;
		g)
			case ${OPTARG,,} in
				m*)
					export GENDER="Male"
					;;
				f*)
					export GENDER="Female"
					;;
				?)
					export GENDER="Unknown"
					;;
			esac
			(printf "%-22s%s (%s)\n" "#Gender" $GENDER "Fail on Autodetermination mismatch!" 1>&2)
			;;
		h)
			usage
			exit 0
			;;
		i)
			if [ ! -e ${OPTARG} ]; then
				(echo "#FAIL: Input file $OPTARG does not exist!" 1>&2)
				exit 1
			fi
			if [[ " ${FILE_LIST[@]} " =~ " ${OPTARG} " ]]
			then
				(echo "FAIL: Input file $OPTARG already added. Perhaps you want Read 2?" 1>&2)
				exit 1
			fi
			export FILE_LIST=(${FILE_LIST[@]} ${OPTARG})
			(printf "%-22s%s\n" "#Input file" $OPTARG 1>&2)
			;;
		p)
			if [ ! -e $PLATFORMS/$OPTARG.bed ]; then
				echo "#FAIL: Unable to located $PLATFORMS/$OPTARG.bed!"
				exit 1
			fi
			export PLATFORM=${OPTARG}
			(printf "%-22s%s (%s)\n" "#Platform" $PLATFORM $(find $PLATFORMS/ -type f -iname "$PLATFORM.bed") 1>&2)
			;;
		r)
			export REF=${OPTARG}
			if [ ! -e $REF ]; then
				(echo "#FAIL: $REF does not exist" 1>&2)
				exit 1
			fi
			export REFA=$REF.fasta
			(printf "%-22s%s\n" "#Reference sequence" $REF 1>&2)
			;;
		s)
			export IDN=${OPTARG}
			(printf "%-22s%s\n" "#Sample ID" $SAMPLE 1>&2)
			;;
		?)
			echo "FAILURE: ${OPTION} ${OPTARG} is not valid!"
			usage
			exit 1
			;;
	esac
done

OUTPUT=coverage.sh

echo "#This file contains gender definitions for individual ${IDN}." | tee ${OUTPUT}
echo "#GD: ${PLATFORM}" | tee -a ${OUTPUT}
echo "" | tee -a ${OUTPUT}

source ${PLATFORMS}/${PLATFORM}.sh

   aCount=0
aCoverage=0
xCoverage=0
yCoverage=0

ren='^[0-9]+$'

printf "#%-10s %8s %s\n" "Chromosome" "Coverage" "Count" | tee -a ${OUTPUT}

for contig in ${CONTIGBLOCKS[@]}; do
	if [ "$contig" != "MT" ] && [ "$contig" != "hs37d5" ] && [ "$contig" != "NC_007605" ] && [[ $contig != GL* ]]; then
		INPUT=depth/${contig}.sample_summary
		if [ ! -e ${INPUT} ]; then
			# Oh crappola!
			echo "#${contig} file ${INPUT} doesn't exist!" | tee -a ${OUTPUT}
			echo "exit 1" | tee -a ${OUTPUT}
			exit $EXIT_IO
		fi
		
		contigCount=$(awk 'NR==2{print $2}' ${INPUT})
		contigCover=$(awk 'NR==2{print $3}' ${INPUT})
		printf "#%-10s %8s %s\n" ${contig} ${contigCover} ${contigCount} | tee -a ${OUTPUT}
		
		if [[ $contig =~ $ren ]] || [[ $contig =~ chr$ren ]]; then	# Contig is a number
			aCount=$(($aCount + $contigCount))
			aCoverage=$(echo "($aCoverage + ($contigCount * $contigCover))" | bc)
		elif [[ $contig == X ]]; then
			xCoverage=${contigCover}
		elif [[ $contig == Y ]]; then
			yCoverage=${contigCover}
		fi
	fi
done

echo "" | tee -a ${OUTPUT}

aCoverage=$(echo "scale=2;$aCoverage/$aCount" | bc)

xaRatio=$(echo "scale=3; $xCoverage/$aCoverage" | bc | sed 's/^\./0./')
yaRatio=$(echo "scale=3; $yCoverage/$aCoverage" | bc | sed 's/^\./0./')
xCount=$(echo "scale=3; ($xCoverage/$aCoverage)/$XRat" | bc | sed 's/^\./0./')
yCount=$(echo "scale=3; ($yCoverage/$aCoverage)/$YRat" | bc | sed 's/^\./0./')

Xmin=$(echo "scale=3;$xCount - $XVar" | bc | sed 's/^\./0./')
Xmax=$(echo "scale=3;$xCount + $XVar" | bc | sed 's/^\./0./')
Ymin=$(echo "scale=3;$yCount - $YVar" | bc | sed 's/^\./0./')
Ymax=$(echo "scale=3;$yCount + $YVar" | bc | sed 's/^\./0./')

printf "%-20s %6s\n" "#Autosomal coverage:" ${aCoverage} | tee -a ${OUTPUT}
printf "%-20s %6s\n" "#True-X coverage:" ${xCoverage} | tee -a ${OUTPUT}
printf "%-20s %6s\n" "#True-Y coverage:" ${yCoverage} | tee -a ${OUTPUT}
printf "%-20s %6s\n" "#X:A ratio:" ${xaRatio} | tee -a ${OUTPUT}
printf "%-20s %6s\n" "#Y:A ratio:" ${yaRatio} | tee -a ${OUTPUT}
printf "%-20s %6s %s\n" "#Fractional X:" ${xCount} "($Xmin -> $Xmax)" | tee -a ${OUTPUT}
printf "%-20s %6s %s\n" "#Fractional Y:" ${yCount} "($Ymin -> $Ymax)" | tee -a ${OUTPUT}

xChromes=0
yChromes=0

# Count X and Y chromosomes that fall within boundaries from whole numbers between 1 and 4: XXXXYYYY at most.
for i in `seq 4`
do
	XinRange=$(echo "$i <= $Xmax && $i >= $Xmin" | bc)
	YinRange=$(echo "$i <= $Ymax && $i >= $Ymin" | bc)
	
	if [ $XinRange -eq 1 ]
	then
		printf "%-20s %6s\n" "#X (in boundary):" $i | tee -a ${OUTPUT}
		xChromes=$i
	fi
	
	if [ $YinRange -eq 1 ]
	then
		printf "%-20s %6s\n" "#Y (in boundary):" $i | tee -a ${OUTPUT}
		yChromes=$i
	fi
done


# Build chromosome string.
if [ $xChromes -gt 0 ]
then
	# There are X chromosomes within the defined boundaries.
	# Write a line of that many Xs.
	sexchromosomes=$(for a in `seq ${xChromes}`; do echo -n X; done)
elif [ $(echo "scale=3;$xCount > (1.0 - $XVar)" | bc) -eq 1 ]
then
	# There are no X chromosomes within the boundaries.
	# Frational portions of X are greater than ONE.
	# Append these chromosomes with an E mark!
	#echo "# WARN: No X chromosomes within boundaries but fractional X is greater than 1" | tee -a ${OUTPUT}
	sexchromosomes=E$(for a in `seq ${xCount}`; do echo -n X; done)
else
	# There are no X chromosomes within the boundaries.
	# Frations of X found are below the lowest possible boundary.
	# Set the number of X chromoromes to ZERO.
	sexchromosomes="0"
fi

if [ $yChromes -gt 0 ]
then
	# There are Y chromosomes within the defined boundaries.
	# Write a line of that many Ys
	sexchromosomes=${sexchromosomes}$(for a in `seq ${yChromes}`; do echo -n Y; done)
elif [ $(echo "scale=3;$yCount > (1.0 - $YVar)" | bc) -eq 1 ]
then
	# There are no Y chromosomes within the boundaries.
	# Fraction portions of Y are greater than ONE.
	# Append these chromosomes with an E mark.
	#echo "# WARN: No Y chromosomes within boundaries but fractional Y is greater than 1" | tee -a ${OUTPUT}
	sexchromosomes=${sexchromosomes}E$(for a in `seq ${yCount}`; do echo -n Y; done)
elif [ $xChromes -eq 1 ]
then
	# There are no Y chromosomes within the boundaries.
	# There is ONE X chromosome.
	# Fractional portions of Y are below lowest possible boundary.
	# Set the number of Y chromosomes to ZERO.
	sexchromosomes=${sexchromosomes}0
fi

# Decide overall gender
if [[ $xChromes -eq 0 ]]
then
	# Could not find any X chromosomes so FAIL!
	calculatedgender="Unknown"
else
	# There is at least ONE X chromosome
	if [[ $yChromes -eq 0 ]] && [[ $(echo "scale=3;$yCount < (1.0 - $YVar)" | bc) -eq 1 ]]
	then
		# There are no Y chromosomes within the boundaries.
		# There are no fractional Y chromosome portions greater than the lowest possible broundry.
		calculatedgender="Female"
	else
		# There are at least 1 full Y chromosome present, even if it falls outside the boundaries.
		calculatedgender="Male"
	fi
fi

printf "%-20s %6s\n" "#SexChr:" $sexchromosomes | tee -a ${OUTPUT}
printf "%-20s %6s\n" "#Gender:" $calculatedgender | tee -a ${OUTPUT}

if [ "$GENDER" != "" ] && [ "$GENDER" != "$calculatedgender" ]; then
	echo "#Determined gender $calculatedgender does not match specified gender $GENDER." | tee -a ${OUTPUT}
	sbatch --mail-user $MAIL_USER --mail-type=FAIL --job-name="${SAMPLE}_ALERT_Gender_Mismatch_Specified_${GENDER}_Found_${calculatedgender}" $SLSBIN/genderfail.sl
fi

if [ "$SEXCHR" == "" ]; then
	if [ $xChromes -eq 0 ]; then
		echo "#Unknown gender. Please check capture platform or sample contamination!" | tee -a ${OUTPUT}
		echo "exit 1" >> ${OUTPUT}
		exit $EXIT_PR
	fi

	if [ $xChromes -lt 2 ] && [ $yChromes -lt 1 ]; then
		echo "#Unknown gender. Please check capture platform or sample contamination!" | tee -a ${OUTPUT}
		echo "exit 1" >> ${OUTPUT}
		exit $EXIT_PR
	fi
else
	if [ "$SEXCHR" != "$sexchromosomes" ]; then
		echo "#Determined gender chromosomes $sexchromosomes do not match specified gender chromosomes $SEXCHR." | tee -a ${OUTPUT}
		echo "#Processing as $SEXCHR" | tee -a ${OUTPUT}
		sbatch --mail-user $MAIL_USER --mail-type=FAIL --job-name="${SAMPLE}_ALERT_Chromosomal_Gender_Mismatch_Specified_${SEXCHR}_Found_${sexchromosomes}" $SLSBIN/genderfail.sl
		xChromes=$(echo $SEXCHR | awk -F"[xX]" '{print NF-1}')
		yChromes=$(echo $SEXCHR | awk -F"[yY]" '{print NF-1}')
	fi
fi

echo "" | tee -a ${OUTPUT}

echo "X_CHROMOSOMES=$xChromes" | tee -a ${OUTPUT}
echo "Y_CHROMOSOMES=$yChromes" | tee -a ${OUTPUT}

touch ${OUTPUT}.done
