#!/bin/bash

# Catch user interrupt (Ctrl+C)
trap keyboard_interrupt SIGINT SIGQUIT SIGTERM

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Default settings
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Common user settings
declare -i verbosity=1
declare audio=false
declare size_limit=3
declare -i passes=2
declare undershoot=0.75
declare -i iterations=3
declare -i threads=1
declare force_stereo=false
declare basic_format=false

declare subtitles=false
declare mkv_fallback=false
declare burn_subs=false

declare v_codec="libvpx"
declare crf=false
declare no_qmax=false
declare bpp_thresh=0.075
declare transparency=false
declare pix_fmt="yuv420p"
declare -i min_height=240
declare min_fps=24

declare a_codec="libvorbis"
declare no_copy=false
declare force_copy=false
declare -i min_audio=24

declare no_filter_firstpass=false
declare ffmpeg_verbosity="stats"
declare color=true
declare debug=false

# Advanced user settings
declare -ria fps_list=(60 30 25 24 22 20 18 16 14 12 10 8 6 4 2 1)
declare -ri  audio_test_dur=60      # 0 for whole stream -> exact bitrate
declare -ri  fallback_bitrate=1     # Must be >0
declare -ri  height_reduction=10
declare -ri  min_quality=50
declare -ri  crf_value=10
declare -r   min_bitrate_ratio=0.9
declare -r   skip_limit=0.01
declare -r   audio_factor=5.5
declare -r   fallback_codec="libvorbis"
declare -r   out_dir_name="webm_done"
# Randomize temp name to allow several instances to run at the same time
declare -r   random_name="$(date +%s_%N)_$RANDOM"
declare -r   ffmpeg_log_prefix="$random_name"
declare -r   temp_name="$random_name"
declare -r   input_info="${random_name}_in.json"
declare -r   output_info="${random_name}_out.json"


# Initializations, which shouldn't be touched
declare -a input_list
declare audio_filters=false
declare video_filters=false

# ANSI escape codes for color output
# See https://en.wikipedia.org/wiki/ANSI_escape_code
declare -r color_current_input='\033[0;35m'
declare -r color_attempt_info='\033[0;32m'
declare -r color_verbose_header='\033[1;36m'
declare -r color_general_settings=$color_current_input
declare -r color_attempt_settings=$color_attempt_info
declare -r color_size_infos=$color_attempt_info
declare -r reset_color='\033[0m'

