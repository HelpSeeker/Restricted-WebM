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
# -) VP9 / Opus support
# -) Vorbis fallback for Opus, when dealing with surround sound
# -) Improve libvpx commands
# -) Multithreading
# -) Include filename in the metadata
# -) Option to disable filters during first pass
# -) Video stream copying
# -) Option to force audio/video trans-/reencoding
# -) Option to force stereo audio
# -) Option to force classic 1 video + 1 audio stream


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Settings
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Default values
size_limit=3
passes=2
audio_bitrate=0
audio_settings="-an"
sub_settings="-sn"
filter_settings=""
min_astream_bitrate=64
astream_count=1

# Default behaviour
use_trim=false
use_audio=false
use_subs=false
mkv_fallback=false

# Initializing variables (don't touch)
file_list=()
vfilters=false
afilters=false
acodec_list=("Vorbis")
vcodec_list=("VP8")

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
	echo -e " -p, --passes <1|2>\tforce single / two-pass encoding (default: 2)"
	echo -e " --start <time>\t\tspecify start time for all input videos in sec."
	echo -e " --end <time>\t\tspecify end time for all input videos in sec."
	echo -e " --subtitles\t\tuse input subtitles (if present)"
	echo -e " --min-audio <bitrate>\tspecify min. audio bitrate in Kbps (default: 64)"
	echo -e " --mkv-fallback\t\tallow usage of MKV for image-based subtitles"
	echo -e ""
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Look for certain substring $2 within a string $1
# If substring is found (e.i. $1 contains the substring) -> Success
contains() {
	case "$1" in 
		*"$2"*) return 0;;
		*) return 1;;
	esac
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

get_video_info() {
	in_duration=$(ffprobe -v error -show_entries format=duration \
					-of default=noprint_wrappers=1:nokey=1 "$input")
	out_duration=$in_duration
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

get_audio_info() {
	for (( i=0; i<100; i++ ))
	do
		index=$(ffprobe -v error -select_streams a:$i -show_entries stream=index \
			-of default=noprint_wrappers=1:nokey=1 "$input")
		if [[ "$index" = "" ]]; then
			astream_count=$i
			break;
		fi
	done
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

get_filter_info() {
	mkdir webm_temp 2> /dev/null

	ffmpeg -loglevel panic -i "$input" -t 1 -map 0:v -c:v copy \
		-filter_complex "$user_filter" "webm_test/video.mkv" || vfilters=true
	ffmpeg -loglevel panic -i "$input" -t 1 -map 0:a? -c:a copy \
		-filter_complex "$user_filter" "webm_test/audio.mkv" || afilters=true
		
	rm -r webm_temp
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
	audio_bitrate=0
	audio_settings=""

	for (( i=0; i<astream_count; i++ ))
	do
		mkdir webm_temp
		
		# Get channel and audio codec info
		channels=$(ffprobe -v error -select_streams a:$i -show_entries stream=channels \
			-of default=noprint_wrappers=1:nokey=1 "$input")
		in_audio_codec=$(ffprobe -v error -select_streams a:$i \
			-show_entries stream=codec_long_name -of default=noprint_wrappers=1:nokey=1 "$input")
		
		# Test for accepted audio codecs
		same_acodec=false			
		for acodec in ${acodec_list[@]}
		do
			contains "$in_audio_codec" "$acodec" && same_acodec=true
		done
		
		# Set audio bitrate
		audio_factor=$(bc <<< "$size_limit*8*1000/($out_duration*5.5*32)")
		if (( audio_factor < 1 )); then
			(( astream_bitrate = 24 * channels ))
		elif (( audio_factor >= 1 && audio_factor < 2 )); then
			(( astream_bitrate = 32 * channels ))
		elif (( audio_factor >= 2 && audio_factor < 7 )); then
			(( astream_bitrate = 48 * channels ))
		elif (( audio_factor >= 7 && audio_factor < 14 )); then
			(( astream_bitrate = 64 * channels ))
		elif (( audio_factor >= 14 && audio_factor < 30 )); then
			(( astream_bitrate = 80 * channels ))
		else
			(( astream_bitrate = 96 * channels ))
		fi
		
		# Ensure that HQ mode gets a higher minimum audio bitrate
		if (( astream_bitrate < min_astream_bitrate )); then 
			astream_bitrate=$min_astream_bitrate
		fi
	
		# Decide between stream copying and trans-/reencoding
		if [[ $same_acodec = true && $afilters = false && $use_trim = false && -z $start_time_all ]]; then
			ffmpeg -loglevel quiet -i "$input" -map 0:a:$i -c:a copy "webm_temp/audio.webm"
			in_astream_bitrate=$(bc <<< "$(ffprobe -v error -show_entries format=bit_rate \
					-of default=noprint_wrappers=1:nokey=1 "webm_temp/audio.webm")/1000")
			
			if (( in_astream_bitrate <= astream_bitrate )); then
				audio_settings="${audio_settings} -c:a:$i copy"
				(( audio_bitrate += in_astream_bitrate ))
			else
				audio_settings="${audio_settings} -c:a:$i libvorbis -b:a:$i ${astream_bitrate}K"
				(( audio_bitrate += astream_bitrate ))
			fi
		else
			audio_settings="${audio_settings} -c:a:$i libvorbis -b:a:$i ${astream_bitrate}K"
			(( audio_bitrate += astream_bitrate ))
		fi
		
		rm -r webm_temp
	done
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Adjust libvpx settings
get_video_settings() {
	video_bitrate=$(bc <<< "$size_limit*8*1000/$out_duration-$audio_bitrate")
	if (( video_bitrate <= 0 )); then video_bitrate=50; fi
	video_settings="-c:v libvpx -b:v ${video_bitrate}K -deadline good"
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
	mkdir webm_temp 2> /dev/null
	
	if [[ $image_subs = true && $mkv_fallback = true ]]; then ext="mkv"; else ext="webm"; fi

	for (( i=passes; i>=1; i-- ))
	do
		if (( i == 2 )); then
			echo "First pass:"
			pass_settings=("-cpu-used" "5" "-pass" "1" "-f" "null" "-")
		elif (( i == 1 && passes == 2 )); then
			echo "Second pass:"
			pass_settings=("-cpu-used" "0" "-pass" "2" "webm_temp/${input%.*}.$ext")
		else
			echo "Only pass:"
			pass_settings=("-cpu-used" "0" "webm_temp/${input%.*}.$ext")
		fi
		
		ffmpeg -loglevel quiet -stats "${input_settings[@]}" $map_settings $video_settings \
			$audio_settings $sub_settings $filter_settings "${pass_settings[@]}"
		echo "~~~~~~~~~~~~~~~~~~"
	done
	
	mv -f "webm_temp/${input%.*}.$ext" "webm_done/${input%.*}.$ext"
	rm -r webm_temp
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Conversion if the input is a video
video_conversion() {
	if [[ ! -e "$input" ]]; then echo "No file $input found. Skipping..."; return; fi
	get_video_info
	get_input_settings
	get_map_settings
	if [[ -n $user_filter ]]; then get_filter_info; get_filter_settings; fi
	if [[ $use_subs = true ]]; then get_sub_info; get_sub_settings; fi
	if [[ $use_audio = true ]]; then get_audio_info; get_audio_settings; fi
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
	-p | --passes) passes=$2; shift 2;;
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

if (( passes != 1 && passes != 2 )); then
	echo "-p/--passes can only be 1 (single pass) or 2 (two-pass). Aborting..."
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
