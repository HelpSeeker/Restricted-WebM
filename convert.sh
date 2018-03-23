#!/bin/bash

# Change into sub-directory to avoid file conflicts when converting webms
cd to_convert || exit

# Define help text
usage () {
echo -e "Usage: sh $0 [-h] [-t] [-a] [-p] [-m { variable | constant | low-variable }] [-s file_size_limit] [-f filters]"
echo -e "\t-h: Show Help"
echo -e "\t-t: Enable trim mode. Lets you specify which part of the input video(s) to encode"
echo -e "\t-a: Enables audio encoding"
echo -e "\t-p: Enables VP8's 2-pass encoding. Only recommended for high bitrates (e.i. short webms)"
echo -e "\t-m { variable | constant | low-variable }: Specifies which bitrate mode VP8 should use"
echo -e "\t\tvariable (default): Usually provides the best quality/size ratio. Works with target/minimum crf and bitrate value."
echo -e "\t\tconstant: Easiest way to reach a certain file size. Specifies an average target bitrate."
echo -e "\t\tlow-variable: Same as the \"variable\" mode, but doesn't apply a minimum crf value. Useful for low-quality webms."
echo -e "\t-s file_size_limit: Specifies the file size limit in MB. Default value is 3."
echo -e "\t\t4chan limits:"
echo -e "\t\t\t/gif/ and /wsg/: 4MB - audio allowed - max. 300 seconds"
echo -e "\t\t\tall other boards: 3MB - no audio allowed - max. 120 seconds"
echo -e "\t\t8chan limits:"
echo -e "\t\t\tall boards: 8MB - audio allowed"
echo -e "\t-f filters: Add filters that you want to apply (with settings). Be careful to type them as you would normally with ffmpeg. Refer to ffmpeg's documentation for further information."
}
 
# Reads input parameters and assigns values accordingly
while getopts ":htapm:s:f:" ARG;
do case "$ARG" in
h) usage && exit;;
t) trim_mode=true;;
a) audio_mode=true;;
p) two_pass=true;;
m) bitrate_mode="$OPTARG";;
s) file_size=$OPTARG;;
f) filter_settings="-filter_complex $OPTARG";;
\?) echo "Unknown flag used. Enter sh $0 -h to show all available options." && exit;;
esac;
done

# Set default values for unspecified parameters
[[ -z $trim_mode ]] && trim_mode=false
[[ -z $audio_mode ]] && audio_mode=false
[[ -z $two_pass ]] && two_pass=false
[[ -z $bitrate_mode ]] && bitrate_mode="variable"
[[ -z $file_size ]] && file_size=3

# The main conversion loop
for input in *; do (
	
	# Use ffprobe to get video properties for later calculations
	length=$(ffprobe -v error -select_streams v:0 -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input")
	frame_rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$input")
	
	# Trim settings
	if [[ "$trim_mode" = true ]]; then
		echo "Current file: $input"
		echo "Please specify where to start encoding (in seconds):"
		read start_time
		echo "Now please specify where to stop encoding (in seconds):"
		read end_time
		duration=$(echo $end_time-$start_time | bc)
	else
		start_time=0
		duration=$length
	fi
	
	# Audio settings
	if [[ "$audio_mode" = true ]]; then 
		audio_bitrate=96
		audio_settings="-c:a libvorbis -ac 2 -ar 44100 -b:a "$audio_bitrate"K"
	else
		audio_bitrate=0
		audio_settings="-an"
	fi
	
	# Calculate bitrate and buffer size
	video_bitrate=$(echo $file_size*8*1000/$duration-$audio_bitrate | bc)
	bufsize=$(echo $video_bitrate*5 | bc)

	# Video settings
	if [[ "$bitrate_mode" = "variable" ]]; then
		video_settings="-crf 10 -qmax 50 -b:v "$video_bitrate"K"
	elif [[ "$bitrate_mode" = "constant" ]]; then
		video_settings="-minrate:v "$video_bitrate"K -maxrate:v "$video_bitrate"K -b:v "$video_bitrate"K"
	elif [[ "$bitrate_mode" = "low-variable" ]]; then
		video_settings="-crf 10 -b:v "$video_bitrate"K"
	else
		echo "Unknown bitrate mode!"
		exit
	fi

	# Use ffmpeg to convert to webm
	if [[ "$two_pass" = true ]]; then
		ffmpeg -y -ss $start_time -i "$input" -t $duration -c:v libvpx -slices 8 -threads 1 $video_settings -deadline good -cpu-used 5 $audio_settings -pass 1 -f webm /dev/null
		ffmpeg -y -ss $start_time -i "$input" -t $duration -c:v libvpx -slices 8 -threads 1 -metadata title="${input%.*}" -auto-alt-ref 1 -lag-in-frames 16 -bufsize $bufsize $video_settings -deadline best -cpu-used 0 $filter_settings $audio_settings -pass 2 "../${input%.*}.webm"
		rm ffmpeg2pass-0.log
	else
		ffmpeg -y -ss $start_time -i "$input" -t $duration -c:v libvpx -slices 8 -threads 1 -metadata title="${input%.*}" -lag-in-frames 16 -bufsize $bufsize $video_settings -deadline best -cpu-used 0 $filter_settings $audio_settings "../${input%.*}.webm"
	fi
	
); done