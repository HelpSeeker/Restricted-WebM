#!/bin/bash

# Activates debug mode
# No encoding attempts will be made. Outpul file size can be entered manually. Variables will be echoed in the convert function.
debug_mode=false

###################
# Functions
###################

# Function to define help text for the -h flag
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


# Function to look for certain substring $2 within a string $1
# Succeeds if substring is found within the string (e.i. it contains the substring)
contains () {
	case "$1" in 
		*"$2"*) return 0;;
		*) return 1;;
	esac
}


# Function to get path to picture for audio showcase mode
pathFinder () {
	if [[ "$showcase_mode" = "manual" ]]; then
		echo "Manual audio showcase mode:"
		echo "Enter image path for $input"
		read -r picture_path
	elif [[ "$showcase_mode" = "auto" ]]; then
		# Searches for picture with the same filename and any extension
		picture_path=$(find ../showcase_pictures/ -type f -name "${input%.*}.*")
	fi
}


# Function to get important video properties for later calculations (via ffprobe)
info () {
	length=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input")
	
	# Reads video height/width of the input video in to_convert/ or the picture being used during auto/manual showcase mode
	if [[ "$showcase_mode" = "auto" || "$showcase_mode" = "manual" ]]; then
		video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$picture_path")
		video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$picture_path")
	else
		video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$input")
		video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$input")
	fi
	
	# Reads frame rate of the input video or sets it to 1fps, if the audio showcase mode is active
	if [[ "$showcase" = true ]]; then frame_rate=1; else frame_rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$input"); fi
	
	aspect_ratio=$(bc <<< "scale=3; $video_width/$video_height")
}


# Function to determine height/width of the output, when a user defined scale filter is being used
scaleTest () {
	# Encodes 1s with the user defined scale filter. "-deadline realtime" for faster encoding speed.
	# No output will appear in the console
	if [[ "$showcase_mode" = "auto" || "$showcase_mode" = "manual" ]]; then
		ffmpeg -y -hide_banner -loglevel panic -loop 1 -i "$picture_path" -i "$input" -map 0:0 -map 1:a -t 1 -pix_fmt yuv420p -c:v libvpx -crf 10 -deadline realtime -filter_complex $filter_settings -an "../done/${input%.*}.webm"
	else
		ffmpeg -y -hide_banner -loglevel panic -i "$input" -t 1 -c:v libvpx -crf 10 -deadline realtime -filter_complex $filter_settings -an "../done/${input%.*}.webm"
	fi
	
	# Height and width can now be defined via the output file
	# Ensures that user defined scaling doesn't prevent later calculations
	video_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
	video_width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
}


# Function to determine codec and size of the input audio and if it's feasible to copy the audio stream instead of re-encoding it
# Makeshift solution, since ffprobe isn't able to determine the audio stream bitrate, but the overall bitrate of a container with only an audio stream in it
audioTest () {
	# Resets main test value for each file
	same_codec=false
	
	# Tests if the input audio codec is the same as the one being used
	input_audio_codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_long_name -of default=noprint_wrappers=1:nokey=1 "$input")
	if [[ "$new_codecs" = true ]]; then
		contains "$input_audio_codec" "Opus" && same_codec=true
	else
		contains "$input_audio_codec" "Vorbis" && same_codec=true
	fi
	
	# Gets information about the audio stream size by copying it in its own container and using ffprobe
	if [[ "$same_codec" = true ]]; then
		ffmpeg -y -hide_banner -loglevel panic -i "$input" -map 0:a:0 -c:a copy "../done/${input%.*}.webm"
		input_audio_bitrate=$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm")
	fi
}


# Function to define variables used for trimming the input
trim () {
	# Prompts the user to specify which part of the input to encode
	echo "Current file: $input"
	echo "Please specify where to start encoding (in seconds). Leave empty to start at the beginning of the input video."
	read -r start_time
	echo "Now please specify where to stop encoding (in seconds). Leave empty to stop at the end of the input video."
	read -r end_time
	
	# Sets start and/or end of the input as default value, if no input was given
	[[ -z $start_time ]] && start_time=0
	[[ -z $end_time ]] && end_time=$length
	
	duration=$(bc <<< "scale=3; $end_time-$start_time")
}