# Error codes
# 1 -> missing required software
# 2 -> invalid user-specified option
# 3 -> misc. runtime error (missing function argument, unknown value in case, etc.)
# 4 -> not all input coubs exist after execution (i.e. some downloads failed)
# 5 -> termination was requested mid-way by the user (i.e. Ctrl+C)
declare -ri missing_dep=1
declare -ri err_option=2
declare -ri err_runtime=3
declare -ri err_size=4
declare -ri user_interrupt=5
declare size_fail=false

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Print to stderr
function err() {
    cat <<< "$@" 1>&2
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Print help text
function usage() {
cat << EOF
Usage: ${0##*/} [OPTIONS] INPUT [INPUT]...

Input:
  Absolute or relative path to a video/image

Common options:
  -h,  --help               show help
  -q,  --quiet              suppress non-error output
  -v,  --verbose            print verbose information
  -a,  --audio              enable audio output
  -s,  --size SIZE          limit max. output file size in MB (def: $size_limit)
  -f,  --filters FILTERS    use custom ffmpeg filters
  -p,  --passes {1,2}       specify number of passes (def: $passes)
  -u,  --undershoot RATIO   specify undershoot ratio (def: $undershoot)
  -i,  --iterations ITER    iterations for each bitrate mode (def: $iterations)
  -t,  --threads THREADS    enable multithreading
  -ss, --start TIME         start encoding at the specified time
  -to, --end TIME           end encoding at the specified time
  -fs, --force-stereo       force stereo audio output
  -bf, --basic-format       restrict output to one video/audio stream

Subtitle options:
  --subtitles               enable subtitle output
  --mkv-fallback            allow usage of MKV for image-based subtitles
  --burn-subs               discard soft subtitles after hardsubbing

Advanced video options:
  --vp9                     use VP9 instead of VP8
  --crf                     use constrained quality instead of VBR
  --no-qmax                 skip the first bitrate mode (VBR with qmax)
  --bpp BPP                 set custom bpp threshold (def: $bpp_thresh)
  --transparency            preserve input transparency
  --pix-fmt FORMAT          choose color space (def: $pix_fmt)
  --min-height HEIGHT       force min. output height (def: $min_height)
  --max-height HEIGHT       force max. output height
  --min-fps FPS             force min. frame rate (def: $min_fps)
  --max-fps FPS             force max. frame rate

Advanced audio options:
  --opus                    use and allow Opus as audio codec
  --no-copy                 disable stream copying
  --force-copy              force-copy compatible (!) audio streams
  --min-audio RATE          force min. channel bitrate in Kbps (def: $min_audio)
  --max-audio RATE          force max. channel bitrate in Kbps

Misc. options:
  --no-filter-firstpass     disable user filters during the first pass
  --ffmpeg-verbosity LEVEL  change FFmpeg command verbosity (def: $ffmpeg_verbosity)
  --no-color                disable colorized output
  --debug                   only print ffmpeg commands

All output will be saved in '$out_dir_name/'.
'$out_dir_name/' is located in the same directory as the input.

For more information visit:
https://github.com/HelpSeeker/Restricted-WebM-in-Bash/wiki
EOF
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# check existence of required software
function check_requirements() {
    local -a dependencies=("ffmpeg" "ffprobe" "bc" "jq" "grep" "awk")
    local dep

    for dep in "${dependencies[@]}"
    do
        if ! command -v "$dep" &> /dev/null; then
            err "Error: $dep not found!"
            exit $missing_dep
        fi
    done
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Parse command line arguments
function parse_options() {
    while [[ "$1" ]]
    do
        case "$1" in
        # Common options
        -h  | --help)         usage; exit 0;;
        -q  | --quiet)        verbosity=0; shift;;
        -v  | --verbose)      verbosity=2; shift;;
        -a  | --audio)        audio=true; shift;;
        -s  | --size)         size_limit="$2"; shift 2;;
        -f  | --filters)      declare -gr user_filters="$2"; shift 2;;
        -p  | --passes)       passes="$2"; shift 2;;
        -u  | --undershoot)   undershoot="$2"; shift 2;;
        -i  | --iterations)   iterations="$2"; shift 2;;
        -t  | --threads)      threads="$2"; shift 2;;
        -ss | --start)        declare -g global_start;
                              global_start="$(parse_time $2)";
                              (( $? == err_option )) && exit $err_option
                              shift 2;;
        -to | --end)          declare -g global_end;
                              global_end="$(parse_time $2)";
                              (( $? == err_option )) && exit $err_option
                              shift 2;;
        -fs | --force-stereo) force_stereo=true; shift;;
        -bf | --basic-format) basic_format=true; shift;;
        # Subtitle options
        --subtitles)           subtitles=true; shift;;
        --mkv-fallback)        mkv_fallback=true; shift;;
        --burn-subs)           subtitles=true; burn_subs=true; shift;;
        # Advanced video options
        --vp9)                 v_codec="libvpx-vp9"; shift;;
        --crf)                 crf=true; shift;;
        --no-qmax)             no_qmax=true; shift;;
        --bpp)                 bpp_thresh="$2"; shift 2;;
        --transparency)        transparency=true; pix_fmt="yuva420p"; shift;;
        --pix-fmt)             pix_fmt="$2"; shift 2;;
        --min-height)          min_height="$2"; shift 2;;
        --max-height)          declare -gir max_height="$2"; shift 2;;
        --min-fps)             min_fps="$2"; shift 2;;
        --max-fps)             declare -gr max_fps="$2"; shift 2;;
        # Advanced audio options
        --opus)                a_codec="libopus"; shift;;
        --no-copy)             no_copy=true; shift;;
        --force-copy)          force_copy=true; shift;;
        --min-audio)           min_audio="$2"; shift 2;;
        --max-audio)           declare -gir max_audio="$2"; shift 2;;
        # Misc. options
        --no-filter-firstpass) no_filter_firstpass=true; shift;;
        --ffmpeg-verbosity)    ffmpeg_verbosity="$2"; shift 2;;
        --no-color)            color=false; shift;;
        --debug)               debug=true; shift;;
        # Files and unknown arguments
        -*) err "Unknown flag '$1'!"; usage; exit $err_option;;
        *)  if [[ -f "$1" ]]; then
                input_list+=("$(readlink -f "$1")")
            else
                err "'$1' is no valid file."
            fi
            shift;;
        esac
    done
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Parse input time syntax and check for validity
# $1: Timecode
function parse_time() {
    [[ -z "$1" ]] && \
        { err "Missing timecode in parse_time!"; exit $err_runtime; }
    local time="$1"

    # Check FFmpeg support
    # Easiest to just test it with ffmpeg (reasonable fast even for >1h durations)
    if ! ffmpeg -v quiet -f lavfi -i anullsrc \
            -t "$time" -c copy -f null -; then
        err "Invalid time ('$1')! For the supported syntax see:"
        err "https://ffmpeg.org/ffmpeg-utils.html#time-duration-syntax"
        exit $err_option
    fi

    sec=$(awk -F: '{
            if(NF==3)
                printf("%.3f\n", 3600*$1 + 60*$2 + $3);
            else if(NF==2)
                printf("%.3f\n", 60*$1 + $2);
            else if(NF==1)
                printf("%.3f\n", $1);
            }' <<< "$time")

    echo "$sec"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Check validity of float values
# $1: To be checked option
function invalid_number() {
    [[ -z $1 ]] && \
        { err "Missing input option in invalid_number!"; exit $err_runtime; }
    local var=$1

    # check if var starts with a number
    # also weeds out chars that bc interprets as number
    case $var in
    [0-9]*);;
    *) return 0;;
    esac

    # check if bc accepts var as input
    # bc's return value doesn't indicate failure for standard_in errors
    bc <<< "$var" |& grep -q error && return 0

    return 1
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Check validity of command line options
function check_options() {
    # General float value check
    # Integer checking done by the arithmetic evaluation during assignment
    if invalid_number $size_limit; then
        err "Invalid size limit ('$size_limit')!"
        exit $err_option
    elif [[ -n $global_start ]] && invalid_number $global_start; then
        err "Invalid start time ('$global_start')!"
        exit $err_option
    elif [[ -n $global_end ]] && invalid_number $global_end; then
        err "Invalid end time ('$global_end')!"
        exit $err_option
    elif invalid_number $undershoot; then
        err "Invalid undershoot ('$undershoot')!"
        exit $err_option
    elif invalid_number $bpp_thresh; then
        err "Invalid bpp threshold ('$bpp_thresh')!"
        exit $err_option
    elif invalid_number $min_fps; then
        err "Invalid min. frame rate ('$min_fps')!"
        exit $err_option
    elif [[ -n $max_fps ]] && invalid_number $max_fps; then
        err "Invalid max. frame rate ('$max_fps')!"
        exit $err_option
    fi

    # Special integer checks
    if (( passes != 1 && passes != 2 )); then
        err "Only 1 or 2 passes are supported!"
        exit $err_option
    elif (( iterations < 1 )); then
        err "Script needs at least 1 iteration per mode!"
        exit $err_option
    elif (( min_height <= 0 )); then
        err "Min. height must be greater than 0!"
        exit $err_option
    elif [[ -n $max_height ]] && (( max_height < min_height )); then
        err "Max. height can't be less than min. height!"
        exit $err_option
    elif (( threads <= 0 )); then
        err "Thread count must be larger than 0!"
        exit $err_option
    elif (( threads > 16 )); then
        # Just a warning
        err "More than 16 threads are not recommended."
    elif [[ -n $max_audio ]] && (( max_audio < 6 )); then
        err "Max. audio channel bitrate must be greater than 6 Kbps!"
        exit $err_option
    elif [[ -n $max_audio ]] && (( max_audio < min_audio )); then
        err "Max. audio channel bitrate can't be less than min. audio channel bitrate!"
        exit $err_option
    fi

    # Special float checks
    # Negative values not possible after general float check
    # To avoid confusion "<= 0" is used instead of "== 0"
    if (( $(bc <<< "$size_limit <= 0") )); then
        err "Target file size must be greater than 0!"
        exit $err_option
    elif [[ -n $global_end ]] && (( $(bc <<< "$global_end <= 0") )); then
        err "End time must be greater than 0!"
        exit $err_option
    elif [[ -n $global_start && -n $global_end ]] && \
         (( $(bc <<< "$global_end <= $global_start") )); then
        err "End time must be greater than start time!"
        exit $err_option
    elif (( $(bc <<< "$undershoot > 1") )); then
        err "Undershoot ratio can't be greater than 1!"
        exit $err_option
    elif (( $(bc <<< "$bpp_thresh <= 0") )); then
        err "Bits per pixel threshold must be greater than 0!"
        exit $err_option
    elif [[ -n $max_fps ]] && (( $(bc <<< "$max_fps < 1") )); then
        err "Max. frame rate can't be less than 1!"
        exit $err_option
    elif [[ -n $max_fps ]] && (( $(bc <<< "$max_fps < $min_fps") )); then
        err "Max. frame rate can't be less than min. frame rate!"
        exit $err_option
    fi

    # Check for mutually exclusive flags
    if [[ $force_copy == true && $no_copy == true ]]; then
        err "--force-copy and --no-copy are mutually exclusive!"
        exit $err_option
    fi

    # Misc. checks
    if (( ${#input_list[@]} == 0 )); then
        err "No input files specified!"
        exit $err_option
    elif [[ $transparency == true && $pix_fmt != "yuva420p" ]]; then
        err "Only yuva420p supports transparency!"
        exit $err_option
    fi

    if [[ $v_codec == "libvpx" ]]; then
        case "$pix_fmt" in
        yuv420p | yuva420p) ;;
        *) err "'$pix_fmt' isn't supported by VP8!"
           err "See 'ffmpeg -h encoder=libvpx' for more infos."
           exit $err_option;;
        esac
    elif [[ $v_codec == "libvpx-vp9" ]]; then
        case "$pix_fmt" in
        yuv420p | yuva420p | \
        yuv422p | yuv440p | yuv444p | \
        yuv420p10le | yuv422p10le | yuv440p10le | yuv444p10le | \
        yuv420p12le | yuv422p12le | yuv440p12le | yuv444p12le | \
        gbrp | gbrp10le | gbrp12le) ;;
        *) err "'$pix_fmt' isn't supported by VP9!"
           err "See 'ffmpeg -h encoder=libvpx-vp9' for more infos."
           exit $err_option;;
        esac
    fi

    case "$ffmpeg_verbosity" in
    stats) ;;
    quiet | panic | fatal | \
    error | warning | info | \
    verbose | debug | trace) ;;
    *) err "'$ffmpeg_verbosity' isn't a supported FFmpeg verbosity level!"
       err "Supported levels:"
       err "  stats quiet panic fatal error warning info verbose debug trace"
       exit $err_option;;
    esac
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Test user set filters
function check_user_filters() {
    [[ -z "$user_filters" ]] && return

    # existing filters let copy fail
    # only crude test; stream specifiers will let it fail as well
    if ! ffmpeg -v quiet -f lavfi -i nullsrc -f lavfi -i anullsrc -t 1 \
            -c:v copy -filter_complex "$user_filters" -f null -; then
        video_filters=true
    fi
    if ! ffmpeg -v quiet -f lavfi -i nullsrc -f lavfi -i anullsrc -t 1 \
            -c:a copy -filter_complex "$user_filters" -f null -; then
        audio_filters=true
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Print all settings for verbose output
function print_options() {
    [[ $color == true ]] && printf "$color_verbose_header"
    printf "\n### Settings for the current session ###\n\n"
    printf "$reset_color"
cat << EOF
Paths:
  Temporary filename:          $temp_name
  Info JSON name:              $input_info $output_info
  Destination directory name:  $out_dir_name/

Size:
  Max. size (MB):              $size_limit
  Undershoot ratio:            $undershoot
  Max. size (Bytes):           $max_size
  Min. size (Bytes):           $min_size

Trimming:
  Start time (sec):            $global_start
  End time (sec):              $global_end

Video:
  Encoder:                     $v_codec
  Passes:                      $passes
  Threads:                     $threads
  Color space:                 $pix_fmt
  Use CQ instead of VBR:       $crf
  CRF:                         $crf_value
  qmax:                        $min_quality
  Fallback bitrate (Kbps):     $fallback_bitrate
  Omit min. quality qmax:      $no_qmax
  Iterations/bitrate mode:     $iterations
  Mode skip threshold:         $skip_limit
  Min. bitrate ratio:          $min_bitrate_ratio

Audio:
  Audio output:                $audio
  Encoder:                     $a_codec
  Fallback encoder:            $fallback_codec
  Force stereo:                $force_stereo
  Min. channel bitrate (Kbps): $min_audio
  Max. channel bitrate (Kbps): $max_audio
  Stream copying disabled:     $no_copy
  Ignore bitrate for copying:  $force_copy
  Bitrate test duration (sec): $audio_test_dur
  Audio factor:                $audio_factor

Subtitles:
  Subtitle support:            $subtitles
  MKV as fallback:             $mkv_fallback
  Discard after hardsubbing:   $burn_subs

Filters:
  User filters:                $user_filters
  Contains video filters:      $video_filters
  Contains audio filters:      $audio_filters
  Omit during 1st pass:        $no_filter_firstpass
  BPP threshold:               $bpp_thresh
  Min. height threshold:       $min_height
  Max. height threshold:       $max_height
  Height reduction step:       $height_reduction
  Min. frame rate threshold:   $min_fps
  Max. frame rate threshold:   $max_fps
  Possible frame rates:        ${fps_list[@]}

Misc.:
  Only 1 video/audio stream:   $basic_format
  FFmpeg verbosity level:      $ffmpeg_verbosity
  Debug mode:                  $debug
EOF
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Print general (i.e. not adjusted during iterations) settings
function print_general_settings() {
    [[ $color == true ]] && printf "$color_general_settings"
cat << EOF
  Verbosity:  ${verbosity_settings[@]}
  Input/trim: ${input_settings[@]}
  Mapping:    ${map_settings[@]}
  Audio:      ${audio_settings[@]}
  Subtitles:  ${subtitle_settings[@]}
  Output:     $output

EOF
    printf "$reset_color"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Print attempt (i.e. adjusted during iterations) settings
function print_attempt_settings() {
    [[ $color == true ]] && printf "$color_attempt_settings"
cat << EOF
  Video:      ${video_settings[@]}
  Filters:    ${filter_settings[@]}
EOF
    printf "$reset_color"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Print size information
function print_size_infos() {
    [[ $color == true ]] && printf "$color_size_infos"
cat << EOF
  Curr. size: $temp_size
  Last size:  $last_size
  Best try:   $out_size

EOF
    printf "$reset_color"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Handle output path
# $1: Absolute path of an input file
function resolve_paths() {
    [[ -z "$1" ]] && \
        { err "Missing input path in resolve_paths!"; \
          clean; exit $err_runtime; }
    [[ -z "$2" ]] && \
        { err "Missing extension in resolve_paths!"; clean; exit $err_runtime; }
    local file="$1"
    local ext="$2"

    local in_name="$(basename "$file")"
    in_name="${in_name%.*}"
    local in_dir="$(dirname "$file")"
    local out_name="$in_name.$ext"
    local out_dir="$in_dir/$out_dir_name"

    if [[ $in_name == "$temp_name" ]]; then
        err "$file"
        err "Error! Input has reserved filename ('$temp_name')."
        exit $err_runtime
    fi

    mkdir -p "$out_dir"
    if ! cd "$out_dir"; then
        err "Can't change into '$out_dir'!"
        exit $err_runtime
    fi

    declare -g output="$out_dir/$out_name"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Decide if input audio stream should be copied
# $1: Absolute path of an input file
# $2: Stream selector
# $3: Output audio bitrate
function audio_copy() {
    [[ -z "$1" ]] && \
        { err "Missing input path in audio_copy!"; clean; exit $err_runtime; }
    [[ -z  $2  ]] && \
        { err "Missing stream selector in audio_copy!"; \
          clean; exit $err_runtime; }
    [[ -z  $3  ]] && \
        { err "Missing output audio bitrate in audio_copy!"; \
          clean; exit $err_runtime; }
    local file="$1"
    local -i stream=$2
    local -i out_rate=$3

    [[ -n $global_start || $audio_filters == true || $no_copy == true ]] && \
        return 1

    # Shorter values speed up test, but only approximate avg. bitrate
    # 0 will copy entire audio stream -> exact
    local -a copy_dur=()
    (( audio_test_dur > 0 )) && copy_dur=("-t" "$audio_test_dur")

    ffmpeg -y -v error -i "$file" "${copy_dur[@]}" \
            -map 0:a:$stream -c copy "$temp_name.mkv"
    ffprobe -v error -show_format -show_streams \
            -print_format json "$temp_name.mkv" > "$output_info"
    local -i in_rate=$(jq -r .format.bit_rate "$output_info")
    local in_codec=$(jq -r .streams[0].codec_name "$output_info")

    local allowed_codec=false
    local -a codec_list=("vorbis")
    [[ $a_codec == "libopus" ]] && codec_list+=("opus")
    for codec in "${codec_list[@]}"
    do
        [[ $codec == "$in_codec" ]] && { allowed_codec=true; break; }
    done

    # *1.05 since bitrate allocation is no exact business
    if [[ $allowed_codec == true ]] && \
       ( [[ $force_copy == true ]] || \
         (( $(bc <<< "$in_rate <= $out_rate*1000*1.05/1") )) ); then
       return 0
    fi

    return 1
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Test if audio fallback encoder is necessary
# $1: Absolute path of an input file
# $2: Stream selector
function opus_fallback() {
    [[ -z "$1" ]] && \
        { err "Missing input path in opus_fallback!"; \
          clean; exit $err_runtime; }
    [[ -z  $2  ]] && \
        { err "Missing stream selector in opus_fallback!"; \
          clean; exit $err_runtime; }
    local file="$1"
    local -i stream=$2

    [[ $force_stereo == true ]] && return 1

    # Certain channel configurations will throw an error
    # See: https://trac.ffmpeg.org/ticket/5718
    if ! ffmpeg -v quiet -i "$file" -t 1 \
            -map 0:a:$stream -c:a libopus -f null -; then
        return 0
    else
        return 1
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Test if output would include image-based subtitles
# $1: Absolute path of an input file
function output_image_subtitles() {
    [[ -z "$1" ]] && \
        { err "Missing input path in output_image_subtitles!"; \
          clean; exit $err_runtime; }
    local file="$1"

    [[ $subtitles == false ]] && return 1
    [[ $burn_subs == true ]] && return 1

    # FFmpeg only supports text->text and bitmap->bitmap conversions
    # bitmap->text in general is a complex topic
    if ! ffmpeg -v quiet -i "$file" -t 1 \
            -map 0:s? -c:s webvtt -f null -; then
        return 0
    else
        return 1
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Calculate values regarding trim settings
# $1: Absolute path of an input file
function calculate_trim_values() {
    [[ -z "$1" ]] && \
        { err "Missing input path in calculate_trim_values!"; \
          clean; exit $err_runtime; }
    local file="$1"

    declare -gA trim_values=()

    local duration=$(jq -r .format.duration "$input_info")

    # Brute-force detect, if ffprobe can't get duration (i.e. GIFs or other images)
    # Encodes input as AVC (fast) and reads duration from the output
    if [[ $duration = "null" ]]; then
        ffmpeg -y -v error -i "$file" -map 0:v -c:v libx264 \
            -preset ultrafast -crf 51 "$temp_name.mkv"
        ffprobe -v error -show_format -show_streams \
            -print_format json "$temp_name.mkv" > "$output_info"
        duration=$(jq -r .format.duration "$output_info")
    fi

    local start=0
    local end=$duration

    if [[ -n $global_start ]] && \
       (( $(bc <<< "$global_start < $duration") )); then
        start=$global_start
    fi
    if [[ -n $global_end ]] && \
       (( $(bc <<< "$global_end <= $duration") )); then
        end=$global_end
    fi
    declare -g trim_values[dur]=$(bc -l <<< "scale=3; ($end-$start)/1")
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Calculate values regarding audio settings
# $1: Max. output size in Bytes
# $2: Output duration
function calculate_audio_values() {
    [[ -z $1 ]] && \
        { err "Missing max. size in calculate_audio_values!"; \
          clean; exit $err_runtime; }
    [[ -z $2 ]] &&
        { err "Missing output duration in calculate_audio_values!"; \
          clean; exit $err_runtime; }
    local -i size=$1
    local duration=$2

    declare -giA audio_values=()
    declare -g audio_values[bitrate]=0
    declare -g audio_values[streams]=0
    declare -g audio_values[channels]=0
    # 44100 is an arbitrary value to check later change
    declare -g audio_values[rate]=44100

    [[ $audio == false ]] && return

    local -i streams=$(jq -r .format.nb_streams "$input_info")
    local -i channels=''
    for (( i=0; i < streams; i++ ))
    do
        if [[ $(jq -r .streams[$i].codec_type "$input_info") == "audio" ]]; then
            if [[ $force_stereo == true ]]; then
                channels=2
            else
                channels=$(jq -r .streams[$i].channels "$input_info")
            fi
            declare -g audio_values[${audio_values[streams]}]=$channels
            audio_values[channels]+=$channels
            (( audio_values[streams]++ ))
            [[ $basic_format == true ]] && break
        fi
    done

    # formula originally based on my experience with stereo audio for 4MB WebMs
    # later on extended to accommodate more bitrates / channels
    local formula="$size*8/($duration*$audio_factor*${audio_values[channels]}*4*1000)"
    local -i factor=$(bc <<< "$formula")
    local -i channel_bitrate
    if (( factor < 1 )); then
        channel_bitrate=6
    elif (( factor < 2 )); then
        channel_bitrate=8
    elif (( factor < 3 )); then
        channel_bitrate=12
    elif (( factor < 4 )); then
        channel_bitrate=16
    elif (( factor < 6 )); then
        channel_bitrate=24
    elif (( factor < 8 )); then
        channel_bitrate=32
    elif (( factor < 28 )); then
        channel_bitrate=48
    elif (( factor < 72 )); then
        channel_bitrate=64
    elif (( factor < 120 )); then
        channel_bitrate=80
    else
        channel_bitrate=96
    fi

    (( channel_bitrate < min_audio )) && channel_bitrate=$min_audio
    if [[ -n $max_audio ]] && (( channel_bitrate > max_audio )); then
        channel_bitrate=$max_audio
    fi

    for (( i=0; i < audio_values[streams]; i++ ))
    do
        (( audio_values[$i]*=channel_bitrate ))
        audio_values[bitrate]+=${audio_values[$i]}
    done

    # Downsample necessary for lower bitrates with libvorbis
    if (( channel_bitrate <= 6 )); then
        audio_values[rate]=8000
    elif (( channel_bitrate <= 12 )); then
        audio_values[rate]=12000
    elif (( channel_bitrate <= 16 )); then
        audio_values[rate]=24000
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Calculate values regarding video settings
# $1: Max. output size in Bytes
# $2: Output duration
# $3: Output audio bitrate
function calculate_video_values() {
    [[ -z $1 ]] && \
        { err "Missing max. size in calculate_video_values!"; \
          clean; exit $err_runtime; }
    [[ -z $2 ]] && \
        { err "Missing output duration in calculate_video_values!"; \
          clean; exit $err_runtime; }
    [[ -z $3 ]] && \
        { err "Missing audio bitrate in calculate_video_values!"; \
          clean; exit $err_runtime; }
    local -i size=$1
    local duration=$2
    local -i audio=$3

    declare -gA video_values=()

    local formula="$size*8/($duration*1000)-$audio"
    declare -gi video_values[bitrate]=$(bc -l <<< "scale=0; $formula")
    (( video_values[bitrate] <= 0 )) && \
        video_values[bitrate]=$fallback_bitrate
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Calculate values regarding (script) filter settings
# $1: Absolute path of an input file
# $2: Video bitrate
function calculate_filter_values() {
    [[ -z "$1" ]] && \
        { err "Missing input file in calculate_filter_values!"; \
          clean; exit $err_runtime; }
    [[ -z  $2  ]] && \
        { err "Missing video bitrate in calculate_filter_values!"; \
          clean; exit $err_runtime; }
    local file="$1"
    local -i bitrate=$2

    # Test for user set scale/fps filter
    local user_scale=false
    local user_fps=false
    case "$user_filters" in (*scale*) user_scale=true;; esac
    case "$user_filters" in (*fps*) user_fps=true;; esac

    local -i height=$(jq -r .streams[0].height "$input_info")
    local -i width=$(jq -r .streams[0].width "$input_info")
    local aspect_ratio=$(bc -l <<< $width/$height)
    local fps=$(bc -l <<< "scale=3; $(jq -r .streams[0].r_frame_rate "$input_info")")
    local bpp=''

    # If user scale/fps filter -> test encode
    # Read the effect (i.e. changed resolution / frame rate) from output
    if [[ $user_scale == true || $user_fps == true ]]; then
        ffmpeg -y -v error -i "$file" -vframes 1 \
            -filter_complex "$user_filters" "$temp_name.mkv"
        ffprobe -v error -show_format -show_streams \
            -print_format json "$temp_name.mkv" > "$output_info"
        height=$(jq -r .streams[0].height "$output_info")
        width=$(jq -r .streams[0].width "$output_info")
        aspect_ratio=$(bc -l <<< $width/$height)
        fps=$(bc -l <<< "scale=3; $(jq -r .streams[0].r_frame_rate "$output_info")")
    fi

    declare -gA filter_values=()
    declare -g filter_values[in_height]=$height
    declare -g filter_values[out_height]=$height
    declare -g filter_values[in_fps]=$fps
    declare -g filter_values[out_fps]=$fps

    [[ $user_scale == true && $user_fps == true ]] && return

    # Perform frame rate drop
    for i in "${fps_list[@]}"
    do
        [[ $user_fps == true ]] && break

        bpp=$(bc -l <<< "scale=3; $bitrate*1000/($fps*$aspect_ratio*$height^2)")
        (( $(bc -l <<< "scale=3; $bpp >= $bpp_thresh/2") )) && break
        fps=$i
    done

    # Enfore frame rate thresholds
    (( $(bc <<< "$fps < $min_fps") )) && fps=$min_fps
    [[ -n $max_fps ]] && (( $(bc <<< "$fps > $max_fps") )) && fps=$max_fps
    (( $(bc <<< "$fps > ${filter_values[in_fps]}") )) && \
        fps=${filter_values[in_fps]}
    filter_values[out_fps]=$fps

    # Perform downscale
    while true
    do
        [[ $user_scale == true ]] && break

        bpp=$(bc -l <<< "scale=3; $bitrate*1000/($fps*$aspect_ratio*$height^2)")
        (( $(bc <<< "$bpp >= $bpp_thresh") )) && break
        (( height-=height_reduction ))
    done
    # Enforce height thresholds
    (( height < min_height )) && height=$min_height
    [[ -n $max_height ]] && (( height > max_height )) && height=$max_height
    (( height > filter_values[in_height] )) && \
        height=${filter_values[in_height]}
    filter_values[out_height]=$height
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Assemble FFmpeg settings regarding verbosity
function get_verbosity_settings() {
    declare -ga verbosity_settings=()
    if [[ $ffmpeg_verbosity == "stats" ]]; then
        verbosity_settings+=("-v" "error" "-stats")
    else
        verbosity_settings+=("-v" "$ffmpeg_verbosity")
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Assemble FFmpeg settings regarding input/trimming
# $1: Absolute path of an input file
# $2: Output duration
function get_input_settings() {
    [[ -z "$1" ]] && \
        { err "Missing input path in get_input_settings!"; \
          clean; exit $err_runtime; }
    [[ -z  $2  ]] && \
        { err "Missing output duration in get_input_settings!"; \
          clean; exit $err_runtime; }
    local file="$1"
    local duration=$2

    declare -ga input_settings=()

    local in_duration=$(jq -r .format.duration "$input_info")
    if [[ -n $global_start ]] && \
       (( $(bc <<< "$global_start < $in_duration") )); then
        input_settings+=("-ss" "$global_start")
    fi
    input_settings+=("-i" "$file")
    if [[ -n $global_end ]] && \
       (( $(bc <<< "$global_end <= $in_duration") )); then
        input_settings+=("-t" "$duration")
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Assemble FFmpeg settings regarding mapping
# $1: Audio stream count
function get_map_settings() {
    [[ -z $1 ]] && \
        { err "Missing audio stream count in get_map_settings!"; \
          clean; exit $err_runtime; }
    local -i streams=$1

    declare -ga map_settings=("-map" "0:v")

    for (( i=0; i < streams; i++ ))
    do
        [[ $audio == false ]] && break
        map_settings+=("-map" "0:a:$i?")
        [[ $basic_format == true ]] && break
    done

    [[ $subtitles == true ]] && map_settings+=("-map" "0:s?")
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Assemble FFmpeg settings regarding subtitles
# $1: Absolute path of an input file
function get_subtitle_settings() {
    [[ -z "$1" ]] && \
        { err "Missing input path in get_subtitle_settings!"; \
          clean; exit $err_runtime; }
    local file="$1"

    declare -ga subtitle_settings=()

    [[ $subtitles == false ]] && return

    if [[ $burn_subs == true ]]; then
        subtitle_settings=("-sn")
    elif output_image_subtitles "$file"; then
        subtitle_settings=("-c:s" "copy")
    else
        subtitle_settings=("-c:s" "webvtt")
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Assemble FFmpeg settings regarding audio
# $1: Absolute path of an input file
# $2: Audio stream count
# $3: Audio sample rate
function get_audio_settings() {
    [[ -z "$1" ]] && \
        { err "Missing input path in get_audio_settings!"; \
          clean; exit $err_runtime; }
    [[ -z  $2  ]] && \
        { err "Missing audio stream count in get_audio_settings!"; \
          clean; exit $err_runtime; }
    [[ -z  $3  ]] && \
        { err "Missing audio sample rate in get_audio_settings!"; \
          clean; exit $err_runtime; }
    local file="$1"
    local -i streams=$2
    local -i rate=$3

    [[ $audio == false ]] && return

    declare -ga audio_settings=()

    for (( i=0; i < streams; i++ ))
    do
        if audio_copy "$file" $i ${audio_values[$i]}; then
            audio_settings+=("-c:a:$i" "copy")
        elif [[ $a_codec == "libopus" ]] && opus_fallback "$file" $i; then
            audio_settings+=("-c:a:$i" "$fallback_codec")
            audio_settings+=("-b:a:$i" "${audio_values[$i]}K")
        else
            audio_settings+=("-c:a:$i" "$a_codec")
            audio_settings+=("-b:a:$i" "${audio_values[$i]}K")
        fi
        [[ $basic_format == true ]] && break
    done
    # -ac/-ar have no effect without audio encoding
    # there's no need for additional checks
    [[ $force_stereo == true ]] && audio_settings+=("-ac" "2")
    (( rate < 44100 )) && audio_settings+=("-ar" "$rate")
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Assemble FFmpeg settings regarding video
# $1: Current bitrate mode
# $2: Output video bitrate
function get_video_settings() {
    [[ -z $1 ]] && \
        { err "Missing bitrate mode in get_video_settings!"; \
          clean; exit $err_runtime; }
    [[ -z $2 ]] && \
        { err "Missing video bitrate in get_video_settings!"; \
          clean; exit $err_runtime; }
    local -i mode=$1
    local -i bitrate=$2

    declare -ga video_settings=()

    video_settings+=("-c:v" "$v_codec")
    video_settings+=("-deadline" "good")
    # -cpu-used defined in call_ffmpeg, since it depends on the pass

    # TO-DO:
    # Test how strong temporal filtering influences high quality encodes
    # Figure out how/why alpha channel support cuts short GIFs during 2-pass
    video_settings+=("-pix_fmt" "$pix_fmt")

    if [[ $pix_fmt == "yuva420p" ]]; then
        video_settings+=("-auto-alt-ref" "0")
    else
        video_settings+=("-auto-alt-ref" "1" "-lag-in-frames" "25" \
                         "-arnr-maxframes" "15" "-arnr-strength" "6")
    fi

    video_settings+=("-b:v" "${bitrate}K")

    if [[ $crf == true ]]; then
        case $mode in 
        1 | 2) video_settings+=("-crf" "$crf_value");;
        esac
    fi

    (( mode == 1 )) && video_settings+=("-qmax" "$min_quality")
    (( mode == 3 )) && video_settings+=("-minrate:v" "${bitrate}K" \
                                        "-maxrate:v" "${bitrate}K")

    video_settings+=("-threads" "$threads")
    # This check isn't necessary, but it avoids command bloat
    if [[ $v_codec == "libvpx-vp9" ]] && (( threads > 1 )); then
        video_settings+=("-tile-columns" "6" \
                         "-tile-rows" "2" "-row-mt" "1")
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Assemble (script) filter string
# $1: Input height
# $2: Input fps
# $3: Output height
# $4: Output fps
function get_filter_settings() {
    [[ -z $1 ]] && \
        { err "Missing input height in get_filter_settings!"; \
          clean; exit $err_runtime; }
    [[ -z $2 ]] && \
        { err "Missing input fps in get_filter_settings!"; \
          clean; exit $err_runtime; }
    [[ -z $3 ]] && \
        { err "Missing output height in get_filter_settings!"; \
          clean; exit $err_runtime; }
    [[ -z $4 ]] && \
        { err "Missing output fps in get_filter_settings!"; \
          clean; exit $err_runtime; }
    local -i in_height=$1
    local in_fps=$2
    local -i out_height=$3
    local out_fps=$4

    declare -ga filter_settings=()

    if (( out_height < in_height && $(bc <<< "$out_fps < $in_fps") )); then
        filter_settings+=("-vf")
        filter_settings+=("scale=-2:$out_height:flags=lanczos,fps=$out_fps")
    elif (( out_height < in_height )); then
        filter_settings+=("-vf")
        filter_settings+=("scale=-2:$out_height:flags=lanczos")
    elif (( $(bc <<< "$out_fps < $in_fps") )); then
        filter_settings+=("-vf")
        filter_settings+=("fps=$out_fps")
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Execute FFmpeg (and assemble pass specific settings)
# $1: Name of output file
function call_ffmpeg() {
    [[ -z "$1" ]] && \
        { err "Missing output name in call_ffmpeg!"; \
          clean; exit $err_runtime; }
    local path="$1"

    local -a raw_video=("-c:v" "copy")
    local -a raw_audio=("-c:a" "copy")
    [[ -n $global_start || $video_filters == true ]] && \
        raw_video=("-c:v" "rawvideo")
    [[ -n $global_start || $audio_filters == true ]] && \
        raw_audio=("-c:a" "pcm_s16le")
    local -a raw_filter=("-filter_complex" "$user_filters")

    local -i pass=''
    local -a pass_settings=()
    for (( pass=1; pass <= passes; pass++ ))
    do
        if (( passes == 1 )); then
            pass_settings=("-cpu-used" "0" "$path")
        elif (( pass == 1 )); then
            pass_settings=("-cpu-used" "5")
            pass_settings+=("-passlogfile" "$ffmpeg_log_prefix" "-pass" "1")
            pass_settings+=("-f" "null" "-")
            [[ $no_filter_firstpass == true ]] && raw_filter=()
            [[ -e "$ffmpeg_log_prefix-0.log" ]] && continue
        elif (( pass == 2 )); then
            pass_settings=("-cpu-used" "0")
            pass_settings+=("-passlogfile" "$ffmpeg_log_prefix" "-pass" "2")
            pass_settings+=("$path")
            raw_filter=("-filter_complex" "$user_filters")
        fi

        if [[ $debug == true ]]; then
            if [[ -n "$user_filters" ]]; then
                echo ffmpeg -y -v error \
                               "${input_settings[@]}" "${map_settings[@]}" \
                               "${raw_video[@]}" "${raw_audio[@]}" -c:s copy \
                               "${raw_filter[@]}" -strict -2 -f matroska -
                echo ffmpeg -y "${verbosity_settings[@]}" -i - -map 0 \
                               "${video_settings[@]}" "${audio_settings[@]}" \
                               "${subtitle_settings[@]}" \
                               "${filter_settings[@]}" "${pass_settings[@]}"
            else
                echo ffmpeg -y "${verbosity_settings[@]}" \
                               "${input_settings[@]}" "${map_settings[@]}" \
                               "${video_settings[@]}" "${audio_settings[@]}" \
                               "${subtitle_settings[@]}" \
                               "${filter_settings[@]}" "${pass_settings[@]}"
            fi
        else
            if [[ -n "$user_filters" ]]; then
                ffmpeg -y -v error \
                          "${input_settings[@]}" "${map_settings[@]}" \
                          "${raw_video[@]}" "${raw_audio[@]}" -c:s copy \
                          "${raw_filter[@]}" -strict -2 -f matroska - | \
                ffmpeg -y "${verbosity_settings[@]}" -i - -map 0 \
                          "${video_settings[@]}" "${audio_settings[@]}" \
                          "${subtitle_settings[@]}" \
                          "${filter_settings[@]}" "${pass_settings[@]}"
            else
                ffmpeg -y "${verbosity_settings[@]}" \
                          "${input_settings[@]}" "${map_settings[@]}" \
                          "${video_settings[@]}" "${audio_settings[@]}" \
                          "${subtitle_settings[@]}" \
                          "${filter_settings[@]}" "${pass_settings[@]}"
            fi
        fi
    done
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Limit output size to be <=max_size
# $1: Absolute path of an input file
# $2: Name of output file
# $3: Output extension
# $4: Initial (theoretical) video bitrate
# Directly accesses mode, bitrate, temp/last/out_size
function limit_size() {
    [[ -z "$1" ]] && \
        { err "Missing input file in limit_size!"; \
          clean; exit $err_runtime; }
    [[ -z "$2" ]] && \
        { err "Missing output name in limit_size!"; \
          clean; exit $err_runtime; }
    [[ -z "$3" ]] && \
        { err "Missing output extension in limit_size!"; \
          clean; exit $err_runtime; }
    [[ -z  $4  ]] && \
        { err "Missing initial bitrate in limit_size!"; \
          clean; exit $err_runtime; }
    [[ -z  $5  ]] && \
        { err "Missing max size in limit_size!"; clean; exit $err_runtime; }
    local file="$1"
    local out="$2"
    local ext="$3"
    local -i ini_bitrate=$4
    local -i max_size=$5

    local -i iter=''
    local user_size=''
    local formula=''
    for (( mode=1; mode <= 3; mode++ ))
    do
        if (( mode == 1 )) && [[ $no_qmax == true ]]; then continue; fi
        for (( iter=1; iter <= iterations; iter++ ))
        do
            formula="$bitrate*$max_size/$temp_size"
            # Reset bitrate for each bitrate mode
            if (( iter == 1 )); then
                bitrate=$ini_bitrate
            # Force min. decrease (% of last bitrate; default: 90%)
            elif (( $(bc <<< "$formula > $bitrate*$min_bitrate_ratio") )); then
                bitrate=$(bc -l <<< "scale=0; $bitrate*$min_bitrate_ratio/1")
            else
                bitrate=$(bc <<< "$formula")
            fi
            (( bitrate <= 0 )) && bitrate=$fallback_bitrate
            calculate_filter_values "$file" $bitrate
            get_video_settings $mode $bitrate
            get_filter_settings ${filter_values[in_height]} \
                                ${filter_values[in_fps]} \
                                ${filter_values[out_height]} \
                                ${filter_values[out_fps]}

            if (( verbosity >= 1 )); then
                [[ $color == true ]] && printf "$color_attempt_info"
                printf "Mode: %d (of 3) | Attempt: %d (of %d) | Height: %d | FPS: %.3f\n" \
                        $mode $iter $iterations \
                        ${filter_values[out_height]} ${filter_values[out_fps]} \
                        2> /dev/null
                printf "$reset_color"
            fi
            (( verbosity >= 2 )) && print_attempt_settings
            call_ffmpeg "$temp_name.$ext"

            # Debug doesn't produce output; specify manually
            if [[ $debug == true ]]; then
                read -rp "Output size in MB: " user_size
                last_size=$temp_size
                temp_size=$(bc -l <<< "scale=0; 1024^2*$user_size/1")
                if (( out_size == 0 || temp_size < out_size )); then
                    out_size=$temp_size
                fi
            else
                last_size=$temp_size
                temp_size=$(stat -c %s "$temp_name.$ext")
                if (( out_size == 0 || temp_size < out_size )); then
                    mv "$temp_name.$ext" "$out"
                    out_size=$temp_size
                fi
            fi
            (( verbosity >= 2 )) && print_size_infos

            # Skip remaining iters, if change too small (defaul: <1%)
            formula="($temp_size-$last_size)/$last_size"
            if (( iter != 1 )) && \
               (( $(bc -l <<< "scale=3; $formula <  $skip_limit") )) && \
               (( $(bc -l <<< "scale=3; $formula > -$skip_limit") )); then
                break
            fi
            (( out_size <= max_size )) && break
        done
        (( out_size <= max_size )) && break
    done
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Enhance output size to be >=min_size (and still <=max_size)
# $1: Absolute path of an input file
# $2: Name of output file
# $3: Output extension
# Directly accesses mode, bitrate, temp/last/out_size
function enhance_size() {
    [[ -z "$1" ]] && \
        { err "Missing input file in enhance_size!"; \
          clean; exit $err_runtime; }
    [[ -z "$2" ]] && \
        { err "Missing output name in enhance_size!"; \
          clean; exit $err_runtime; }
    [[ -z "$3" ]] && \
        { err "Missing output extension in enhance_size!"; \
          clean; exit $err_runtime; }
    local file="$1"
    local out="$2"
    local ext="$3"

    local -i iter=''
    local user_size=''
    local formula=''
    for (( iter=1; iter <= iterations; iter++ ))
    do
        (( out_size <= max_size && out_size >= min_size )) && break
        formula="$bitrate*$max_size/$temp_size"
        # Force min. decrease (% of last bitrate; default: 90%)
        if (( $(bc <<< "$formula < $bitrate") && \
              $(bc <<< "$formula > $bitrate*$min_bitrate_ratio") )); then
            bitrate=$(bc -l <<< "scale=0; $bitrate*$min_bitrate_ratio/1")
        else
            bitrate=$(bc <<< "$bitrate*$max_size/$temp_size")
        fi
        (( bitrate <= 0 )) && bitrate=$fallback_bitrate
        calculate_filter_values "$file" $bitrate
        get_video_settings $mode $bitrate
        get_filter_settings ${filter_values[in_height]} \
                            ${filter_values[in_fps]} \
                            ${filter_values[out_height]} \
                            ${filter_values[out_fps]}

        if (( verbosity >= 1 )); then
            [[ $color == true ]] && printf "$color_attempt_info"
            printf "Enhance Attempt: %d (of %d) | Height: %d | FPS: %.3f\n" \
                    $iter $iterations \
                    ${filter_values[out_height]} ${filter_values[out_fps]} \
                    2> /dev/null
            printf "$reset_color"
        fi
        (( verbosity >= 2 )) && print_attempt_settings
        call_ffmpeg "$temp_name.$ext"

        # Debug doesn't produce output; specify manually
        if [[ $debug == true ]]; then
            read -rp "Output size in MB: " user_size
            last_size=$temp_size
            temp_size=$(bc -l <<< "scale=0; 1024^2*$user_size/1")
            (( temp_size < out_size )) && out_size=$temp_size
        else
            last_size=$temp_size
            temp_size=$(stat -c %s "$temp_name.$ext")
            if (( temp_size <= max_size && temp_size > out_size )); then
                mv "$temp_name.$ext" "$out"
                out_size=$temp_size
            fi
        fi
        (( verbosity >= 2 )) && print_size_infos

        # Skip remaining iters, if change too small (defaul: <1%)
        formula="($temp_size-$last_size)/$last_size"
        if (( $(bc -l <<< "scale=3; $formula <  $skip_limit") && \
              $(bc -l <<< "scale=3; $formula > -$skip_limit") )); then
            break
        fi
    done
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Clean up the workspace
function clean() {
    # delete leftover files
    rm "$input_info" "$output_info" "$temp_name".* 2> /dev/null
    (( passes == 2 )) && rm "$ffmpeg_log_prefix-0.log" 2> /dev/null
    # Unset all file specific variables/arrays
    unset output
    unset trim_values
    unset audio_values
    unset video_values
    unset filter_values
    unset verbosity_settings
    unset input_settings
    unset map_settings
    unset subtitle_settings
    unset audio_settings
    unset video_settings
    unset filter_settings
    unset ext
    unset mode
    unset bitrate
    unset temp_size out_size last_size
    # pass settings local to call_ffmpeg
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function keyboard_interrupt() {
    err "User Interrupt!"
    clean
    exit $user_interrupt
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main script
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function main() {
    check_requirements
    parse_options "$@"
    check_options
    check_user_filters
    declare -ir max_size=$(bc -l <<< "scale=0; $size_limit*1024^2/1")
    declare -ir min_size=$(bc -l <<< "scale=0; $max_size*$undershoot/1")
    if (( verbosity >= 2 )); then
        print_options
        [[ $color == true ]] && printf "$color_verbose_header"
        printf "\n### Start conversion ###\n\n"
        printf "$reset_color"
    fi

    for input in "${input_list[@]}"
    do
        local ext="webm"
        # The following variables get directly accessed in limit/enhance_size
        # enhance_size depends on the modified values from limit_size
        # they get unset in clean
        local -i mode=''
        local -i bitrate=''
        local -i temp_size='' out_size='' last_size=''

        if (( verbosity >= 1 )); then
            [[ $color == true ]] && printf "$color_current_input"
            echo "Current file: $input"
            printf "$reset_color"
        fi

        if output_image_subtitles "$input"; then
            if [[ $mkv_fallback == false ]]; then
                err "$input"
                err "Error: Conversion of image-based subtitles not supported!"
                clean
                continue
            else
                ext="mkv"
            fi
        fi
        resolve_paths "$input" "$ext"

        ffprobe -v error -show_format -show_streams \
            -print_format json "$input" > "$input_info"

        # Check for basic stream order assumptions
        # First stream: video stream
        # Everything afterwards: non-video streams
        if [[ $(jq -r .streams[0].codec_type "$input_info") != "video" ]]; then
            err "$input"
            err "Error: Unsupported stream order (first stream not video)!"
            clean
            continue
        elif [[ $(jq -r .streams[1].codec_type "$input_info") == "video" ]]; then
            err "$input"
            err "Error: More than one video stream per file not supported!"
            clean
            continue
        fi

        calculate_trim_values "$input"
        calculate_audio_values $max_size ${trim_values[dur]}
        calculate_video_values $max_size \
                               ${trim_values[dur]} \
                               ${audio_values[bitrate]}
        get_verbosity_settings
        get_input_settings "$input" ${trim_values[dur]}
        get_map_settings ${audio_values[streams]}
        get_subtitle_settings "$input"
        get_audio_settings "$input" ${audio_values[streams]} \
                           ${audio_values[rate]}
        (( verbosity >= 2 )) && print_general_settings

        limit_size "$input" "$output" "$ext" ${video_values[bitrate]} $max_size
        if (( out_size > max_size )); then
            err "$output"
            err "Error: Still too large!"
            size_fail=true
            clean
            continue
        fi
        enhance_size "$input" "$output" "$ext"
        if (( out_size < min_size )); then
            err "$output"
            err "Error: Still too small!"
            size_fail=true
        fi

        clean
    done
}

# Execute main function
(( $# == 0 )) && { usage; exit 0; }
main "$@"
if (( verbosity >= 2 )); then
    [[ $color == true ]] && printf "$color_verbose_header"
    printf "\n### Finished ###\n\n"
    printf "$reset_color"
fi
[[ $size_fail == true ]] && exit $err_size
exit 0
