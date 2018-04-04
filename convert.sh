#!/bin/bash

###################
# Functions
###################

# Define help text
usage () {
	echo -e "Usage: $0 [-h] [-t] [-a] [-q] [-c { auto | manual | video }] [-n] [-s file_size_limit] [-u undershoot_limit] [-i iterations] [-f filters]"
	echo -e "\\t-h: Show Help. For more detailed infos: Read help.txt."
	echo -e "\\t-t: Enable trim mode."
	echo -e "\\t-a: Enable audio encoding."
	echo -e "\\t-q: Enable HQ (high quality) mode. Doesn't work if you manually use the scale filter."
	echo -e "\\t-c { auto | manual | video }: Enable audio showcase mode. Supersedes -a, -u and -q flag."
	echo -e "\\t\\tauto: Use images with matching filename in showcase_pictures."
	echo -e "\\t\\tmanual: Enter path to picture manually for each video."
	echo -e "\\t\\tvideo: Apply settings to videos in to_convert."
	echo -e "\\t-n: Use the newer codecs VP9/Opus instead of VP8/Vorbis."
	echo -e "\\t-s file_size_limit: Specify the file size limit in MB. Default value is 3."
	echo -e "\\t\\t4chan limits:"
	echo -e "\\t\\t\\t/gif/ and /wsg/: 4MB - audio allowed - max. 300 seconds"
	echo -e "\\t\\t\\tall other boards: 3MB - no audio allowed - max. 120 seconds"
	echo -e "\\t\\t8chan limits:"
	echo -e "\\t\\t\\tall boards: 8MB - audio allowed"
	echo -e "\\t-u undershoot_limit: Define what percentage of the file size limit must be utilized. Default value: 0.75 (75%)."
	echo -e "\\t-i iterations: Define how many encoding attempts there will be for each bitrate mode. Default value is 3."
	echo -e "\\t-f filters: Add custom ffmpeg filters. Refer to ffmpeg's documentation for further information"
}

# Look for certain substring $2 within a string $1
# Succeeds if substring is found within the string (e.i. it contains the substring)
contains () {
	case "$1" in 
		*"$2"*) return 0;;
		*) return 1;;
	esac
}

# Get path to picture for audio showcase mode
pathFinder () {
	if [[ "$showcase_mode" = "manual" ]]; then
		echo "Manual audio showcase mode:"
		echo "Enter image path for $input"
		read -r picture_path
	elif [[ "$showcase_mode" = "auto" ]]; then
		picture_path=$(find ../showcase_pictures/ -type f -name "${input%.*}.*")
	fi
}

# Use ffprobe to get video properties for later calculations
info () {
	length=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input")
	if [[ "$showcase_mode" = "auto" || "$showcase_mode" = "manual" ]]; then
		video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$picture_path")
		video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$picture_path")
	else
		video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$input")
		video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$input")
	fi
	if [[ "$showcase" = true ]]; then frame_rate=1; else frame_rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$input"); fi
	aspect_ratio=$(bc <<< "scale=3; $video_width/$video_height")
}

# Ask user where to start and end video and use it to calculate the video duration
trim () {
	echo "Current file: $input"
	echo "Please specify where to start encoding (in seconds). Leave empty to start at the beginning of the input video."
	read -r start_time
	[[ -z $start_time ]] && start_time=0
	echo "Now please specify where to stop encoding (in seconds). Leave empty to stop at the end of the input video."
	read -r end_time
	[[ -z $end_time ]] && end_time=$length
	duration=$(bc <<< "scale=3; $end_time-$start_time")
}

