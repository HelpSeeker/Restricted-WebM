#!/bin/bash

###################
###### Functions ######
###################

# Defines help text
usage () {
	echo -e "Usage: $0 [-h] [-t] [-a] [-n] [-s file_size_limit] [-u undershoot_limit] [-f filters]"
	echo -e "\\t-h: Show Help"
	echo -e "\\t-t: Enable trim mode. Lets you specify which part of the input video(s) to encode"
	echo -e "\\t-a: Enables audio encoding. Bitrate gets chosen automatically."
	echo -e "\\t-n: Use the newer codecs VP9/Opus instead of VP8/Vorbis. Will lead to even longer encoding times, but offers a better quality (especially at low bitrates). Also note that 4chan doesn't support VP9/Opus webms."
	echo -e "\\t-s file_size_limit: Specifies the file size limit in MB. Default value is 3."
	echo -e "\\t\\t4chan limits:"
	echo -e "\\t\\t\\t/gif/ and /wsg/: 4MB - audio allowed - max. 300 seconds"
	echo -e "\\t\\t\\tall other boards: 3MB - no audio allowed - max. 120 seconds"
	echo -e "\\t\\t8chan limits:"
	echo -e "\\t\\t\\tall boards: 8MB - audio allowed"
	echo -e "\\t-u undershoot_limit: Define what percentage of the file size limit must be utilized. Default value: 0.75 (75%). Very high values may lead to worse results (since the script has to fall back on its last video encoding setting)"
	echo -e "\\t-f filters: Add filters that you want to apply (with settings). Be careful to type them as you would normally with ffmpeg. Refer to ffmpeg's documentation for further information"
}

# Looks for certain substrings $2 within a string $1
# Succeeds if substring is found within the string (e.i. it contains the substring)
contains () {
	case "$1" in 
		*"$2"*) return 0;;
		*) return 1;;
	esac
}

# Uses ffprobe to get video properties for later calculations
info () {
	length=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1")
	frame_rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$1")
	video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$1")
	video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$1")
	aspect_ratio=$(bc <<< "scale=3; $video_width/$video_height")
}

# Asks user where to start and end each video and use it to calculate the video's duration
trim () {
	echo "Current file: $1"
	echo "Please specify where to start encoding (in seconds):"
	read -r start_time
	echo "Now please specify where to stop encoding (in seconds):"
	read -r end_time
	duration=$(bc <<< "scale=3; $end_time-$start_time")
}

# Defines audio codec and properties
# Audio bitrate function/assignment is the result of trying to match my experience with 4MB webms
audio () {
	audio_factor=$(bc <<< "$file_size*8*1000/($duration*4.5*32)")
	if [[ $audio_factor -le 1 ]]; then audio_channels=1; else audio_channels=2; fi
	if [[ $audio_factor -le 1 ]]; then
		audio_bitrate=32
	elif [[ $audio_factor -eq 2 ]]; then
		audio_bitrate=64
	elif [[ $audio_factor -gt 2 && $audio_factor -le 6 ]]; then
		audio_bitrate=96
	else
		audio_bitrate=128
	fi
	if [[ "$new_codecs" = true ]]; then
		audio_settings="-c:a libopus -ac $audio_channels -ar 48000 -b:a ${audio_bitrate}K"
		# -ar 48000, because Opus only allows certain sampling rates (48000, 24000, 16000, 12000, 8000)
	else
		audio_settings="-c:a libvorbis -ac $audio_channels -ar 44100 -b:a ${audio_bitrate}K"
	fi
}

# Calculates important values for the encoding process
calc () {
	video_bitrate=$(bc <<< "($file_size*8*1000/$duration-$audio_bitrate+0.5)/1")
	(( bufsize = $video_bitrate*5 ))
	bpp=$(bc <<< "scale=3; $video_bitrate*1000/($video_height*$video_width*$frame_rate)")
}

# Reduces output height (width is later adjusted via aspect ratio) to reach certain bits per pixel value; min. output height is 360p
downscale () {
	new_video_height=$video_height
	new_bpp=$bpp
	while [[ $(bc <<< "$new_bpp < 0.04") -eq 1 && $new_video_height -gt 360 ]]; do
		(( new_video_height -= 10 ))
		new_bpp=$(bc <<< "scale=3; $1*1000/($new_video_height*$new_video_height*$aspect_ratio*$frame_rate)")
		scaling_factor="-vf scale=-1:$new_video_height"
	done
}

# Reduces framerate if bpp value is too low and the input video has a framerate above 24 fps
# frame_settings introduced in case of further adjustments regarding keyframe intervals
framedrop () {
	if [[ $(bc <<< "$new_bpp < 0.04") -eq 1 && $(bc <<< "$frame_rate > 24") -eq 1 ]]; then
		new_frame_rate=24
		frame_settings="-r $new_frame_rate"
	fi
}