# Function to define audio codec and its settings
audio () {
	# Determines input audio stream properties via audioTest function
	audioTest

	# Chooses audio bitrate based on length / file size limit and whether or not the audio showcase mode is being used
	if [[ "$showcase" = true ]]; then
		# -1 to have some wiggle room for the video stream. Otherwise the audio would take up ~90% of the file size limit
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
	
	# Ensures that HQ mode gets a higher minimum audio bitrate
	# 96kbps produces decent results for Vorbis, comparable to mp3 at 128kbps (see: http://listening-test.coresv.net/results.htm)
	if [[ "$hq_mode" = true && $audio_bitrate -lt 96 ]]; then audio_bitrate=96; fi
	
	# Sets Opus or Vorbis as the audio codec (based on the -n flag)
	if [[ "$new_codecs" = true ]]; then
		audio_codec="libopus"
		# 48000, because Opus only allows certain sampling rates (48000, 24000, 16000, 12000, 8000)
		sampling_rate=48000
	else
		audio_codec="libvorbis"
		sampling_rate=44100
	fi
	
	# Copy the input audio stream if it uses the same codec and the bitrate is smaller or equal to the chosen audio bitrate
	# *1.05 since bitrate isn't an exact business
	# Automatically disabled if trim mode is active
	if [[ "$same_codec" = true && $(bc <<< "$input_audio_bitrate <= $audio_bitrate*1000*1.05") -eq 1 && "$trim_mode" = false ]]; then
		audio_settings="-c:a copy"
	else
		audio_settings="-c:a $audio_codec -ac 2 -ar $sampling_rate -b:a ${audio_bitrate}K"
	fi
}


# Function to calculate important values for the encoding process
# These are all start values and are likely to be replaced later on
calc () {
	video_bitrate=$(bc <<< "($file_size*8*1000/$duration-$audio_bitrate+0.5)/1")
	# Prevents negative bitrates for extreme file size limit / length combos
	if (( video_bitrate <= 0 )); then video_bitrate=50; fi
	bpp=$(bc <<< "scale=3; $video_bitrate*1000/($video_height*$video_width*$frame_rate)")
}


# Function to raise bpp value (quality) of the output webm
# Video bitrate as input to be able to use it with adjusted bitrates as well
downscale () {
	# Resets start values each time downscale is used
	new_video_height=$video_height
	new_frame_rate=$frame_rate
	new_bpp=$bpp
	
	# Reduces output height until bpp value is higher than its threshold or the output height would be smaller than twice its threshold
	# Width is adjusted later on via aspect ratio
	while (( $(bc <<< "$new_bpp < $bcc_threshold") && new_video_height > height_threshold*2 )); do
		(( new_video_height -= 10 ))
		new_bpp=$(bc <<< "scale=3; $1*1000/($new_video_height*$new_video_height*$aspect_ratio*$new_frame_rate)")
		scaling_factor="scale=-1:$new_video_height"
	done
	
	# Reduces frame rate if bpp value is still higher than its threshold
	framedrop
	# Bpp calculation to avoid unnecessary cycle in the following while loop
	new_bpp=$(bc <<< "scale=3; $1*1000/($new_video_height*$new_video_height*$aspect_ratio*$new_frame_rate)")
	
	# Reduce output height further. This time potentially until the height threshold is reached
	while (( $(bc <<< "$new_bpp < $bcc_threshold") && new_video_height > height_threshold )); do
		(( new_video_height -= 10 ))
		new_bpp=$(bc <<< "scale=3; $1*1000/($new_video_height*$new_video_height*$aspect_ratio*$new_frame_rate)")
		scaling_factor="scale=-1:$new_video_height"
	done
}


