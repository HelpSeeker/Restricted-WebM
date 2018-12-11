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
# -) VP9
# -) Improve libvpx commands
# -) Multithreading
# -) Include filename in the metadata
# -) Video stream copying
# -) Throw error if the entire audio already exceeds the size limit


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
min_achannel_bitrate=32
max_achannel_bitrate=96
astream_count=1
a_encoder="libvorbis"

# Default behaviour
use_trim=false
use_audio=false
use_subs=false
mkv_fallback=false
no_filter_firstpass=false
force_stereo=false
no_stream_copy=false
basic_format=false

# Initializing variables (don't touch)
file_list=()
vfilters=false
afilters=false
acodec_list=("Vorbis")
vcodec_list=("VP8")

# Error types
image_subs=false
wrong_trim=false
missing_input=false

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
	echo -e " -p, --passes <1|2>\tforce single/two-pass encoding (default: 2)"
	echo -e " -ss, --start <time>\tspecify start time for all input videos in sec."
	echo -e " -to, --end <time>\tspecify end time for all input videos in sec."
	echo -e " -fs, --force-stereo\tforce stereo audio output"
	echo -e " -bf, --basic-format\tlimit the output to max. one video/audio stream"
	echo -e " --opus\t\t\tuse and allow Opus as audio codec"
	echo -e " --subtitles\t\tuse input subtitles (if present)"
	echo -e " --min-audio <bitrate>\tforce min. audio channel bitrate in Kbps (default: 32)"
	echo -e " --max-audio <bitrate>\tforce max. audio channel bitrate in Kbps (default: 96)"
	echo -e " --mkv-fallback\t\tallow usage of MKV for image-based subtitles"
	echo -e " --no-filter-firstpass\tdisable filters during the first pass"
	echo -e " --no-copy\t\tdisable stream copying"
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
	if [[ $basic_format = true ]]; then astream_count=1; fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Test input subtitles