# Defines which video codec and bitrate mode to use
video () {
	if [[ "$new_codecs" = true ]]; then video_codec="libvpx-vp9"; else video_codec="libvpx"; fi
	# modes=( "variable" "low-variable" "constant" "skip_threshold")
	case $1 in
		1) video_settings="-c:v $video_codec -crf 10 -qmax 50 -b:v ${video_bitrate}K";;
		2) video_settings="-c:v $video_codec -crf 10 -qmax 50 -b:v ${new_video_bitrate}K";;
		3) video_settings="-c:v $video_codec -crf 10 -b:v ${video_bitrate}K";;	
		4) video_settings="-c:v $video_codec -crf 10 -b:v ${new_video_bitrate}K";;	
		5) video_settings="-c:v $video_codec -minrate:v ${video_bitrate}K -maxrate:v ${video_bitrate}K -b:v ${video_bitrate}K";;
		6) video_settings="-c:v $video_codec -minrate:v ${new_video_bitrate}K -maxrate:v ${new_video_bitrate}K -b:v ${new_video_bitrate}K";;
		7) video_settings="-c:v $video_codec -bufsize $bufsize -minrate:v ${video_bitrate}K -maxrate:v ${video_bitrate}K -b:v ${video_bitrate}K -skip_threshold 100";;
		*) { echo "File still doesn't fit the specified limit. Please use ffmpeg manually." && rm "../done/${input%.*}.webm" && echo "$input" >> ../too_large.txt; };;
	esac
}

# The actual ffmpeg conversion commands
convert () {
	if [[ $(bc <<< "$new_bpp >= 0.075") -eq 1 ]]; then
		ffmpeg -y -ss $start_time -i "$1" -t $duration $frame_settings $video_settings -slices 8 -threads 1 -deadline good -cpu-used 5 $audio_settings -pass 1 -f webm /dev/null
		ffmpeg -y -ss $start_time -i "$1" -t $duration $frame_settings $video_settings -slices 8 -threads 1 -metadata title="${1%.*}" -auto-alt-ref 1 -lag-in-frames 16 -deadline good -cpu-used 0 $scaling_factor $filter_settings $audio_settings -pass 2 "../done/${1%.*}.webm"
		rm ffmpeg2pass-0.log
	else
		ffmpeg -y -ss $start_time -i "$1" -t $duration $frame_settings $video_settings -slices 8 -threads 1 -metadata title="${1%.*}" -lag-in-frames 16 -deadline good -cpu-used 0 $scaling_factor $filter_settings $audio_settings "../done/${1%.*}.webm"
	fi
}

# Function to summarize the first encoding cycle.
initial_encode () {
	contains "$filter_settings" "scale" || downscale "$video_bitrate"
	framedrop
	video 1
	convert "$1"
}

# Loops through the different video settings if the webm is too large/small
# Every setting can be done twice: Once with the original calculated and once with an adjusted bitrate
limiter () {
	#echo "Debug mode: Enter webm size."
	#read -r webm_size
	webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${1%.*}.webm")
	counter=1
	while [[ $webm_size -gt $(bc <<< "($file_size*1024*1024+0.5)/1") || $webm_size -lt $(bc <<< "($file_size*1024*1024*$undershoot_limit+0.5)/1") ]]; do
		(( counter += 1 ))
		new_video_bitrate=$(bc <<< "($video_bitrate*$file_size*1024*1024/$webm_size+0.5)/1")
		contains "$filter_settings" "scale" || if [[ $(($counter%2)) -eq 0 ]]; then downscale "$new_video_bitrate"; else downscale "$video_bitrate"; fi
		framedrop
		video "$counter"
		if [[ "$counter" -le 7 ]]; then 
			convert "$1" 
			#echo "Debug mode: Enter webm size."
			#read -r webm_size
			webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${1%.*}.webm")
		else
			break
		fi
	done
}

####################
###### Main script ######
####################

# Read input parameters and assigns values accordingly
while getopts ":htans:u:f:" ARG; do
	case "$ARG" in
	h) usage && exit;;
	t) trim_mode=true;;
	a) audio_mode=true;;
	n) new_codecs=true;;
	s) file_size="$OPTARG";;
	u) undershoot_limit="$OPTARG";;
	f) filter_settings="-filter_complex $OPTARG";;
	*) echo "Unknown flag used. Use $0 -h to show all available options." && exit;;
	esac;
done

# Set default values for unspecified parameters
[[ -z $trim_mode ]] && trim_mode=false
[[ -z $audio_mode ]] && audio_mode=false
[[ -z $new_codecs ]] && new_codecs=false
[[ -z $file_size ]] && file_size=3
[[ -z $undershoot_limit ]] && undershoot_limit=0.75

# Change into sub-directory to avoid file conflicts when converting webms
cd to_convert 2> /dev/null || { echo "No to_convert folder present" && exit; }
# Make sure there are any files in to_convert/
# Used another for-loop, since wildcard matching doesn't work with test alone
for file in *; do [[ -e "$file" ]] || { echo "No files present in to_convert" && exit; }; break; done
# Create sub-directory for the finished webms
mkdir ../done 2> /dev/null

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
	initial_encode "$input"
	limiter "$input"
	
	# Print various variables for debugging purposes
	#~ echo "Duration: $duration"
	#~ echo "Height: $video_height"
	#~ echo "Width: $video_width"
	#~ echo "Audio bitrate: $audio_bitrate"
	#~ echo "Video bitrate: $video_bitrate"
	#~ echo "Buffer size: $bufsize"
	#~ echo "Bits per pixel: $bpp"
	#~ echo "2-pass mode is active: $two_pass"
	#~ echo "Aspect ratio: $aspect_ratio"
	#~ echo "Framerate: $frame_rate"
	#~ echo "Audio factor: $audio_factor"
	#~ echo "Channels: $audio_channels"
); done