# Function to reduce frame rate if bpp value is higher than its threshold
# Video bitrate as input to be able to use it with adjusted bitrates as well
framedrop () {
	# Calculates new_bpp if user defined scale used (not done until this point, since downscale would be disabled)
	if [[ "$user_scale" = true ]]; then new_bpp=$(bc <<< "scale=3; $1*1000/($video_height*$video_width*$frame_rate)"); fi
	
	# Reduces frame rate to 24fps if bpp is too low and the input frame rate is higher than 24fps
	# Will not trigger during audio showcase mode, since frame rate is defined as 1
	if (( $(bc <<< "$new_bpp < $bcc_threshold") && $(bc <<< "$frame_rate >= 24") )); then
		new_frame_rate=24
	else 
		new_frame_rate=$frame_rate
	fi
	frame_settings="-r $new_frame_rate"
}


# Function to adjust video bitrate
# Uses a counter as input (only to determine if it's the first try for a bitrate mode)
bitrate () {
	if (( $1 == 1 )); then
		# Each bitrate mode begins with the initially calculated bitrate
		last_video_bitrate=$video_bitrate
		new_video_bitrate=$video_bitrate
	else
		# Video bitrate of the last try is saved in order to be able to compare consecutive attempts
		last_video_bitrate=$new_video_bitrate
		
		# New video bitrate is adjusted based on the output file size
		new_video_bitrate=$(bc <<< "($last_video_bitrate*$file_size*1024*1024/$webm_size+0.5)/1")
		
		# Makes sure that the adjusted bitrate is at least 10% smaller / bigger than the prior one
		difference=$(( last_video_bitrate - new_video_bitrate ))
		if (( $(bc <<< "${difference#-} < $last_video_bitrate*0.1") && difference > 0 )); then
			new_video_bitrate=$(bc <<< "($last_video_bitrate/1.1+0.5)/1")
		elif (( $(bc <<< "${difference#-} < $last_video_bitrate*0.1") && difference < 0 )); then
			new_video_bitrate=$(bc <<< "($last_video_bitrate*1.1+0.5)/1")
		fi
	fi
}


# Function to define which video codec and bitrate mode to use
# Needs number of bitrate mode as input, unless audio showcase mode is active
video () {
	# Sets VP9 or VP8 as the video codec (based on the -n flag)
	if [[ "$new_codecs" = true ]]; then video_codec="libvpx-vp9"; else video_codec="libvpx"; fi
	
	# Defines video settings
	# VBR with minimum quality -> VBR without minimum quality -> CBR
	if [[ "$showcase" = true ]]; then
		video_settings="-c:v $video_codec -crf 10 -qmax 50 -b:v 10M"
	else
		case $1 in
			1) video_settings="-c:v $video_codec -crf 10 -qmax 50 -b:v ${new_video_bitrate}K";;
			2) video_settings="-c:v $video_codec -crf 10 -b:v ${new_video_bitrate}K";;	
			3) video_settings="-c:v $video_codec -minrate:v ${new_video_bitrate}K -maxrate:v ${new_video_bitrate}K -b:v ${new_video_bitrate}K";;
			# Prior 4th bitrate mode. Can force videos in almost any file size limit, but will most likely produce a slide show, as it drops frames
			# 4) video_settings="-c:v $video_codec -bufsize $bufsize -minrate:v ${video_bitrate}K -maxrate:v ${video_bitrate}K -b:v ${video_bitrate}K -skip_threshold 100";;
			*) echo "Unknown bitrate mode!";;
		esac
	fi
}