# Define audio codec and properties
# Audio bitrate function/assignment is the result of me trying to match my experience with 4MB webms
audio () {
	if [[ "$hq_mode" = true ]]; then
		audio_bitrate=96
	elif [[ "$showcase" = true ]]; then
		# -1 to have some wiggle room for the video stream. Otherwise the audio would take up ~90% of the file size limit
		audio_factor=$(bc <<< "$file_size*8*1000/($duration*32)-1")
		case $audio_factor in
			0 | 1 | 2 | 3) audio_bitrate=96;;
			4) audio_bitrate=128;;
			5) audio_bitrate=160;;
			*) audio_bitrate=192;;
		esac
	else
		audio_factor=$(bc <<< "$file_size*8*1000/($duration*5.5*32)")
		case $audio_factor in
			0) audio_bitrate=48;;
			1) audio_bitrate=64;;
			2 | 3 | 4 | 5 | 6) audio_bitrate=96;;
			*) audio_bitrate=128;;
		esac
	fi
	if [[ "$new_codecs" = true ]]; then
		audio_codec="libopus"
		# 48000, because Opus only allows certain sampling rates (48000, 24000, 16000, 12000, 8000)
		sampling_rate=48000
	else
		audio_codec="libvorbis"
		sampling_rate=44100
	fi
	
	audio_settings="-c:a $audio_codec -ac 2 -ar $sampling_rate -b:a ${audio_bitrate}K"
}

# Calculate important values for the encoding process
calc () {
	video_bitrate=$(bc <<< "($file_size*8*1000/$duration-$audio_bitrate+0.5)/1")
	bpp=$(bc <<< "scale=3; $video_bitrate*1000/($video_height*$video_width*$frame_rate)")
	new_bpp=$bpp
}

# Reduce output height (width is later adjusted via aspect ratio) to reach certain bits per pixel value; min. output height is 360p/240p
# If bpp still too low (and input frame rate >24), reduce frame rate to 24fps
# Video bitrate as input to be able to use it with adjusted bitrates as well
downscale () {
	new_video_height=$video_height
	new_bpp=$bpp
	while (( $(bc <<< "$new_bpp < $bcc_threshold") && new_video_height > height_threshold )); do
		(( new_video_height -= 10 ))
		new_bpp=$(bc <<< "scale=3; $1*1000/($new_video_height*$new_video_height*$aspect_ratio*$frame_rate)")
		scaling_factor="scale=-1:$new_video_height"
	done
	
	if (( $(bc <<< "$new_bpp < $bcc_threshold") && $(bc <<< "$frame_rate > 24") )); then
		new_frame_rate=24
		frame_settings="-r $new_frame_rate"
	else 
		frame_settings=""
	fi
}

# Calculate adjusted bitrate
# Every bitrate mode is supposed to start with the initial bitrate (calculated in calc), before the bitrate gets adjusted
# Min. bitrate difference after each adjustment is 10% of the previous bitrate
bitrate () {
	if (( $1 == 1 )); then
		last_video_bitrate=$video_bitrate
		new_video_bitrate=$video_bitrate
	else
		last_video_bitrate=$new_video_bitrate
		new_video_bitrate=$(bc <<< "($last_video_bitrate*$file_size*1024*1024/$webm_size+0.5)/1")
		difference=$(( last_video_bitrate - new_video_bitrate ))
		if (( $(bc <<< "${difference#-} < $last_video_bitrate*0.1") && difference > 0 )); then
			new_video_bitrate=$(bc <<< "($last_video_bitrate/1.1+0.5)/1")
		elif (( $(bc <<< "${difference#-} < $last_video_bitrate*0.1") && difference < 0 )); then
			new_video_bitrate=$(bc <<< "($last_video_bitrate*1.1+0.5)/1")
		fi
	fi
}

# Define which video codec and bitrate mode to use
# Needs number of bitrate mode and the to be used video bitrate as input, unless audio showcase mode is active
video () {
	if [[ "$new_codecs" = true ]]; then video_codec="libvpx-vp9"; else video_codec="libvpx"; fi
	if [[ "$showcase" = true ]]; then
		video_settings="-c:v $video_codec -crf 10 -qmax 50 -b:v 10M"
	else
		case $1 in
			1) video_settings="-c:v $video_codec -crf 10 -qmax 50 -b:v ${2}K";;
			2) video_settings="-c:v $video_codec -crf 10 -b:v ${2}K";;	
			3) video_settings="-c:v $video_codec -minrate:v ${2}K -maxrate:v ${2}K -b:v ${2}K";;
			# 4) video_settings="-c:v $video_codec -bufsize $bufsize -minrate:v ${video_bitrate}K -maxrate:v ${video_bitrate}K -b:v ${video_bitrate}K -skip_threshold 100";;
			*) echo "Unknown bitrate mode!";;
		esac
	fi
}