get_sub_info() {
	# Throw error if subtitles can't be converted to webvtt (i.e. they're image-based)
	mkdir webm_temp 2> /dev/null
	ffmpeg -loglevel quiet -i "$input" -t 1 -map 0:s? -c:s webvtt "webm_temp/sub.webm" || image_subs=true
	rm -r webm_temp
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

get_filter_info() {
	mkdir webm_temp 2> /dev/null

	ffmpeg -loglevel panic -i "$input" -t 1 -map 0:v -c:v copy \
		-filter_complex "$user_filter" "webm_temp/video.mkv" || vfilters=true
	ffmpeg -loglevel panic -i "$input" -t 1 -map 0:a? -c:a copy \
		-filter_complex "$user_filter" "webm_temp/audio.mkv" || afilters=true
		
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
	if [[ $use_audio = true && $basic_format = true ]]; then
		map_settings="${map_settings} -map 0:a:0?"
	elif [[ $use_audio = true ]]; then
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
		opus_fail=false
		
		# Test for accepted audio codecs
		same_acodec=false			
		for acodec in ${acodec_list[@]}
		do
			contains "$in_audio_codec" "$acodec" && same_acodec=true
		done
		
		if [[ $force_stereo = true && $channels -gt 2 ]]; then 
			# to ensure to disable stream copying
			same_acodec=false
			channels=2
		fi
		
		if [[ $a_encoder = "libopus" && $channels -gt 2 ]]; then
			ffmpeg -loglevel quiet -i "$input" -t 1 -map 0:a:$i -c:a:$i libopus "webm_temp/opus.webm" || opus_fail=true
		fi
		
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
		if (( astream_bitrate < min_achannel_bitrate * channels )); then 
			(( astream_bitrate = min_achannel_bitrate * channels ))
		elif (( astream_bitrate > max_achannel_bitrate * channels )); then 
			(( astream_bitrate = max_achannel_bitrate * channels ))
		fi
	
		# Decide between stream copying and trans-/reencoding
		if [[ $no_stream_copy = false && $same_acodec = true && $afilters = false && $use_trim = false && -z $start_time_all ]]; then
			ffmpeg -loglevel quiet -i "$input" -map 0:a:$i -c:a copy "webm_temp/audio.webm"
			in_astream_bitrate=$(bc <<< "$(ffprobe -v error -show_entries format=bit_rate \
					-of default=noprint_wrappers=1:nokey=1 "webm_temp/audio.webm")/1000")
			
			if (( in_astream_bitrate <= astream_bitrate )); then
				audio_settings="${audio_settings} -c:a:$i copy"
				(( audio_bitrate += in_astream_bitrate ))
			elif [[ $opus_fail = true ]]; then
				audio_settings="${audio_settings} -c:a:$i libvorbis -b:a:$i ${astream_bitrate}K"
				(( audio_bitrate += astream_bitrate ))
			else
				audio_settings="${audio_settings} -c:a:$i $a_encoder -b:a:$i ${astream_bitrate}K"
				(( audio_bitrate += astream_bitrate ))
			fi
		elif [[ $opus_fail = true ]]; then
			audio_settings="${audio_settings} -c:a:$i libvorbis -b:a:$i ${astream_bitrate}K"
			(( audio_bitrate += astream_bitrate ))
		else
			audio_settings="${audio_settings} -c:a:$i $a_encoder -b:a:$i ${astream_bitrate}K"
			(( audio_bitrate += astream_bitrate ))
		fi
		
		rm -r webm_temp
	done
	
	if [[ $force_stereo = true ]]; then
		audio_settings="${audio_settings} -ac 2"
	fi
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

convert_video() {
	mkdir webm_done 2> /dev/null
	mkdir webm_temp 2> /dev/null
	
	if [[ $image_subs = true && $mkv_fallback = true ]]; then ext="mkv"; else ext="webm"; fi

	for (( i=passes; i>=1; i-- ))
	do
		if (( i == 2 )); then
			if [[ $no_filter_firstpass = true ]]; then filter_settings=""; fi 
			echo "First pass:"
			pass_settings=("-cpu-used" "5" "-pass" "1" "-f" "null" "-")
		elif (( i == 1 && passes == 2 )); then
			if [[ $no_filter_firstpass = true ]]; then get_filter_settings; fi 
			echo "Second pass:"
			pass_settings=("-cpu-used" "0" "-pass" "2" "webm_temp/${input%.*}.$ext")
		else
			echo "Only pass:"
			pass_settings=("-cpu-used" "0" "webm_temp/${input%.*}.$ext")
		fi
		
		ffmpeg -loglevel panic "${input_settings[@]}" $map_settings \
			-c:a pcm_s16le -c:v rawvideo -c:s copy $filter_settings -f nut - | \
		ffmpeg -loglevel quiet -stats -i - $video_settings $audio_settings $sub_settings "${pass_settings[@]}"
		echo "~~~~~~~~~~~~~~~~~~"
	done
	
	mv -f "webm_temp/${input%.*}.$ext" "webm_done/${input%.*}.$ext"
	rm -r webm_temp
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Conversion if the input is a video
video_conversion() {
	if [[ ! -e "$input" ]]; then missing_input=true; echo "No file $input found. Skipping..."; return; fi
	get_video_info
	get_input_settings
	get_map_settings
	if [[ -n $user_filter ]]; then get_filter_info; get_filter_settings; fi
	if [[ $use_subs = true ]]; then get_sub_info; get_sub_settings; fi
	if [[ $use_audio = true ]]; then get_audio_info; get_audio_settings; fi
	get_video_settings
	
	if [[ $image_subs = true && $mkv_fallback = false ]]; then return; 
	elif [[ $wrong_trim = true ]]; then return; fi
	convert_video
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
		echo -e "\t c) Start time greater than end time\n"
		} >> webm.log
	fi
	
	if [[ $missing_input = true ]]; then
		{
		echo -e "Error occured for:\n$input"
		echo -e "\n\tFile not found.\n"
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
	-f | --filter) user_filter="$2"; shift 2;;
	-p | --passes) passes=$2; shift 2;;
	-ss | --start) start_time_all=$2; shift 2;;
	-to | --end) end_time_all=$2; shift 2;;
	-fs | --force-stereo) force_stereo=true; shift;;
	-bf | --basic-format) basic_format=true; shift;;
	--opus) acodec_list+=("Opus"); a_encoder="libopus"; shift;;
	--subtitles) use_subs=true; shift;;
	--min-audio) min_achannel_bitrate=$2; shift 2;;
	--max-audio) max_achannel_bitrate=$2; shift 2;;
	--mkv-fallback) mkv_fallback=true; shift;;
	--no-filter-firstpass) no_filter_firstpass=true; shift;;
	--no-copy) no_stream_copy=true; shift;;
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

# Check start/end time validity
# Individual trim settings get checked in get_input_settings
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

# Make sure only 1 and 2 passes are accepted as input
if (( passes != 1 && passes != 2 )); then
	echo "-p/--passes can only be 1 (single pass) or 2 (two-pass). Aborting..."
	exit
fi

if [[ -z "$user_filter" ]]; then no_filter_firstpass=false; fi	

# Vorbis doesn't support lower bitrate
# Needs additional test for Opus (as it can go lower)
if (( max_achannel_bitrate < 24 )); then
	echo "Max. audio channel bitrate is too low for Vorbis. Aborting..."
	exit
fi

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Main conversion loop
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
