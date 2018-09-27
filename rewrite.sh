#!/bin/bash

# WORK IN PROGRESS
# Complete rewrite of convert.sh
# Goals:
# -) Improved readability
# -) Support for multiple audio streams
# -) Support for subtitles
# -) Basic analysis of applied filters (video filters? audio filters?)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Settings
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

file_size_limit=3

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

get_info() {
	length=$(ffprobe -v error -show_entries format=duration \
					-of default=noprint_wrappers=1:nokey=1 "$input")
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Get start/end time for trimming
get_trim_settings() {
	# Prompt user to specify start/end time (in seconds)
	echo "~~~~~~~~~~~~~~~~~~"
	echo "Current file: $input"
	echo "~~~~~~~~~~~~~~~~~~"
	echo "Please specify where to start encoding (in seconds). Leave empty to start at the beginning of the input video."
	read -r start_time
	echo "~~~~~~~~~~~~~~~~~~"
	echo "Now please specify where to stop encoding (in seconds). Leave empty to stop at the end of the input video."
	read -r end_time
	echo "~~~~~~~~~~~~~~~~~~"
	
	# If no input, set start time to 0 and/or end time to video length
	[[ -z $start_time ]] && start_time=0
	[[ -z $end_time ]] && end_time=$length
	
	duration=$(bc <<< "scale=3; $end_time-$start_time")
	trim_settings="-ss $start_time -to $end_time"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

get_map_settings() {
	map_settings="-map 0:v -map 0:a? -map 0:s?"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

get_audio_settings() {
	audio_bitrate=96
	audio_settings="-c:a libvorbis -b:a ${audio_bitrate}"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

get_video_settings() {
	video_bitrate=$(bc <<< "$file_size_limit*8*1000/$length")
	video_settings="-c:v libvpx -b:v ${video_bitrate}K -deadline good -cpu-used 0"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

convert() {
	ffmpeg $trim_settings -i "$input" $map_settings \
		$video_settings $audio_settings"../done/${input%.*}.webm"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main script
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cd to_convert/ 2> /dev/null || { echo "No directory to_convert present!"; exit; }

mkdir ../done

for input in *
do
	get_info
	get_trim_settings
	get_map_settings
	get_audio_settings
	get_video_settings
	convert
done