# Function that contains the actual ffmpeg commands
# Also used to concatenate the filter settings string 
convert () {
	# Combines automatic scale filter with user defined filters
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
	
	# Defines input options for the ffmpeg command
	# Contains infos about the input files and trim settings
	if [[ -n "$showcase_mode" && "$showcase_mode" != "video" ]]; then
		if [[ "$animated_gif" = true ]]; then 
			# "-ignore_loop 0" since ffmpeg disables infinite looping gifs by default
			input_config=(-ignore_loop 0 -i "$picture_path" -ss "$start_time" -i "$input" -map 0:0 -map 1:a:0)
		else
			# "-loop 1" to infinitely loop the input picture to the input audio
			input_config=(-loop 1 -i "$picture_path" -ss "$start_time" -i "$input" -map 0:0 -map 1:a:0 -t "$duration")
		fi
	else 
		if [[ "${input##*.}" = "gif" ]]; then 
			# no trim settings, as they cannot be applied to gifs
			input_config=(-i "$input")
		else
			input_config=(-ss "$start_time" -i "$input" -t "$duration")
		fi
	fi
	
	if [[ "$debug_mode" = true ]]; then
		# Print various variables for debugging purposes
		#echo "Audio factor: $audio_factor"
		#echo "Iteration: $i"
		#echo "First try: $first_try"
		#echo "Best try: $best_try"
		#echo "Best try bitrate: $best_try_bitrate"
		echo "Video settings: $video_settings"
		#echo "Mode counter: $mode_counter"
		#echo "Attempt: $attempt"
		echo "Frame settings: $frame_settings"
		echo "Bpp: $new_bpp"
		#echo "Filters: $filter"
		echo "User scale: $user_scale"
	else
		# gifs need their own ffmpeg commands to avoid VP8 bug
		# alternate reference frame must be specifically disabled (-auto-alt-ref) or ffmpeg will throw an error
		if [[ "$animated_gif" = true || "${input##*.}" = "gif" ]]; then
			if [[ ($(bc <<< "$new_bpp >= 0.075") -eq 1 && "$new_video_bitrate" -ge 400) || "$new_video_bitrate" -ge 2000 ]]; then
				echo -e "\\n\\n\\n"
				[[ -e ffmpeg2pass-0.log ]] || ffmpeg -y -hide_banner "${input_config[@]}" $frame_settings $video_settings -auto-alt-ref 0 -slices 8 -threads 1 -deadline good -cpu-used 5 -an -pass 1 -f webm /dev/null
				echo -e "\\n\\n\\n"
				ffmpeg -y -hide_banner "${input_config[@]}" $frame_settings -pix_fmt yuv420p $video_settings -tune ssim -slices 8 -threads 1 -metadata title="${input%.*}" -auto-alt-ref 0 -deadline good -cpu-used 0 $filter $audio_settings -pass 2 "../done/${input%.*}.webm"
			else
				echo -e "\\n\\n\\n"
				ffmpeg -y -hide_banner "${input_config[@]}" $frame_settings -pix_fmt yuv420p $video_settings -tune ssim -slices 8 -threads 1 -metadata title="${input%.*}" -auto-alt-ref 0 -deadline good -cpu-used 0 $filter $audio_settings "../done/${input%.*}.webm"
			fi
		else
			# 2-pass encoding is only viable for high quality encodes. Therefore minimum bitrate/bpp requirement.
			# A high enough bitrate (and therefore the audio showcase mode) will also activate it
			if [[ ($(bc <<< "$new_bpp >= 0.075") -eq 1 && "$new_video_bitrate" -ge 400) || "$new_video_bitrate" -ge 2000 || -n $showcase_mode ]]; then
				echo -e "\\n\\n\\n"
				[[ -e ffmpeg2pass-0.log ]] || ffmpeg -y -hide_banner "${input_config[@]}" $frame_settings $video_settings -slices 8 -threads 1 -deadline good -cpu-used 5 -an -pass 1 -f webm /dev/null
				echo -e "\\n\\n\\n"
				ffmpeg -y -hide_banner "${input_config[@]}" $frame_settings $video_settings -tune ssim -slices 8 -threads 1 -metadata title="${input%.*}" -auto-alt-ref 1 -lag-in-frames 25 -arnr-maxframes 15 -arnr-strength 3 -deadline good -cpu-used 0 $filter $audio_settings -pass 2 "../done/${input%.*}.webm"
			else
				echo -e "\\n\\n\\n"
				ffmpeg -y -hide_banner "${input_config[@]}" $frame_settings $video_settings -tune ssim -slices 8 -threads 1 -metadata title="${input%.*}" -deadline good -cpu-used 0 $filter $audio_settings "../done/${input%.*}.webm"
			fi
		fi
	fi
}