# Define frame_settings for audio showcase mode
# Input is how many tries (at lowering the file size) were already attempted
showcaseSettings () {
	keyframe_interval=$(( 20 * $1 ))
	frame_settings="-r $frame_rate -g $keyframe_interval"
}

# Actual ffmpeg conversion commands
# Also used to concatenate automatic downscale and user defined filters
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
	
	if [[ "$showcase_mode" = "auto" || "$showcase_mode" = "manual" ]]; then
		echo -e "\\n\\n\\n"
		ffmpeg -y -hide_banner -ss $start_time -loop 1 -i "$picture_path" -i "$input" -t $duration $frame_settings -pix_fmt yuv420p $video_settings -slices 8 -threads 1 -deadline good -cpu-used 5 -an -pass 1 -f webm /dev/null
		echo -e "\\n\\n\\n"
		ffmpeg -y -hide_banner -ss $start_time -loop 1 -i "$picture_path" -i "$input" -t $duration $frame_settings -pix_fmt yuv420p $video_settings -slices 8 -threads 1 -metadata title="${input%.*}" -auto-alt-ref 1 -lag-in-frames 16 -deadline good -cpu-used 0 $filter $audio_settings -pass 2 "../done/${input%.*}.webm"
		rm ffmpeg2pass-0.log
	else
		if [[ $(bc <<< "$new_bpp >= 0.075") -eq 1 || "$showcase_mode" = "video" ]]; then
			echo -e "\\n\\n\\n"
			ffmpeg -y -hide_banner -ss $start_time -i "$input" -t $duration $frame_settings $video_settings -slices 8 -threads 1 -deadline good -cpu-used 5 -an -pass 1 -f webm /dev/null
			echo -e "\\n\\n\\n"
			ffmpeg -y -hide_banner -ss $start_time -i "$input" -t $duration $frame_settings $video_settings -slices 8 -threads 1 -metadata title="${input%.*}" -auto-alt-ref 1 -lag-in-frames 16 -deadline good -cpu-used 0 $filter $audio_settings -pass 2 "../done/${input%.*}.webm"
			rm ffmpeg2pass-0.log
		else
			echo -e "\\n\\n\\n"
			ffmpeg -y -hide_banner -ss $start_time -i "$input" -t $duration $frame_settings $video_settings -slices 8 -threads 1 -metadata title="${input%.*}" -lag-in-frames 16 -deadline good -cpu-used 0 $filter $audio_settings "../done/${input%.*}.webm"
		fi
	fi
	
	# Print various variables for debugging purposes
	#~ echo "Audio factor: $audio_factor"
	#~ echo "Iteration: $i"
	#~ echo "First try: $first_try"
	#~ echo "Video settings: $video_settings"
	#~ echo "Mode counter: $mode_counter"
	#~ echo "Filters: $filter"
}

# Function to summarize the first encoding cycle.
initialEncode () {
	contains "$filter_settings" "scale" || downscale "$video_bitrate"
	if [[ "$showcase" = true ]]; then showcaseSettings 1; fi
	bitrate 1
	video 1 "$video_bitrate"
	convert
}

# Quality adjustment to raise output above undershoot limit
enhance () {
	i=2
	while (( $(bc <<< "$webm_size > $file_size*1024*1024") || $(bc <<< "$webm_size < $file_size*1024*1024*$undershoot_limit") )); do
		bitrate "$i"
		if (( new_video_bitrate < last_video_bitrate || $(bc <<< "$new_video_bitrate > $last_video_bitrate*1.4") )); then contains "$filter_settings" "scale" || downscale "$new_video_bitrate"; fi
		video "$1" "$new_video_bitrate"
		convert
		webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
		#echo "Debug mode: Enter webm size."
		#read -r webm_size
		if (( webm_size > best_try && $(bc <<< "$webm_size < $file_size*1024*1024") )); then
			best_try=$webm_size
			best_try_bitrate=$new_video_bitrate
		fi
		if (( i > adjust_iterations*2 )); then
			use_best_try=true
			video "$1" "$best_try_bitrate"
			convert
			break
		fi
		(( i += 1 ))
	done
}

