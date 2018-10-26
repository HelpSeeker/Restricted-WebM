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
# -) Subtitle support
# -) Handle image-based subtitles
#		-> throw error
# -) Advanced audio stream selection
#		-> count streams, adjust bitrate calculation
# -) Advanced audio options
#		-> stream copying, adjust bitrate based on channel count
# -) VP9 / Opus support
# -) Single pass
# -) Improve libvpx commands
# -) Multithreading
# -) Include filename in the metadata


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Settings
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Default values
size_limit=3

audio_bitrate=0
audio_settings="-an"
min_audio_bitrate=64

# Default behaviour
use_trim=false
use_audio=false
use_subtitles=false

# Initializing variables (don't touch)
file_list=()

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
	echo -e " -t, --trim\t\ttrim input videos"
	echo -e " -a, --audio\t\tuse input audio (if present)"
	echo -e " -s, --size <limit>\tspecify file size limit in MiB (default: 3)"
	echo -e " --subtitles\t\tuse input subtitles (if present)"
	echo -e " --min-audio <bitrate>\tspecify min. audio bitrate in Kbps (default: 64)"
	echo -e ""
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

get_info() {
	in_duration=$(ffprobe -v error -show_entries format=duration \
					-of default=noprint_wrappers=1:nokey=1 "$input")
	out_duration=$in_duration
}

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
	
	out_duration=$(bc <<< "scale=3; $end_time-$start_time")
	trim_settings="-ss $start_time -to $end_time"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

get_map_settings() {
	map_settings="-map 0:v"
	if [[ $use_audio = true ]]; then
		map_settings="${map_settings} -map 0:a?"
	elif [[ $use_subtitles = true ]]; then
		map_settings="${map_settings} -map 0:s?"
	fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

get_video_settings() {
	video_bitrate=$(bc <<< "$size_limit*8*1000/$out_duration-$audio_bitrate")
	video_settings="-c:v libvpx -b:v ${video_bitrate}K"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

convert() {
	echo "First pass:"
	ffmpeg -loglevel quiet -stats $trim_settings -i "$input" $map_settings \
		$video_settings -deadline good -cpu-used 5 $audio_settings -pass 1 -f null -
	echo "~~~~~~~~~~~~~~~~~~"
	echo "Second pass:"
	ffmpeg -y -loglevel quiet -stats $trim_settings -i "$input" $map_settings \
		$video_settings -deadline good -cpu-used 0 $audio_settings -pass 2 "webm_done/${input%.*}.webm"
	echo "~~~~~~~~~~~~~~~~~~"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main script
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

while [[ "$1" ]]
do
	case "$1" in
	-h | --help) show_help; exit;;
	-t | --trim) use_trim=true; shift;;
	-a | --audio) use_audio=true; shift;;
	-s | --size) size_limit=$2; shift 2;;
	--subtitles) echo "Subtitle support isn't implemented yet."; exit;;
	--min-audio) min_audio_bitrate=$2; shift 2;;
	-*) echo "Unknown flag '${1}' used!"; exit;;
	*) file_list+=("$1"); shift;; 
	esac
done

mkdir webm_done 2> /dev/null
#mkdir webm_temp || { echo "Can't create webm_temp directory! Aborting..."; exit; }

echo "~~~~~~~~~~~~~~~~~~"

for input in "${file_list[@]}"
do
	echo "Current file: $input"
	echo "~~~~~~~~~~~~~~~~~~"
	get_info
	if [[ $use_trim = true ]]; then get_trim_settings; fi
	get_map_settings
	if [[ $use_audio = true ]]; then get_audio_settings; fi
	get_video_settings
	convert
	echo "Final size: $(bc <<< "scale=2; $(stat -c %s "webm_done/${input%.*}.webm")/1024/1024") MiB"
	echo "~~~~~~~~~~~~~~~~~~"
	echo "~~~~~~~~~~~~~~~~~~"
	rm ffmpeg2pass-0.log 2> /dev/null
done
