#!/bin/bash

###################
###### Functions ######
###################

# Define help text
usage () {
	echo -e "Usage: $0 [-h] [-t] [-a] [-p] [-s file_size_limit] [-f filters]"
	echo -e "\\t-h: Show Help"
	echo -e "\\t-t: Enable trim mode. Lets you specify which part of the input video(s) to encode"
	echo -e "\\t-a: Enables audio encoding"
	echo -e "\\t-p: Enables VP8's 2-pass encoding. Only recommended for high bitrates (e.i. short webms)"
	echo -e "\\t-s file_size_limit: Specifies the file size limit in MB. Default value is 3."
	echo -e "\\t\\t4chan limits:"
	echo -e "\\t\\t\\t/gif/ and /wsg/: 4MB - audio allowed - max. 300 seconds"
	echo -e "\\t\\t\\tall other boards: 3MB - no audio allowed - max. 120 seconds"
	echo -e "\\t\\t8chan limits:"
	echo -e "\\t\\t\\tall boards: 8MB - audio allowed"
	echo -e "\\t-f filters: Add filters that you want to apply (with settings). DO NOT USE SCALING AS IT'S APPLIED AUTOMATICALLY RIGHT NOW! Also be careful to type them as you would normally with ffmpeg. Refer to ffmpeg's documentation for further information."
}

# Use ffprobe to get video properties for later calculations
info () {
	length=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1")
	frame_rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$1")
	video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$1")
	video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$1")
	aspect_ratio=$(bc <<< "scale=3; $video_width/$video_height")
}

# Trim function when flag is accordingly set
trim () {
	echo "Current file: $1"
	echo "Please specify where to start encoding (in seconds):"
	read -r start_time
	echo "Now please specify where to stop encoding (in seconds):"
	read -r end_time
	duration=$(bc <<< "scale=3; $end_time-$start_time")
}

# Audio function when flag is accordingly set
audio () {
	audio_bitrate=96
	audio_settings="-c:a libvorbis -ac 2 -ar 44100 -b:a ${audio_bitrate}K"
}

# Function to calculate important values for the encoding process (mainly bitrate)
calc () {
	video_bitrate=$(bc <<< "($file_size*8*1000/$duration-$audio_bitrate+0.5)/1")
	(( bufsize = $video_bitrate*5 ))
	bpp=$(bc <<< "scale=3; $video_bitrate*1000/($video_height*$video_width*$frame_rate)")
}

# Automatic downscale function
downscale () {
	while [[ $(bc <<< "$bpp < 0.03") -eq 1 && $video_height -gt 360 ]]; do
		(( video_height -= 10 ))
		bpp=$(bc <<< "scale=3; $video_bitrate*1000/($video_height*$video_height*$aspect_ratio*$frame_rate)")
		scaling_factor="-vf scale=-1:$video_height"
	done
}

# Bitrade mode function based on which mode was chosen by the user. Defaults to variable.
mode () {
	# modes=( "variable" "low-variable" "constant" "skip_threshold")
	case $1 in
		1) video_settings="-crf 10 -qmax 50 -b:v ${video_bitrate}K";;
		2) video_settings="-crf 10 -b:v ${video_bitrate}K";;		
		3) video_settings="-minrate:v ${video_bitrate}K -maxrate:v ${video_bitrate}K -b:v ${video_bitrate}K";;
		4) video_settings="-minrate:v ${video_bitrate}K -maxrate:v ${video_bitrate}K -b:v ${video_bitrate}K -skip_threshold 100";;
		*) echo "File still doesn't fit the specified limit. Please use ffmpeg manually.";;
	esac
}

# Function for the actual conversion via ffmpeg
convert () {
	if [[ "$two_pass" = true ]]; then
		ffmpeg -y -ss $start_time -i "$1" -t $duration -c:v libvpx -slices 8 -threads 1 $video_settings -deadline good -cpu-used 5 $audio_settings -pass 1 -f webm /dev/null
		ffmpeg -y -ss $start_time -i "$1" -t $duration -c:v libvpx -slices 8 -threads 1 -metadata title="${1%.*}" -auto-alt-ref 1 -lag-in-frames 16 -bufsize $bufsize $video_settings -deadline best -cpu-used 0 $scaling_factor $filter_settings $audio_settings -pass 2 "../done/${1%.*}.webm"
		rm ffmpeg2pass-0.log
	else
		ffmpeg -y -ss $start_time -i "$1" -t $duration -c:v libvpx -slices 8 -threads 1 -metadata title="${1%.*}" -lag-in-frames 16 -bufsize $bufsize $video_settings -deadline best -cpu-used 0 $scaling_factor $filter_settings $audio_settings "../done/${1%.*}.webm"
	fi
}

# Function to swap bitrate mode if result is still over the file size limit
limiter () {
	webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${1%.*}.webm")
	counter=1
	while [[ $webm_size -gt $(bc <<< "($file_size*1024*1024+0.5)/1") ]]; do
		(( counter += 1 ))
		mode $counter
		if [[ "$counter" -lt 5 ]]; then 
			convert "$1" 
			webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${1%.*}.webm")
		else
			webm_size=0
		fi
	done
}

####################
###### Main script ######
####################

# Create sub-directory for the finished webms
mkdir done

# Change into sub-directory to avoid file conflicts when converting webms
cd to_convert || exit
 
# Reads input parameters and assigns values accordingly
while getopts ":htaps:f:" ARG; do
	case "$ARG" in
	h) usage && exit;;
	t) trim_mode=true;;
	a) audio_mode=true;;
	p) two_pass=true;;
	s) file_size=$OPTARG;;
	f) filter_settings="-filter_complex $OPTARG";;
	*) echo "Unknown flag used. Enter sh $0 -h to show all available options." && exit;;
	esac;
done

# Set default values for unspecified parameters
[[ -z $trim_mode ]] && trim_mode=false
[[ -z $audio_mode ]] && audio_mode=false
[[ -z $two_pass ]] && two_pass=false
[[ -z $file_size ]] && file_size=3

# The main conversion loop
for input in *; do (
	info "$input"
	
	# Set default conversion variables
	# Might get overwritten based on set flags
	start_time=0
	duration=$length
	audio_bitrate=0
	audio_settings="-an"

	if [[ "$trim_mode" = true ]]; then trim "$input"; fi
	if [[ "$audio_mode" = true ]]; then audio; fi
	calc
	downscale
	mode 1
	convert "$input"
	limiter "$input"

	# Print various variables for debugging purposes
	#~ echo "Duration: $duration"
	#~ echo "Frame rate: $frame_rate"
	#~ echo "Height: $video_height"
	#~ echo "Width: $video_width"
	#~ echo "Audio bitrate: $audio_bitrate"
	#~ echo "Video bitrate: $video_bitrate"
	#~ echo "Buffer size: $bufsize"
	#~ echo "Bits per pixel: $bpp"
	#~ echo "Aspect ratio: $aspect_ratio"
); done