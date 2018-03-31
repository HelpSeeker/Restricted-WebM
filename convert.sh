#!/bin/bash

###################
# Functions
###################

# Defines help text
usage () {
	echo -e "Usage: $0 [-h] [-t] [-a] [-q] [-n] [-s file_size_limit] [-u undershoot_limit] [-f filters]"
	echo -e "\\t-h: Show Help"
	echo -e "\\t-t: Enable trim mode. Lets you specify which part of the input video(s) to encode"
	echo -e "\\t-a: Enable audio encoding. Bitrate gets chosen automatically."
	echo -e "\\t-q: Enable HQ (high quality) mode. The script tries to raise the bpp value high enough to use 2-pass encoding. Audio bitrate fixed at 96kbps. Doesn't work if you manually use the scale filter."
	echo -e "\\t-n: Use the newer codecs VP9/Opus instead of VP8/Vorbis. Will lead to even longer encoding times, but offers a better quality (especially at low bitrates). Also note that 4chan doesn't support VP9/Opus webms."
	echo -e "\\t-s file_size_limit: Specify the file size limit in MB. Default value is 3."
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
	echo "Please specify where to start encoding (in seconds). Leave empty to start at the beginning of the input video."
	read -r start_time
	[[ -z $start_time ]] && start_time=0
	echo "Now please specify where to stop encoding (in seconds). Leave empty to stop at the end of the input video."
	read -r end_time
	[[ -z $end_time ]] && end_time=$length
	duration=$(bc <<< "scale=3; $end_time-$start_time")
}

# Defines audio codec and properties
# Audio bitrate function/assignment is the result of trying to match my experience with 4MB webms
audio () {
	if [[ "$hq_mode" = true ]]; then
		audio_bitrate=96
		audio_channels=2
	else
		audio_factor=$(bc <<< "$file_size*8*1000/($duration*5.5*32)")
		if [[ $audio_factor -eq 0 ]]; then audio_channels=1; else audio_channels=2; fi
		case $audio_factor in
			0) audio_bitrate=48;;
			1) audio_bitrate=64;;
			2 | 3 | 4 | 5 | 6) audio_bitrate=96;;
			*) audio_bitrate=128;;
		esac
		if [[ $audio_factor -le 1 ]]; then audio_channels=1; else audio_channels=2; fi
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
	while [[ $(bc <<< "$new_bpp < $bcc_threshold") -eq 1 && $new_video_height -gt $height_threshold ]]; do
		(( new_video_height -= 10 ))
		new_bpp=$(bc <<< "scale=3; $1*1000/($new_video_height*$new_video_height*$aspect_ratio*$frame_rate)")
		scaling_factor="scale=-1:$new_video_height"
	done
}

# Reduces framerate if bpp value is too low and the input video has a framerate above 24 fps
# frame_settings introduced in case of further adjustments regarding keyframe intervals
framedrop () {
	if [[ $(bc <<< "$new_bpp < $bcc_threshold") -eq 1 && $(bc <<< "$frame_rate > 24") -gt 1 ]]; then
		new_frame_rate=24
		frame_settings="-r $new_frame_rate"
	fi
}

# Defines which video codec and bitrate mode to use
video () {
	if [[ "$new_codecs" = true ]]; then video_codec="libvpx-vp9"; else video_codec="libvpx"; fi
	case $1 in
		0) video_settings="-c:v $video_codec -crf 10 -qmax 50 -b:v ${video_bitrate}K";;
		1 | 2) video_settings="-c:v $video_codec -crf 10 -qmax 50 -b:v ${new_video_bitrate}K";;
		3) video_settings="-c:v $video_codec -crf 10 -b:v ${video_bitrate}K";;	
		4 | 5) video_settings="-c:v $video_codec -crf 10 -b:v ${new_video_bitrate}K";;	
		6) video_settings="-c:v $video_codec -minrate:v ${video_bitrate}K -maxrate:v ${video_bitrate}K -b:v ${video_bitrate}K";;
		7 | 8) video_settings="-c:v $video_codec -minrate:v ${new_video_bitrate}K -maxrate:v ${new_video_bitrate}K -b:v ${new_video_bitrate}K";;
		# 9) video_settings="-c:v $video_codec -bufsize $bufsize -minrate:v ${video_bitrate}K -maxrate:v ${video_bitrate}K -b:v ${video_bitrate}K -skip_threshold 100";;
		b) { echo "File can't be fit in the specified file size/undershoot limit. Please use ffmpeg manually." && rm "../done/${input%.*}.webm" && echo "$input" >> ../too_small_for_undershoot.txt; };;
		*) { echo "File still doesn't fit the specified limit. Please use ffmpeg manually." && rm "../done/${input%.*}.webm" && echo "$input" >> ../too_large.txt; };;
	esac
}

