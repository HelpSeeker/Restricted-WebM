#!/bin/bash

# Activates debug mode
# No encoding attempts will be made
# Outpul file size can be entered manually
# Variables will be echoed in the convert function
debug_mode=false

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Default settings
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Don't touch these, unless you want to mess with / break the script's main functionality
trim_mode=false
audio_mode=false
hq_mode=false
showcase=false
new_codecs=false
audio_bitrate=0
audio_settings="-an"
start_time=0
user_scale=false
user_bpp=false

# These values change the default limits of the script
file_size=3
undershoot_limit=0.75
adjust_iterations=3
height_threshold=180
bpp_threshold=0.04
# hq_bpp_threshold is used for both HQ and audio showcase mode
hq_bpp_threshold=0.075
# 96kbps produces decent results for Vorbis, comparable to mp3 at 128kbps
# http://listening-test.coresv.net/results.htm
hq_min_audio=96

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Functions
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Function to define help text for the -h flag
usage () {
	echo -e "Usage: $0 [-h] [-t] [-a] [-q] [-n] [-s file_size_limit] [-c { auto | manual | video }] [-f filters]"
	echo -e "\\t\\t[-u undershoot_limit] [-i iterations] [-g height_threshold] [-b bpp_threshold]"
	
	echo -e "\\nMain options:\\n"
	echo -e "\\t-h: Show Help."
	echo -e "\\t-t: Enable trim mode."
	echo -e "\\t-a: Enable audio encoding."
	echo -e "\\t-q: Enable HQ (high quality) mode. Doesn't work if you manually use the scale filter."
	echo -e "\\t-n: Use the newer codecs VP9/Opus instead of VP8/Vorbis."
	echo -e "\\t-s file_size_limit: Specify the file size limit in MB. Default value is 3."
	echo -e "\\t\\t4chan limits:"
	echo -e "\\t\\t\\t/gif/ and /wsg/: 4MB - audio allowed - max. 300 seconds"
	echo -e "\\t\\t\\tall other boards: 3MB - no audio allowed - max. 120 seconds"
	echo -e "\\t\\t8chan limits:"
	echo -e "\\t\\t\\tall boards: 8MB - audio allowed"
	
	echo -e "\\t-c { auto | manual | video }: Enable audio showcase mode. Supersedes -a, -u and -q flag."
	echo -e "\\t\\tauto: Use images with matching filename in showcase_pictures."
	echo -e "\\t\\tmanual: Enter path to picture manually for each video."
	echo -e "\\t\\tvideo: Apply settings to videos in to_convert."
	echo -e "\\t-f filters: Add custom ffmpeg filters. Refer to ffmpeg's documentation for further information"
	
	echo -e "\\nAdvanced options:"
	echo -e "(default values can be changed permanently in the beginning of the script)\\n"
	echo -e "\\t-u undershoot_limit: Define what percentage of the file size limit must be utilized. Default value: 0.75 (75%)."
	echo -e "\\t-i iterations: Define how many encoding attempts there will be for each bitrate mode. Default value is 3."
	echo -e "\\t-g height_threshold: Set the minimum pixel height the output webm should have. Default value: 180."
	echo -e "\\t-b bpp_threshold: Set the minimum bpp value the output webm should have (higher values -> higher quality, more downscaling). Default value: 0.04 for normal, 0.075 for HQ/audio showcase mode.\n"
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Look for certain substring $2 within a string $1
# If substring is found (e.i. $1 contains the substring) -> Success
contains () {
	case "$1" in 
		*"$2"*) return 0;;
		*) return 1;;
	esac
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Get picture path for audio showcase mode
pathFinder () {
	if [[ "$showcase_mode" = "manual" ]]; then
		echo "Manual audio showcase mode:"
		echo "Enter image path for $input"
		read -r picture_path
	elif [[ "$showcase_mode" = "auto" ]]; then
		# Search for picture with the same filename and any extension
		picture_path=$(find ../showcase_pictures/ -type f -name "${input%.*}.*")
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Get important video properties for later calculations (via ffprobe)
info () {
	length=$(ffprobe -v error -show_entries format=duration \
					-of default=noprint_wrappers=1:nokey=1 "$input")
	
	# Read video height/width of the input video in to_convert
	# Alternatively the picture being used during auto/manual showcase mode
	if [[ "$showcase_mode" = "auto" || "$showcase_mode" = "manual" ]]; then
		video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
					-of default=noprint_wrappers=1:nokey=1 "$picture_path")
		
		video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
					-of default=noprint_wrappers=1:nokey=1 "$picture_path")
	else
		video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
					-of default=noprint_wrappers=1:nokey=1 "$input")
		
		video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
					-of default=noprint_wrappers=1:nokey=1 "$input")
	fi
	
	# Read frame rate of the input video
	# Set it to 1fps, if the audio showcase mode is active
	if [[ "$showcase" = true ]]; then 
		frame_rate=1
	else 
		frame_rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate \
					-of default=noprint_wrappers=1:nokey=1 "$input")
	fi
	
	aspect_ratio=$(bc <<< "scale=3; $video_width/$video_height")
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Determine height/width of the output, when a user defined scale filter is being used
scaleTest () {
	# Encode 1s with the user defined scale filter. 
	# No output will appear in the console
	if [[ "$showcase_mode" = "auto" || "$showcase_mode" = "manual" ]]; then
		ffmpeg -y -hide_banner -loglevel panic -loop 1 -i "$picture_path" -i "$input" \
					-map 0:0 -map 1:a -t 1 -pix_fmt yuv420p -c:v libvpx -crf 10 \
					-deadline good -cpu-used 5 -filter_complex $filter_settings \
					-an "../done/${input%.*}.webm"
	else
		ffmpeg -y -hide_banner -loglevel panic -i "$input" \
					-t 0.1 -c:v libvpx -crf 10 -deadline good -cpu-used 5 -auto-alt-ref 0 \
					-filter_complex $filter_settings -an "../done/${input%.*}.webm"
	fi
	
	# Read user set height/width from the test webm
	video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
					-of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
	
	video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
					-of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Determine codec/size of the input audio
# If Vorbis/Opus and feasible bitrate -> copy audio
audioTest () {
	# Reset main test value for each file
	same_codec=false
	
	# Test if the input audio codec is the same as the one being used
	input_audio_codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_long_name \
					-of default=noprint_wrappers=1:nokey=1 "$input")
	
	if [[ "$new_codecs" = true ]]; then
		contains "$input_audio_codec" "Opus" && same_codec=true
	else
		contains "$input_audio_codec" "Vorbis" && same_codec=true
	fi
	
	# Get audio bitrate (makeshift solution)
	# ffprobe can't get audio stream bitrate, but overall bitrate of an audio container
	if [[ "$same_codec" = true ]]; then
		ffmpeg -y -hide_banner -loglevel panic -i "$input" -map 0:a:0 \
					-c:a copy "../done/${input%.*}.webm"
					
		input_audio_bitrate=$(ffprobe -v error -show_entries format=bit_rate \
					-of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Get start/end time for trimming
trim () {
	# Prompt user to specify start/end time (in seconds)
	echo "Current file: $input"
	echo "Please specify where to start encoding (in seconds). Leave empty to start at the beginning of the input video."
	read -r start_time
	echo "Now please specify where to stop encoding (in seconds). Leave empty to stop at the end of the input video."
	read -r end_time
	
	# If no input, set start time to 0 and/or end time to video length
	[[ -z $start_time ]] && start_time=0
	[[ -z $end_time ]] && end_time=$length
	
	duration=$(bc <<< "scale=3; $end_time-$start_time")
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Define audio codec and its settings
audio () {
	# Determine input audio stream properties via audioTest
	audioTest

	# Choose audio bitrate based on length / file size limit 
	# Audio showcase mode chooses higher bitrate sooner
	if [[ "$showcase" = true ]]; then
		# -1 to have some wiggle room for the video stream
		# Otherwise ~90% of the file size limit would be audio
		audio_factor=$(bc <<< "$file_size*8*1000/($duration*32)-1")
		case $audio_factor in
			0 | 1 | 2 | 3) audio_bitrate=96;;
			4) audio_bitrate=128;;
			5) audio_bitrate=160;;
			*) audio_bitrate=192;;
		esac
	else
		# Assignment of the audio factor tries to recreate my experience with 4MB webms
		audio_factor=$(bc <<< "$file_size*8*1000/($duration*5.5*32)")
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
	fi
	
	# Ensure that HQ mode gets a higher minimum audio bitrate
	if [[ "$hq_mode" = true && $audio_bitrate -lt $hq_min_audio ]]; then 
		audio_bitrate=$hq_min_audio
	fi
	
	# Set Opus or Vorbis as the audio codec (based on -n flag)
	if [[ "$new_codecs" = true ]]; then
		audio_codec="libopus"
		# 48000, because Opus only allows certain sampling rates (48000, 24000, 16000, 12000, 8000)
		sampling_rate=48000
	else
		audio_codec="libvorbis"
		sampling_rate=44100
	fi
	
	# If viable (same codec, smaller/equal bitrate) copy input audio
	# *1.05 since bitrate isn't an exact business
	# Automatically disabled if trim mode is active
	if [[ "$same_codec" = true && \
			$(bc <<< "$input_audio_bitrate <= $audio_bitrate*1000*1.05") -eq 1 && \
			"$trim_mode" = false ]]; then
		audio_settings="-c:a copy"
	else
		audio_settings="-c:a $audio_codec -ac 2 -ar $sampling_rate -b:a ${audio_bitrate}K"
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Calculate important values (first video bitrate, original bpp value)
calc () {
	video_bitrate=$(bc <<< "$file_size*8*1000/$duration-$audio_bitrate")
	# Prevent negative bitrate for extreme file size limit / length combos
	if (( video_bitrate <= 0 )); then video_bitrate=50; fi
	bpp=$(bc <<< "scale=3; $video_bitrate*1000/($video_height*$video_width*$frame_rate)")
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Downscale output based on bpp value
# Needs video bitrate as input argument
downscale () {
	# Reset start values for each call
	new_video_height=$video_height
	new_frame_rate=$frame_rate
	new_bpp=$bpp
	
	# Reduce output height until bpp >= bpp threshold or output height <= height threshold*2
	# Width will be adjusted by ffmpeg's scale filter
	while (( $(bc <<< "$new_bpp < $bpp_threshold") && new_video_height > height_threshold*2 )); do
		(( new_video_height -= 10 ))
		new_bpp=$(bc <<< "scale=3; $1*1000/($new_video_height*$new_video_height*$aspect_ratio*$new_frame_rate)")
		scaling_factor="scale=-1:$new_video_height"
	done
	
	# Reduce frame rate if bpp >= bpp threshold
	framedrop
	
	# New bpp calculation 
	# Avoids unnecessary cycle in the following while loop
	new_bpp=$(bc <<< "scale=3; $1*1000/($new_video_height*$new_video_height*$aspect_ratio*$new_frame_rate)")
	
	# Reduce output height further if bpp >= bpp
	# Stops if output height <= height threshold
	while (( $(bc <<< "$new_bpp < $bpp_threshold") && new_video_height > height_threshold )); do
		(( new_video_height -= 10 ))
		new_bpp=$(bc <<< "scale=3; $1*1000/($new_video_height*$new_video_height*$aspect_ratio*$new_frame_rate)")
		scaling_factor="scale=-1:$new_video_height"
	done
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Reduce frame rate
# Needs video bitrate as input argument
framedrop () {
	# Calculates new_bpp if user defined scale filter 
	# Necessary, since downscale would be disabled
	if [[ "$user_scale" = true ]]; then 
		new_bpp=$(bc <<< "scale=3; $1*1000/($video_height*$video_width*$frame_rate)")
	fi
	
	# Reduce frame rate to 24fps if bpp <= bpp threshold and input frame rate > 24fps
	# Audio showcase mode not affected, since frame rate defined as 1fps
	if (( $(bc <<< "$new_bpp < $bpp_threshold") && $(bc <<< "$frame_rate > 24") )); then
		new_frame_rate=24
	else 
		new_frame_rate=$frame_rate
	fi
	
	frame_settings="-r $new_frame_rate"
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Adjust video bitrate
# Try counter as input argument (first try for a bitrate mode?)
bitrate () {
	if (( $1 == 1 )); then
		# Each bitrate mode begins with the initially calculated bitrate
		last_video_bitrate=$video_bitrate
		new_video_bitrate=$video_bitrate
	else
		# Save last video bitrate for comparison of conesecutive attempts
		last_video_bitrate=$new_video_bitrate
		
		# Adjust new video bitrate based on output file size
		new_video_bitrate=$(bc <<< "($last_video_bitrate*$file_size*1024*1024/$webm_size+0.5)/1")
		
		# Ensure a minimum decrease of 10%
		# No minimal increase percentage 
		difference=$(( last_video_bitrate - new_video_bitrate ))
		if (( $(bc <<< "${difference#-} < $last_video_bitrate*0.1") && difference > 0 )); then 
			new_video_bitrate=$(bc <<< "($last_video_bitrate/1.1+0.5)/1")
		fi
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Define video codec and bitrate mode
# Number of bitrate mode as input argument (unless audio showcase mode)
# 1: VBR with qmax
# 2: VBR without qmax
# 3: CBR
# 4 (not used anymore): CBR and allow to drop frames
video () {
	# Set libvpx-vp9 (VP9) or libvpx (VP8) as vcodec (based on -n flag)
	if [[ "$new_codecs" = true ]]; then video_codec="libvpx-vp9"; else video_codec="libvpx"; fi
	
	# Define bitrate mode and its settings
	if [[ "$showcase" = true ]]; then
		# Basically constant quality with crf 10 (i.e. -crf 10 -b:v 0)
		# As reference: Results slightly worse than libx264 with crf 18
		video_settings="-c:v $video_codec -crf 10 -qmax 50 -b:v 10M"
	else
		case $1 in
			1) video_settings="-c:v $video_codec -qmax 50 -b:v ${new_video_bitrate}K";;
			2) video_settings="-c:v $video_codec -b:v ${new_video_bitrate}K";;	
			3) video_settings="-c:v $video_codec -minrate:v ${new_video_bitrate}K \
					-maxrate:v ${new_video_bitrate}K -b:v ${new_video_bitrate}K";;
			# Prior 4th bitrate mode; allows to drop frames
			# About 99% chance to fit any video stream into file size limit
			# Drawback: Turns videos into slideshows
			# 4) video_settings="-c:v $video_codec -bufsize $bufsize -minrate:v ${video_bitrate}K \
			#		-maxrate:v ${video_bitrate}K -b:v ${video_bitrate}K -skip_threshold 100";;
			*) echo "Unknown bitrate mode!";;
		esac
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Concatenate filters
concatenate() {
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
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Define input/trim/mapping options
input() {	
	if [[ -n "$showcase_mode" && "$showcase_mode" != "video" ]]; then
		if [[ "$animated_gif" = true ]]; then 
			# -ignore_loop 0 since ffmpeg disables infinite looping gifs by default
			input_config=(-ignore_loop 0 -i "$picture_path" -ss "$start_time" \
					-i "$input" -map 0:0 -map 1:a:0)
		else
			# -loop 1 to infinitely loop the input picture to the input audio
			input_config=(-loop 1 -i "$picture_path" -ss "$start_time" \
					-i "$input" -map 0:0 -map 1:a:0 -t "$duration")
		fi
	else
		# TODO:
		# Look into gif trimming. It works for the scale test, so why shouldn't it here?
		if [[ "${input##*.}" = "gif" ]]; then 
			# no trim settings, as they cannot be applied to gifs
			input_config=(-i "$input")
		else
			input_config=(-ss "$start_time" -i "$input" -t "$duration")
		fi
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Print calculated/chosen values during debug mode
debug() {
	echo -e "\\n\\n"
	echo "Audio factor: $audio_factor"
	echo "Iteration: $i"
	echo "First try: $first_try"
	echo "Best try: $best_try"
	echo "Best try bitrate: $best_try_bitrate"
	echo "Video settings: $video_settings"
	echo "Mode counter: $mode_counter"
	echo "Attempt: $attempt"
	echo "Video bitrate: $video_bitrate"
	echo "Video height: $new_video_height"
	echo "Bpp: $new_bpp"
	echo "Filters: $filter"
	echo "User scale: $user_scale"
	echo -e "\\n\\n"
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Convert video via ffmpeg
convert () {
	# Get final filter string
	concatenate
	
	# Get input/trim/mapping options
	input	
	
	if [[ "$debug_mode" = true ]]; then
		debug
	else
		# Gifs need seperate ffmpeg commands to avoid VP8 bug
		# Alternate reference frame must be manually disabled for input with alpha layer
		if [[ "$animated_gif" = true || "${input##*.}" = "gif" ]]; then
			# 2-pass encoding automatically used for HQ and audio showcase mode
			if [[ "$hq_mode" = true ]]; then
				echo -e "\\n\\n"
				
				# Only do 1st pass, if no log file present
				[[ -e ffmpeg2pass-0.log ]] || ffmpeg -y -hide_banner "${input_config[@]}" \
					$frame_settings $video_settings -auto-alt-ref 0 -slices 8 -threads 1 \
					-deadline good -cpu-used 5 -an -pass 1 -f webm /dev/null
				
				echo -e "\\n\\n"
				
				ffmpeg -y -hide_banner "${input_config[@]}" $frame_settings -pix_fmt yuv420p \
					$video_settings -tune ssim -slices 8 -threads 1 -metadata title="${input%.*}" \
					-auto-alt-ref 0 -deadline good -cpu-used 0 $filter \
					$audio_settings -pass 2 "../done/${input%.*}.webm"
			
			# Single pass encoding used during normal mode
			else
				echo -e "\\n\\n"
				
				ffmpeg -y -hide_banner "${input_config[@]}" $frame_settings -pix_fmt yuv420p \
					$video_settings -tune ssim -slices 8 -threads 1 -metadata title="${input%.*}" \
					-auto-alt-ref 0 -deadline good -cpu-used 0 $filter \
					$audio_settings "../done/${input%.*}.webm"
			fi
		else
			# 2-pass encoding automatically used for HQ and audio showcase mode
			if [[ "$hq_mode" = true || -n $showcase_mode ]]; then
				echo -e "\\n\\n"
				
				# Only do 1st pass, if no log file present
				[[ -e ffmpeg2pass-0.log ]] || ffmpeg -y -hide_banner "${input_config[@]}" \
					$frame_settings $video_settings -slices 8 -threads 1 -deadline good \
					-cpu-used 5 -an -pass 1 -f webm /dev/null
				
				echo -e "\\n\\n"
				
				ffmpeg -y -hide_banner "${input_config[@]}" $frame_settings $video_settings \
					-tune ssim -slices 8 -threads 1 -metadata title="${input%.*}" -auto-alt-ref 1 \
					-lag-in-frames 25 -arnr-maxframes 15 -arnr-strength 3 -deadline good \
					-cpu-used 0 $filter $audio_settings -pass 2 "../done/${input%.*}.webm"
			
			# Single pass encoding used during normal mode
			else
				echo -e "\\n\\n"
				
				ffmpeg -y -hide_banner "${input_config[@]}" $frame_settings $video_settings \
					-tune ssim -slices 8 -threads 1 -metadata title="${input%.*}" -deadline good \
					-cpu-used 0 $filter $audio_settings "../done/${input%.*}.webm"
			fi
		fi
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Define settings for the audio showcase mode
# Try counter as input argument 
showcaseSettings () {
	# Animated gif detection for auto and manual showcase option
	# They receive normal video treatment
	# "0/0" is the default for static images
	if [[ "$showcase_mode" != "video" ]]; then 
		new_frame_rate=$(ffprobe -v error -show_entries stream=avg_frame_rate \
					-of default=noprint_wrappers=1:nokey=1 "$picture_path")
	else 
		new_frame_rate="0/0"
	fi
	
	# Increase keyframe interval
	# Main/only way to decrease file size during audio showcase mode
	keyframe_interval=$(( 20 * $1 ))
	
	# If an animated gif is used, treat it as a normal video
	# Choose new audio bitrate (likely to be less than with audio showcase mode)
	if [[ "$new_frame_rate" != "0/0" ]]; then 
		animated_gif=true
		frame_rate=$new_frame_rate
		showcase=false
		frame_settings="-r $frame_rate"
		audio
	else 
		frame_settings="-r $frame_rate -g $keyframe_interval"
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# First encoding cycle
initialEncode () {
	if [[ "$showcase" = true ]]; then showcaseSettings 1; fi
	
	if [[ "$user_scale" = false ]]; then 
		downscale "$video_bitrate"
	else
		framedrop "$video_bitrate"
	fi
	
	bitrate 1
	video 1
	convert
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# File size adjuster for audio showcase mode
showcaseAdjuster () {
	# Determine output file size via ffprobe
	# Entered manually during debug mode
	if [[ "$debug_mode" = true ]]; then 
		echo "Debug mode: Enter webm size." && read -r webm_size
	else 
		webm_size=$(ffprobe -v error -show_entries format=size \
					-of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
	fi
	
	# TODO: Make sure counter variable have the same name (i) if possible
	# First try done in initialEncode
	counter=2
	
	# Increase keyframe interval until webm size < file size limit
	# No undershoot limit for audio showcase mode
	while (( $(bc <<< "$webm_size > $file_size*1024*1024") )); do
		showcaseSettings "$counter"
		convert
		
		# Determine output file size via ffprobe
		# Entered manually during debug mode
		if [[ "$debug_mode" = true ]]; then 
			echo "Debug mode: Enter webm size." && read -r webm_size
		else
			webm_size=$(ffprobe -v error -show_entries format=size \
					-of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
		fi
		
		# Break loop if not able to make webm small enough (6 tries by default)
		# Add filename to too_large.txt
		if (( counter > adjust_iterations*2 )); then 
			echo "File still doesn't fit the specified limit. Please use ffmpeg manually." 
			echo "$input" >> ../too_large.txt
			break
		fi
		
		(( counter += 1 ))
	done
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Adjust file size for too small webms (webm size < undershoot limit)
# Number of bitrate mode as input argument
enhance () {
	i=2
	while (( $(bc <<< "$webm_size > $file_size*1024*1024") || \
					$(bc <<< "$webm_size < $file_size*1024*1024*$undershoot_limit") )); do
		
		bitrate "$i"
		
		# Re-apply downscale if
		# a) the webm is too big 
		# b) the newly adjusted bitrate is 40% larger than the prior one
		# Using downscale every time makes output file size too unpredictable
		if [[ ($new_video_bitrate -lt $last_video_bitrate || \
					$(bc <<< "$new_video_bitrate > $last_video_bitrate*1.4") -eq 1) && \
					"$user_scale" = false ]]; then
			
			downscale "$new_video_bitrate"
		else 
			framedrop "$new_video_bitrate"
		fi
		
		video "$1"
		convert
		
		# Determine output file size via ffprobe
		# Entered manually during debug mode
		if [[ "$debug_mode" = true ]]; then
			echo "Debug mode: Enter webm size." && read -r webm_size
		else
			webm_size=$(ffprobe -v error -show_entries format=size \
					-of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
		fi
		
		# Saves settings to reproduce best try
		# Best try: biggest output file below the undershoot limit
		if (( webm_size > best_try && $(bc <<< "$webm_size < $file_size*1024*1024") )); then
			best_try=$webm_size
			best_try_bitrate=$new_video_bitrate
			# Keep track which attempt was the best try
			# If last and best try are the same -> keep the last try
			attempt=$i
		fi
		
		# Break loop if not able to make webm small enough (6 tries by default)
		# Do a last conversion with the best try's settings or keep the last try (if best try)
		if (( i > adjust_iterations*2 )); then
			if (( attempt <= adjust_iterations*2 )); then
				new_video_bitrate=$best_try_bitrate
				video "$1"
				convert
			fi
			# Flag to break loop in adjuster
			use_best_try=true
			break
		fi
		
		(( i += 1 ))
	done
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Adjust file size for too large webms
# Number of bitrate mode as input argument
limit () {
	# If first bitrate mode, first encode was done in initialEncode
	if (( $1 == 1 )); then start=2; else start=1; fi

	for (( i = start; i <= adjust_iterations; i++ ))
	do
		bitrate "$i"
		
		# Re-apply downscale for reduced bitrate
		if [[ $new_video_bitrate -lt $last_video_bitrate && "$user_scale" = false ]]; then
			downscale "$new_video_bitrate"
		else
			framedrop "$new_video_bitrate"
		fi
		
		video "$1"
		convert
		
		# Determine output file size via ffprobe
		# Entered manually during debug mode
		if [[ "$debug_mode" = true ]]; then
			echo "Debug mode: Enter webm size." && read -r webm_size
		else
			webm_size=$(ffprobe -v error -show_entries format=size \
					-of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
		fi
		
		# Break loop if qmax (minimum quality parameter) prevents decreasing the file size
		# Only possible during first bitrate mode
		if (( $1 == 1 && $(bc <<< "$webm_size < $first_try*1.01") && \
					$(bc <<< "$webm_size > $first_try*0.99") )); then break; fi
		
		# Break loop if output file size is lower than file size limit
		# At this point file is either finished or enhance will be called
		if (( $(bc <<< "$webm_size < $file_size*1024*1024") )); then
			# Flag to prevent switching to the next bitrate mode
			small_break=true
			break
		fi
	done
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Decide which steps to take based on the output of initialEncode
adjuster () {
	# Determine output file size via ffprobe
	# Entered manually during debug mode
	if [[ "$debug_mode" = true ]]; then 
		echo "Debug mode: Enter webm size." && read -r webm_size
	else
		webm_size=$(ffprobe -v error -show_entries format=size \
					-of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
	fi
	
	# Reset default values for each file
	first_try=$webm_size
	mode_counter=1
	use_best_try=false
	small_break=false
	
	# This while loop will continue until:
	# a) the output file size lies within the specified file size range (success)
	# b) there are no more bitrate modes to go through (file too large)
	# c) the enhance function has to utilize the best try (file too small)
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
			attempt=1
			enhance $mode_counter
		fi
		
		# Keep current bitrate mode, if limit succeeds
		# Prevents the wrong bitrate mode being used by enhance (if webm size < undershoot limit)
		if [[ "$small_break" = false ]]; then (( mode_counter += 1 )); fi
	done
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main script
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Read user set flags
while getopts ":htaqns:c:f:u:i:g:b:" ARG; do
	case "$ARG" in
	h) usage && exit;;
	t) trim_mode=true;;
	a) audio_mode=true;;
	q) hq_mode=true;;
	n) new_codecs=true;;
	s) file_size="$OPTARG";;
	c) showcase_mode="$OPTARG" && showcase=true;;
	f) filter_settings="$OPTARG";;
	u) undershoot_limit="$OPTARG";;
	i) adjust_iterations="$OPTARG";;
	g) height_threshold="$OPTARG";;
	b) bpp_threshold="$OPTARG" && user_bpp=true;;	
	*) echo "Unknown flag used. Use $0 -h to show all available options." && exit;;
	esac;
done

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Set bpp threshold based on which mode was chosen
if [[ "$user_bpp" = false && ("$showcase" = true || "$hq_mode" = true) ]]; then 
	bpp_threshold=$hq_bpp_threshold
fi

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Check if valid showcase mode option was chosen
if [[ "$showcase" = true ]]; then
	case $showcase_mode in
		auto | manual | video);;
		*) echo "Invalid option for audio showcase mode!" && exit;;
	esac
fi

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Check user set filters for the word "scale"
contains "$filter_settings" "scale" && user_scale=true

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Make sure showcase_pictures/ exists (and contains files if auto option was chosen)
if [[ "$showcase_mode" = "auto" ]]; then
	cd showcase_pictures 2> /dev/null || { echo "No showcase_pictures folder present" && exit; }
	
	for file in *
	do 
		[[ -e "$file" ]] || { echo "No files present in showcase_pictures" && exit; }
		break
	done
	
	cd ..
fi

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Change into sub-directory to avoid file conflicts when converting webms
cd to_convert 2> /dev/null || { echo "No to_convert folder present" && exit; }

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Make sure there are any files in to_convert/
for file in *
do 
	[[ -e "$file" ]] || { echo "No files present in to_convert" && exit; }
	break
done

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Create sub-directory for the finished webms
mkdir ../done 2> /dev/null

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Main conversion loop
for input in *; do (
	if [[ "$showcase" = true ]]; then pathFinder; fi
	info
	if [[ "$user_scale" = true ]]; then scaleTest; fi
	
	# Length must be defined anew for each individual file
	duration=$length
	
	if [[ "$trim_mode" = true ]]; then trim; fi
	if [[ "$audio_mode" = true || "$showcase" = true ]]; then audio; fi
	calc
	initialEncode
	if [[ "$showcase" = true ]]; then showcaseAdjuster; else adjuster; fi
	# Only remove 2-pass encoding log if file is finished
	rm ffmpeg2pass-0.log 2> /dev/null
	# Reset special gif treatment during audio showcase mode 
	if [[ "$animated_gif" = true ]]; then animated_gif=false && showcase=true; fi
); done