# Quality adjustment to force output into the file size limit
limit () {
	if (( $1 == 1 )); then start=2; else start=1; fi
	for (( i = start; i <= adjust_iterations; i++ ))
	do
		bitrate "$i"
		if (( new_video_bitrate < last_video_bitrate )); then contains "$filter_settings" "scale" || downscale "$new_video_bitrate"; fi
		video "$1" "$new_video_bitrate"
		convert
		webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
		#echo "Debug mode: Enter webm size."
		#read -r webm_size
		if (( $1 == 1 && $(bc <<< "$webm_size < $first_try*1.01") && $(bc <<< "$webm_size > $first_try*0.99") )); then break; fi
		if (( $(bc <<< "$webm_size < $file_size*1024*1024") )); then small_break=true; break; fi
	done
}

# Decide which steps to take based on the webm of the initial encode
adjuster () {
	#echo "Debug mode: Enter webm size."
	#read -r webm_size
	webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
	first_try=$webm_size
	mode_counter=1
	use_best_try=false
	small_break=false
	while (( $(bc <<< "$webm_size > $file_size*1024*1024") || $(bc <<< "$webm_size < $file_size*1024*1024*$undershoot_limit") )); do
		if [[ "$use_best_try" = true ]]; then
			echo "Failed to raise output file size above undershoot limit." 
			echo "$input" >> ../too_small_for_undershoot.txt
			break
		elif (( mode_counter > 3 )); then
			echo "File still doesn't fit the specified limit. Please use ffmpeg manually." 
			echo "$input" >> ../too_large.txt
			break
		elif (( $(bc <<< "$webm_size > $file_size*1024*1024") )); then
			limit $mode_counter
		elif (( $(bc <<< "$webm_size < $file_size*1024*1024*$undershoot_limit") )); then
			best_try=$webm_size
			best_try_bitrate=$last_video_bitrate
			enhance $mode_counter
		fi
		if [[ "$small_break" = false ]]; then (( mode_counter += 1 )); fi
	done
}

# Reduce file size for audio showcase webms
# Limited possibilities since ffprobe can't show the size of a single stream
showcaseAdjuster () {
	webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
	counter=2
	while (( $(bc <<< "$webm_size > $file_size*1024*1024") )); do
		showcaseSettings "$counter"
		convert
		webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
		if (( counter > 6 )); then 
			echo "File still doesn't fit the specified limit. Please use ffmpeg manually." 
			echo "$input" >> ../too_large.txt
			break
		fi
		(( counter += 1 ))
	done
}

####################
# Main script 
####################

# Read input parameters and assign values accordingly
while getopts ":htaqc:ns:u:i:f:" ARG; do
	case "$ARG" in
	h) usage && exit;;
	t) trim_mode=true;;
	a) audio_mode=true;;
	q) hq_mode=true;;
	c) showcase_mode="$OPTARG";;
	n) new_codecs=true;;
	s) file_size="$OPTARG";;
	u) undershoot_limit="$OPTARG";;
	i) adjust_iterations="$OPTARG";;
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
[[ -z $adjust_iterations ]] && adjust_iterations=3
if [[ -n $showcase_mode ]]; then
	case $showcase_mode in
		auto | manual | video) showcase=true && hq_mode=false;;
		*) echo "Invalid option for audio showcase mode!" && exit;;
	esac
else
	showcase=false
fi


# Set default conversion variables that are the same for all files
# Might get overwritten if any corresponding flags are set
audio_bitrate=0
audio_settings="-an"
start_time=0
if [[ "$hq_mode" = true ]]; then
	bcc_threshold=0.075
	height_threshold=240
elif [[ "$showcase" = true ]]; then
	bcc_threshold=0.075
	height_threshold=360
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
	if [[ "$showcase" = true ]]; then pathFinder; fi
	info
	# Length must be defined anew for each individual file
	duration=$length
	if [[ "$trim_mode" = true ]]; then trim; fi
	if [[ "$audio_mode" = true || "$showcase" = true ]]; then audio; fi
	calc
	initialEncode
	if [[ "$showcase" = true ]]; then showcaseAdjuster; else adjuster; fi
); done