# The actual ffmpeg conversion commands
convert () {
	if [[ -n $scaling_factor && -n $filter_settings ]]; then
		filter="-filter_complex "
		filter="${filter}$filter_settings,"
		filter="${filter}$scaling_factor"
	elif [[ -z $scaling_factor && -z $filter_settings ]]; then
		filter=""
	else
		filter="-filter_complex "
		filter="${filter}$filter_settings"
		filter="${filter}$scaling_factor"
	fi

	if [[ $(bc <<< "$new_bpp >= 0.075") -eq 1 ]]; then
		echo -e "\\n\\n\\n"
		ffmpeg -y -hide_banner -ss $start_time -i "$1" -t $duration $frame_settings $video_settings -slices 8 -threads 1 -deadline good -cpu-used 5 $audio_settings -pass 1 -f webm /dev/null
		echo -e "\\n\\n\\n"
		ffmpeg -y -hide_banner -ss $start_time -i "$1" -t $duration $frame_settings $video_settings -slices 8 -threads 1 -metadata title="${1%.*}" -auto-alt-ref 1 -lag-in-frames 16 -deadline good -cpu-used 0 $filter $audio_settings -pass 2 "../done/${1%.*}.webm"
		rm ffmpeg2pass-0.log
	else
		echo -e "\\n\\n\\n"
		ffmpeg -y -hide_banner -ss $start_time -i "$1" -t $duration $frame_settings $video_settings -slices 8 -threads 1 -metadata title="${1%.*}" -lag-in-frames 16 -deadline good -cpu-used 0 $filter $audio_settings "../done/${1%.*}.webm"
	fi
}

# Function to summarize the first encoding cycle.
initial_encode () {
	contains "$filter_settings" "scale" || { downscale "$video_bitrate" && framedrop; }
	video 0
	convert "$1"
}

# Loops through the different video settings if the webm is too large/small
# Every setting can be done twice: Once with the original calculated and once with an adjusted bitrate
limiter () {
	#echo "Debug mode: Enter webm size."
	#read -r webm_size
	webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${1%.*}.webm")
	counter=0
	last_video_bitrate=$video_bitrate
	while [[ $webm_size -gt $(bc <<< "($file_size*1024*1024+0.5)/1") || $webm_size -lt $(bc <<< "($file_size*1024*1024*$undershoot_limit+0.5)/1") ]]; do
		
		if [[ $webm_size -lt $(bc <<< "($file_size*1024*1024+0.5)/1") && -z $best_try_counter ]]; then
			best_try_counter=$counter
			best_try_bitrate=$last_video_bitrate
		fi
		
		(( counter += 1 ))
		
		if [[ $(($counter%3)) -eq 0 ]]; then
			new_video_bitrate=$video_bitrate
		else
			new_video_bitrate=$(bc <<< "($last_video_bitrate*$file_size*1024*1024/$webm_size+0.5)/1")
			difference=$(($last_video_bitrate-$new_video_bitrate))
			if [[ ${difference#-} -lt $(bc <<< "($last_video_bitrate*0.1+0.5)/1") && $difference -gt 0 ]]; then
				new_video_bitrate=$(bc <<< "($last_video_bitrate/1.1+0.5)/1")
			elif [[ ${difference#-} -lt $(bc <<< "($last_video_bitrate*0.1+0.5)/1") && $difference -lt 0 ]]; then
				new_video_bitrate=$(bc <<< "($last_video_bitrate*1.1+0.5)/1")
			fi
		fi
		
		if [[ $new_video_bitrate -lt $last_video_bitrate || $new_video_bitrate -gt $(bc <<< "($last_video_bitrate*1.5+0.5)/1") ]]; then contains "$filter_settings" "scale" || { downscale "$new_video_bitrate" && framedrop; }; fi
		
		if [[ "$counter" -le 8 ]]; then 
			video "$counter"
			convert "$1" 
			last_video_bitrate=$new_video_bitrate
			#echo "Debug mode: Enter webm size."
			#read -r webm_size
			webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${1%.*}.webm")
		else
			if [[ -n $best_try_counter ]]; then
				video "b"
				new_video_bitrate=$best_try_bitrate
				video "best_try_counter"
				convert "$1"
				break
			else
				video "$counter"
				break
			fi
		fi
	done
}

####################
# Main script 
####################

# Read input parameters and assigns values accordingly
while getopts ":htaqns:u:f:" ARG; do
	case "$ARG" in
	h) usage && exit;;
	t) trim_mode=true;;
	a) audio_mode=true;;
	q) hq_mode=true;;
	n) new_codecs=true;;
	s) file_size="$OPTARG";;
	u) undershoot_limit="$OPTARG";;
	f) filter_settings="$OPTARG";;
	*) echo "Unknown flag used. Use $0 -h to show all available options." && exit;;
	esac;
done

# Set default values for unspecified parameters
[[ -z $trim_mode ]] && trim_mode=false
[[ -z $audio_mode ]] && audio_mode=false
[[ -z $hq_mode ]] && hq_mode=false
[[ -z $new_codecs ]] && new_codecs=false
[[ -z $file_size ]] && file_size=3
[[ -z $undershoot_limit ]] && undershoot_limit=0.75

# Set default conversion variables that are the same for all files
# Might get overwritten if the corresponding flags are set
audio_bitrate=0
audio_settings="-an"
start_time=0
if [[ "$hq_mode" = true ]]; then
	bcc_threshold=0.075
	height_threshold=240
else
	bcc_threshold=0.04
	height_threshold=360
fi

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
	# Duration is different for each file, so it must be defined for each file seperately
	duration=$length
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