# Function to define frame rate settings for the audio showcase mode
# Uses a counter as input to determine keyframe interval 
showcaseSettings () {
	# Animated gif detection for auto and manual showcase option
	# "0/0" is the default for static images
	if [[ "$showcase_mode" != "video" ]]; then new_frame_rate=$(ffprobe -v error -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$picture_path"); else new_frame_rate="0/0"; fi
	
	# Main way of reducing the file size for the audio showcase mode
	# Big keyframe intervals can decrease the size of a few minute long video stream to a few hundred KB
	keyframe_interval=$(( 20 * $1 ))
	
	# Activates special gif treatment in case of an animated gif
	# Makes sure that the normal adjuster is used and chooses a new audio bitrate based on the standard formula
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


# Function to summarize the first encoding cycle
initialEncode () {
	if [[ "$showcase" = true ]]; then showcaseSettings 1; fi
	if [[ "$user_scale" = false ]]; then downscale "$video_bitrate"; else framedrop "$video_bitrate"; fi
	bitrate 1
	video 1
	convert
}


# Function to reduce file size for audio showcase webms
showcaseAdjuster () {
	# Determines the output file size via ffprobe. During debug mode the user can enter it manually to test various scenarios
	if [[ "$debug_mode" = true ]]; then echo "Debug mode: Enter webm size." && read -r webm_size; else webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm"); fi
	
	counter=2
	while (( $(bc <<< "$webm_size > $file_size*1024*1024") )); do
		showcaseSettings "$counter"
		convert
		
		if [[ "$debug_mode" = true ]]; then echo "Debug mode: Enter webm size." && read -r webm_size; else webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm"); fi
		
		if (( counter > adjust_iterations*2 )); then 
			echo "File still doesn't fit the specified limit. Please use ffmpeg manually." 
			echo "$input" >> ../too_large.txt
			break
		fi
		
		(( counter += 1 ))
	done
}


# Function to increase the file size if it's smaller than the undershoot limit
# Needs the number of the bitrate mode as input
enhance () {
	i=2
	while (( $(bc <<< "$webm_size > $file_size*1024*1024") || $(bc <<< "$webm_size < $file_size*1024*1024*$undershoot_limit") )); do
		bitrate "$i"
		
		# Only define a new output height if the video is too big or the newly adjusted bitrate is 40% larger than the prior one
		# Using downscale every time would make the produced file size far more unpredictable
		if [[ ($new_video_bitrate -lt $last_video_bitrate || $(bc <<< "$new_video_bitrate > $last_video_bitrate*1.4") -eq 1) && "$user_scale" = false ]]; then downscale "$new_video_bitrate"; else framedrop "$new_video_bitrate"; fi
		
		video "$1"
		convert
		
		if [[ "$debug_mode" = true ]]; then echo "Debug mode: Enter webm size." && read -r webm_size; else webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm"); fi
		
		# Saves settings to reproduce the best try
		# The best try is the biggest file that still doesn't reach the undershoot limit
		if (( webm_size > best_try && $(bc <<< "$webm_size < $file_size*1024*1024") )); then
			best_try=$webm_size
			best_try_bitrate=$new_video_bitrate
			# This variable is later used to determine wheter or not the best try was also the last one
			# If yes the script keeps the file instead of re-encoding the same webm again
			attempt=$i
		fi
		
		# Exits the loop after certain number of tries
		# Either keeps the best try (if it was the last one) or encodes one last webm with the best try's settings
		if (( i > adjust_iterations*2 && attempt <= adjust_iterations*2 )); then
			use_best_try=true
			new_video_bitrate=$best_try_bitrate
			video "$1"
			convert
			break
		elif (( attempt > adjust_iterations*2 )); then
			break
		fi
		
		(( i += 1 ))
	done
}


# Function to decrease the file size if it's bigger than the file size limit
# Needs the number of the bitrate mode as input
limit () {
	# Makes sure the very first encode attempt isn't done twice (already done once in the initialEncode function)
	if (( $1 == 1 )); then start=2; else start=1; fi

	for (( i = start; i <= adjust_iterations; i++ ))
	do
		bitrate "$i"
		
		if [[ $new_video_bitrate -lt $last_video_bitrate && "$user_scale" = false ]]; then downscale "$new_video_bitrate"; else framedrop "$new_video_bitrate"; fi
		
		video "$1"
		convert
		
		if [[ "$debug_mode" = true ]]; then echo "Debug mode: Enter webm size." && read -r webm_size; else webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm"); fi
		
		# Exits the loop during the first bitrate mode, if the output file size is basically the same for 2 consecutive encodes
		# "-qmax 50" will produce a certain minimum file size that cannot be lowered. This statement makes sure that the script switches to the next bitrate mode in such a case
		if (( $1 == 1 && $(bc <<< "$webm_size < $first_try*1.01") && $(bc <<< "$webm_size > $first_try*0.99") )); then break; fi
		
		# Exits the loop as soon as the file size is lower than the file size limit (e.i. no need to lower it further)
		if (( $(bc <<< "$webm_size < $file_size*1024*1024") )); then small_break=true; break; fi
	done
}


# Decide which steps to take based on the webm of the initial encode
adjuster () {
	if [[ "$debug_mode" = true ]]; then echo "Debug mode: Enter webm size." && read -r webm_size; else webm_size=$(ffprobe -v error -show_entries format=size -of default=noprint_wrappers=1:nokey=1 "../done/${input%.*}.webm"); fi
	
	# Sets default values for each file
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
		
		# If the limit function produces a file within the specified file limit, small_break will become true
		# This is done in case, that the file is smaller than the undershoot limit. Otherwise the enhance function would switch to the next bitrate mode instead of trying to raise the file size while using the same mode
		if [[ "$small_break" = false ]]; then (( mode_counter += 1 )); fi
	done
}


####################
# Main script 
####################

# Reads user set flags and additional settings from the command line and assigns values accordingly
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


# Sets default values for unspecified flags/settings
[[ -z $trim_mode ]] && trim_mode=false
[[ -z $audio_mode ]] && audio_mode=false
[[ -z $hq_mode ]] && hq_mode=false
[[ -z $new_codecs ]] && new_codecs=false
[[ -z $file_size ]] && file_size=3
[[ -z $undershoot_limit ]] && undershoot_limit=0.75
[[ -z $adjust_iterations ]] && adjust_iterations=3
# Fail-safe to make sure that a valid showcase mode option was chosen
if [[ -n $showcase_mode ]]; then
	case $showcase_mode in
		auto | manual | video) showcase=true && hq_mode=false;;
		*) echo "Invalid option for audio showcase mode!" && exit;;
	esac
