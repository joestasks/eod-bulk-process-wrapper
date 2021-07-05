#!/bin/bash

print_help()
{
	echo ""
	echo "The following commands set up the environment:"
	echo "______________________________________________"
	echo ""
	echo "module use /g/data/v10/public/modules/modulefiles"
	echo "module load dea"
	echo "pip install --upgrade --user eodatasets3"
	echo ""
	echo "======"
	echo "= Or ="
	echo "======"
	echo ""
	echo "Get latest Miniconda3 Linux 64-bit:"
	echo "-----------------------------------"
	echo "https://docs.conda.io/en/latest/miniconda.html"
	echo "./Miniconda3-py39_4.9.2-Linux-x86_64.sh"
	echo "conda deactivate"
	echo "conda config --set auto_activate_base false"
	echo "conda update -n base -c defaults conda"
	echo "conda create -n eo3_gdal"
	echo "conda activate eo3_gdal"
	echo "conda install -c conda-forge gdal"
	echo "conda install pytest"
	echo ""
	echo "Clone default branch (eodatasets3):"
	echo "-----------------------------------"
	echo "git clone https://github.com/GeoscienceAustralia/eo-datasets.git"
	echo "cd eo-datasets"
	echo "pip install -e ."
	echo "which eo3-prepare"
	echo "eo3-prepare --help"
	echo ""
	echo ""
	echo "Usage: ./eo3_bulk_process.sh [-h|c|i|o|l|r]"
	echo "options:"
	echo "	h	Print this help."
	echo "	c	Remove (clean) TAR files after processing if YAML file was generated."
	echo "	i	Input path where TAR files are located - optional, defaults to working directory."
	echo "	o	Output path where YAML files will be written - optional, defaults to directory name corresponding to TAR file."
	echo "	l	Path where log files are located - optional, defaults to working directory."
	echo "	r	Reprocess using existing directories with untared files."
	echo ""
}

while getopts ":hci:o:l:r" opt; do
	case $opt in
		h) print_help
		   exit 0
		   ;;
		c) clean_tar=1
		   ;;
		i) input_path_arg=$OPTARG
		   ;;
		o) output_path_arg=$OPTARG
		   ;;
		l) log_path_arg=$OPTARG
		   ;;
		r) reprocess=1
		   ;;
	       \?) echo "Invalid option: -$OPTARG" >&2
		   exit 1
		   ;;
		:) echo "Option -$OPTARG requires an argument" >&2
		   exit 1
		   ;;
	esac
done

WORKING_DIR=$(pwd)
LOG_PATH="$WORKING_DIR"
if [ ! -z "$log_path_arg" ]; then
	mkdir -p "$log_path_arg"
	cd "$log_path_arg"
	LOG_PATH=$(pwd)
	cd "$WORKING_DIR"
fi

LOG_DT_PID="$(date +%F_%X)_$BASHPID"
NO_YAML_LOG="$LOG_PATH/${LOG_DT_PID}_noyaml.log"
OUT_LOG="$LOG_PATH/${LOG_DT_PID}_out.log"
exec 1> >(tee "$OUT_LOG")
ERR_LOG="$LOG_PATH/${LOG_DT_PID}_err.log"
exec 2> >(tee "$ERR_LOG")

if [ ! -z "$input_path_arg" ]; then
	cd "$input_path_arg"
fi
input_path=$(pwd)
echo "Current input path is: $input_path"
FILES="./*.tar"
if [ "$reprocess" ]; then
	echo "Reprocess mode set to on, existing directories will be used instead of TAR files!"
	FILES="./*/"
fi

for f in $FILES
do
	echo "Processing $f ..."

	base_filename=$(basename -- "$f")
	extension="${base_filename##*.}"
	filename="${base_filename%.*}"
	yaml_filename="$filename.odc-metadata.yaml"

	if echo "$filename" | grep -qEo -- '[0-9]{8}_[0-9]{8}'; then
		output_path="./$filename"
		if [ ! -z "$output_path_arg" ]; then
			output_path="$output_path_arg"
		fi
		path_row=$(echo "$filename" | cut -d'_' -f 3)
		path="${path_row:0:3}"
		row="${path_row:3:3}"
		echo "Path of input file: $f"
		echo "Filename: $filename"
		echo "Output will go here: $output_path"
		echo "YAML Path: $path"
		echo "YAML Row: $row"

		if file --mime-type "$f" | grep -q tar$; then
			echo "$f is a TAR file"
			mkdir "$filename"
			mv "$f" "$filename"
			#cp "$f" "$filename" #testing
			cd "$filename"
			tar -xvf "$f"
			cd ..
		else
			echo "$f is not a TAR file"
		fi

		echo "Running eo3-prepare for $filename ..."
		eo3-prepare landsat-l1 --output-base "$output_path" "$filename" --producer 'usgs.gov'

		# Comment out the following lines to enable detection of existing YAML by
		# eo3-prepare and prevent reprocessing.
		cd "$filename"
		if [ "$clean_tar" ] && test -f "$path/$row/$yaml_filename"; then
			rm "$f"
		else
			mv "$f" "$input_path"
			echo "$filename" >> "$NO_YAML_LOG"
		fi
		mv "$path/$row/$yaml_filename" .
		rmdir -p "$path/$row"
		cd ..

		#exit #testing
	else
		echo "$f does not appear to be valid input => skipping"
	fi
done

cd "$WORKING_DIR"
if cat "$ERR_LOG" | grep -qE -- 'Traceback|Error|Invalid'; then
	echo ""
	echo "***> There were errors, check err.log!"
fi

