#!/bin/bash

# WORK IN PROGRESS
# Complete rewrite of convert.sh
# Goals:
# -) Improved readability
# -) Support for multiple audio streams
# -) Support for subtitles
# -) Basic analysis of applied filters (video filters? audio filters?)
# -) Better argument parsing
# -) Not as restrictive folder structure

# Next milestone:
# 	Establish basic conversion functionality for ONE input file

# TO-DO
# -) Advanced audio stream selection
#		-> count streams, adjust bitrate calculation
# -) Advanced audio options
#		-> stream copying, adjust bitrate based on channel count
# -) VP9 / Opus support
# -) Single pass
# -) Improve libvpx commands
# -) Multithreading
# -) Include filename in the metadata
# -) Option to disable filters during first pass


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Settings
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Default values
size_limit=3

audio_bitrate=0
audio_settings="-an"
sub_settings="-sn"
filter_settings=""
min_audio_bitrate=64

# Default behaviour
use_trim=false
use_audio=false
use_subs=false
mkv_fallback=false

# Initializing variables (don't touch)
file_list=()

# Error types
image_subs=false
wrong_trim=false

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

show_help() {
	echo -e "Restricted-WebM is a WebM creation script."
	echo -e "Its goal is to produce WebMs within a certain file size limit."
	echo -e "For further information visit https://github.com/HelpSeeker/Restricted-WebM\n"
	echo -e "Usage: webm.sh [OPTIONS]"
	echo -e "  or   webm.sh [OPTIONS] INPUT [INPUT]...\n"
	echo -e "Options:\n"
	echo -e " -h, --help\t\tshow this help"
	echo -e " -t, --trim\t\tprompt user for trim settings for each video"
	echo -e " -a, --audio\t\tuse input audio (if present)"
	echo -e " -s, --size <limit>\tspecify file size limit in MiB (default: 3)"
	echo -e " -f, --filter <string>\tpass custom ffmpeg filters"
	echo -e " --start <time>\t\tspecify start time for all input videos in sec."
	echo -e " --end <time>\t\tspecify end time for all input videos in sec."
	echo -e " --subtitles\t\tuse input subtitles (if present)"
	echo -e " --min-audio <bitrate>\tspecify min. audio bitrate in Kbps (default: 64)"
	echo -e " --mkv-fallback\t\tallow usage of MKV for image-based subtitles"
	echo -e ""
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

get_video_info() {
	in_duration=$(ffprobe -v error -show_entries format=duration \
					-of default=noprint_wrappers=1:nokey=1 "$input")
	out_duration=$in_duration
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Test input subtitles
get_sub_info() {
	# Throw error if subtitles can't be converted to webvtt (i.e. they're image-based)
	mkdir webm_temp 2> /dev/null
	ffmpeg -loglevel quiet -i "$input" -map 0:s? -c:s webvtt "webm_temp/sub.webm" || image_subs=true
	rm -r webm_temp
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#get_filter_info() {
#}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Get start/end time for trimming
get_trim_settings() {
	# Prompt user to specify start/end time (in seconds)
	echo "Specify start time (in sec). Default: 0"
	read -r start_time
	echo "~~~~~~~~~~~~~~~~~~"
	echo "Specify end time (in sec). Default: full length"
	read -r end_time
	echo "~~~~~~~~~~~~~~~~~~"
	
	# If no input, set start time to 0 and/or end time to video length
	[[ -z $start_time ]] && start_time=0
	[[ -z $end_time ]] && end_time=$in_duration		
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Add trim settings
get_input_settings() {
	# Set start/end time either via user input or default values
	if [[ -n $start_time_all ]]; then start_time=$start_time_all; else start_time=0; fi
	if [[ -n $end_time_all ]]; then end_time=$end_time_all; else end_time=$in_duration; fi

	# Get start/end time by prompting the user
	if [[ $use_trim = true ]]; then get_trim_settings; fi
	
	# Throw error for wrong start/end time
	if (( $(bc <<< "$start_time < 0") || $(bc <<< "$end_time <= $start_time") || $(bc <<< "$end_time > $in_duration") )); then
		wrong_trim=true
	fi
	
	out_duration=$(bc <<< "scale=3; $end_time-$start_time")
	
	# Create final input settings (trim settings + input)
	if (( start_time > 0 )); then
		input_settings=("-ss" "$start_time" "-i" "$input")
	else
		input_settings=("-i" "$input")
	fi
	
	if (( $(bc <<< "$end_time < $in_duration") )); then
		input_settings+=("-t" "$out_duration")
	fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Adjust map settings
get_map_settings() {
	map_settings="-map 0:v"
	if [[ $use_audio = true ]]; then
		map_settings="${map_settings} -map 0:a?"
	fi
	if [[ $use_subs = true ]]; then
		map_settings="${map_settings} -map 0:s?"
	fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Adjust subtitle settings
get_sub_settings() {
	if [[ $image_subs = false ]]; then 
		sub_settings="-c:s webvtt"
	else
		sub_settings="-c:s copy"
	fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Adjust libvorbis/libopus settings
get_audio_settings() {
	audio_factor=$(bc <<< "$size_limit*8*1000/($out_duration*5.5*32)")
	if (( audio_factor < 1 )); then
		audio_bitrate=48
	elif (( audio_factor >= 1 && audio_factor < 2 )); then
		audio_bitrate=64
	elif (( audio_factor >= 2 && audio_factor < 7 )); then
		audio_bitrate=96
	elif (( audio_factor >= 7 && audio_factor < 14 )); then
		audio_bitrate=128
	elif (( audio_bitrate >= 14 && audio_factor < 30 )); then
		audio_bitrate=160
	else
		audio_bitrate=192
	fi
	
	# Ensure that HQ mode gets a higher minimum audio bitrate
	if (( audio_bitrate < min_audio_bitrate )); then 
		audio_bitrate=$min_audio_bitrate
	fi
	audio_settings="-c:a libvorbis -ac 2 -b:a ${audio_bitrate}K"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Adjust libvpx settings
get_video_settings() {
	video_bitrate=$(bc <<< "$size_limit*8*1000/$out_duration-$audio_bitrate")
	video_settings="-c:v libvpx -b:v ${video_bitrate}K"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Assemble filter string
get_filter_settings() {
	filter_settings="-filter_complex $user_filter"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ffmpeg commands
convert() {
	mkdir webm_done 2> /dev/null
	
	if [[ $image_subs = true && $mkv_fallback = true ]]; then ext="mkv"; else ext="webm"; fi

	echo "First pass:"
	ffmpeg -loglevel quiet -stats "${input_settings[@]}" $map_settings \
		$video_settings -deadline good -cpu-used 5 $audio_settings \
		$sub_settings $filter_settings -pass 1 -f null -
	echo "~~~~~~~~~~~~~~~~~~"
	echo "Second pass:"
	ffmpeg -y -loglevel quiet -stats "${input_settings[@]}" $map_settings \
		$video_settings -deadline good -cpu-used 0 $audio_settings \
		$sub_settings $filter_settings -pass 2 "webm_done/${input%.*}.$ext"
	echo "~~~~~~~~~~~~~~~~~~"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Conversion if the input is a video
video_conversion() {
	if [[ ! -e "$input" ]]; then echo "No file $input found. Skipping..."; return; fi
	get_video_info
	if [[ $use_subs = true ]]; then get_sub_info; get_sub_settings; fi
	get_input_settings
	get_map_settings
	if [[ -n $user_filter ]]; then get_filter_settings; fi
	if [[ $use_audio = true ]]; then get_audio_settings; fi
	get_video_settings
	
	if [[ $image_subs = true && $mkv_fallback = false ]]; then return; 
	elif [[ $wrong_trim = true ]]; then return; fi
	convert
	echo "Final size: $(bc <<< "scale=2; $(stat -c %s "webm_done/${input%.*}.$ext")/1024/1024") MiB"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Generate error log
document_errors() {
	if [[ $image_subs = true && $mkv_fallback = false ]]; then
		{
		echo -e "Error occured for:\n$input"
		echo -e "\n\tImage-based subtitles detected."
		echo -e "\tPlease provide text-based subtitles or use --mkv-fallback\n"
		} >> webm.log
	fi
	
	if [[ $wrong_trim = true ]]; then
		{
		echo -e "Error occured for:\n$input"
		echo -e "\n\tWrong trim settings were specified."
		echo -e "\tPossible causes:"
		echo -e "\t a) Start or end time less than zero"
		echo -e "\t b) Start or end time greater than the input duration"
		echo -e "\t c) Start time greater than end time"
		} >> webm.log
	fi
	
	image_subs=false
	wrong_trim=false
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main script
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Parse input flags/files
while [[ "$1" ]]
do
	case "$1" in
	-h | --help) show_help; exit;;
	-t | --trim) use_trim=true; shift;;
	-a | --audio) use_audio=true; shift;;
	-s | --size) size_limit=$2; shift 2;;
	-f | --filter) user_filter=$2; shift 2;;
	--start) start_time_all=$2; shift 2;;
	--end) end_time_all=$2; shift 2;;
	--subtitles) use_subs=true; shift;;
	--min-audio) min_audio_bitrate=$2; shift 2;;
	--mkv-fallback) mkv_fallback=true; shift;;
	-*) echo "Unknown flag '${1}' used!"; exit;;
	*) file_list+=("$1"); shift;; 
	esac
done

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Check user input for validity
for option in "start" "end"
do
	var="${option}_time_all"
	case "${!var}" in
		*[!0-9]?[!0-9]*) echo "--$option must be a positive number. Aborting..."; exit;;
	esac
done

if (( start_time_all < 0 )); then
	echo "--start can't be less than zero. Aborting..."
	exit
elif [[ ( -n $start_time_all && -n $end_time_all ) && $end_time_all -le start_time_all ]]; then
	echo "--end can't be equal or less than --start. Aborting..."
	exit
elif [[ $use_trim = true && ( -n $start_time_all || -n $end_time_all ) ]]; then
	echo "--trim and --start/--end are mutually exclusive. Aborting..."
	exit
fi

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~



for input in "${file_list[@]}"
do
	echo "~~~~~~~~~~~~~~~~~~"
	echo "Current file: $input"
	echo "~~~~~~~~~~~~~~~~~~"
	video_conversion
	document_errors
	rm ffmpeg2pass-0.log 2> /dev/null
done

# Show user that errors occured
if [[ -e webm.log ]]; then
	echo -e "\nError(s) occured while running this script."
	echo -e "Please check webm.log for more information.\n"
fi