else
	showcase=false
fi


# Sets default conversion variables that are the same for all files
# Might get overwritten in the conversion loop if any corresponding flags are set
audio_bitrate=0
audio_settings="-an"
start_time=0
user_scale=false
height_threshold=180
if [[ "$showcase" = true || "$hq_mode" = true ]]; then bcc_threshold=0.075; else bcc_threshold=0.04; fi
contains "$filter_settings" "scale" && user_scale=true


# Makes sure showcase_pictures/ exists and there are any files in it, if the auto audio showcase mode is active
# Used another for-loop, since wildcard matching doesn't work with test alone
if [[ "$showcase_mode" = "auto" ]]; then
	cd showcase_pictures 2> /dev/null || { echo "No showcase_pictures folder present" && exit; }
	for file in *; do [[ -e "$file" ]] || { echo "No files present in showcase_pictures" && exit; }; break; done
	cd ..
fi
# Changes into sub-directory to avoid file conflicts when converting webms
cd to_convert 2> /dev/null || { echo "No to_convert folder present" && exit; }
# Makes sure there are any files in to_convert/
for file in *; do [[ -e "$file" ]] || { echo "No files present in to_convert" && exit; }; break; done
# Creates sub-directory for the finished webms
mkdir ../done 2> /dev/null


# The main conversion loop
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
	# Removes 2-pass encoding log only right at the end to avoid unnecessary 1st pass encodes
	rm ffmpeg2pass-0.log 2> /dev/null
	# Resets special gif treatment during audio showcase mode in case gifs and normal pictures are mixed
	if [[ "$animated_gif" = true ]]; then animated_gif=false && showcase=true; fi
); done
