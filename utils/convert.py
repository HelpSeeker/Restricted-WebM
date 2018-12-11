"""
Provide functions to convert input files via ffmpeg.

Functions:
    assemble_command: Convert dictionaries into lists
    get_size: Get output size either via ffprobe or user input
    raw_command: Collect ffmpeg options for piping the input
    webm_command: Collect ffmpeg options create final WebM
    ffmpeg: Run the commands
    limiter: Adjust video settings to decrease WebM size
    enhancer: Adjust video settings to increase WebM size
    convert_file: Handle the whole conversion process
"""

from os import path, mkdir, remove, replace
from subprocess import Popen, run, PIPE

from utils.audio import audio_settings
from utils.error import log_error
from utils.info import output_size
from utils.entry import input_settings
from utils.mapping import map_settings
from utils import video

def assemble_command(dictionary):
    """
    Convert a dictionary into a list.
    These lists are used for subprocess.run()

    Params:
        param1: Dictionary containing ffmpeg options

    Results:
        ffmpeg options in list form
    """
    command = []
    for i in list(dictionary.keys()):
        command.extend(dictionary[i])

    return command

def get_size(debug_flag, out_path):
    """
    Get output size via ffprobe or user input.

    Params:
        param1: Debug flag
        param2: Output path

    Results:
        File size in bytes
    """
    if debug_flag:
        size = input("Output size in MiB: ")
        size = float(size)*1024**2
    else:
        size = output_size(out_path)

    return size

def raw_command(args, in_file):
    """
    Gather different ffmpeg settings.
    This is the first of two ffmpeg commands.
    User filters will be applied during with this command.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input information

    Returns
        Dictionary containing an ffmpeg command
    """
    command = {"program" : ["ffmpeg"],
               "verbosity": ["-v", "panic"],
               "input": input_settings(args, in_file),
               "map": map_settings(args, in_file.a_prop.streams),
               "video": ["-c:v", "copy"],
               "audio": [],
               "subtitles": [],
               "filter": [],
               "output": ["-strict", "-2", "-f", "matroska", "-"]}

    if args.video_filters or args.trim or args.start != 0:
        command["video"] = ["-c:v", "rawvideo"]
    if args.filter != "":
        command["filter"] = ["-filter_complex", args.filter]
    if args.subtitles:
        command["subtitles"] = ["-c:s", "copy"]
    if args.audio:
        command["audio"] = ["-c:a", "copy"]
        if args.audio_filters or args.trim or args.start != 0:
            command["audio"] = ["-c:a", "pcm_s16le"]

    return command

def webm_command(args, in_file):
    """
    Gather different ffmpeg settings.
    This is the second of two ffmpeg commands.
    The actual conversion happens with this command.
    Automatic filters will be applied with this command.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input information

    Returns
        Dictionary containing an ffmpeg command
    """
    # https://trac.ffmpeg.org/ticket/6375
    # If this bug happens frequently then add
    # "bugfix": ["-max_muxing_queue_size", "9999"],
    command = {"program" : ["ffmpeg", "-y"],
               "verbosity": ["-v", "panic", "-stats"],
               "input": ["-i", "-"],
               "map": ["-map", "0"],
               "video": [],
               "speed": ["-deadline", "good", "-cpu-used", "0"],
               #"bugfix": ["-max_muxing_queue_size", "9999"],
               "audio": [],
               "subtitles": [],
               "filter": [],
               "output": []}

    if args.audio:
        command["audio"] = audio_settings(args, in_file)
    if args.subtitles:
        command["subtitles"] = ["-c:s", "webvtt"]
        if in_file.image_sub and args.mkv_fallback:
            command["subtitles"] = ["-c:s", "copy"]

    return command

def ffmpeg(args, raw, webm, out_path):
    """
    Apply pass specific options and run ffmpeg.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: ffmpeg command (input -> raw pipe)
        param3: ffmpeg command (raw pipe -> WebM)
        param4: Output path of the WebM
    """
    webm["output"] = [out_path]
    # Temporarily store values in case of 2-pass encoding
    raw_filter = raw["filter"]
    raw_audio = raw["audio"]
    webm_audio = webm["audio"]

    # Get pass specific settings if 2-pass encoding
    for i in range(0, args.passes):
        if i == 0 and args.passes == 2:
            # skip first pass if log is present
            # faster encoding and more predictable out size
            if path.exists("ffmpeg2pass-0.log"):
                continue

            if args.no_filter_firstpass:
                raw["filter"] = []
            raw["audio"] = ["-an"]
            webm["audio"] = ["-an"]
            webm["speed"] = ["-deadline", "good", "-cpu-used", "5"]
            webm["output"] = ["-pass", "1", "-f", "null", "-"]
        elif i == 1:
            raw["filter"] = raw_filter
            raw["audio"] = raw_audio
            webm["audio"] = webm_audio
            webm["speed"] = ["-deadline", "good", "-cpu-used", "0"]
            webm["output"] = ["-pass", "2", out_path]

        ffmpeg_raw = assemble_command(raw)
        ffmpeg_webm = assemble_command(webm)

        # Only print command when debug flag
        if args.debug:
            print(ffmpeg_raw)
            print(ffmpeg_webm)
        else:
            # Pipe output of 1st command to 2nd command
            raw_out = Popen(ffmpeg_raw, stdout=PIPE, bufsize=10**8)
            run(ffmpeg_webm, stdin=raw_out.stdout)

def limiter(args, in_file, raw, webm):
    """
    Adjust video settings to fit input into the file size limit.
    Loop through bitrate modes and adjust bitrate based on previous attempt.
    Apply downscaling and frame dropping (unless disabled)

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input information
        param3: ffmpeg command (input -> raw pipe)
        param4: ffmpeg command (raw pipe -> WebM)
    """
    out_path = in_file.i_prop.out_path

    for mode in range(0, 3):
        bitrate_list = []
        size_list = []

        for attempt in range(0, args.iterations):
            if bool(bitrate_list):
                last_bitrate = bitrate_list[attempt-1]
                last_size = size_list[attempt-1]
            else:
                last_bitrate = None
                last_size = None

            bitrate = video.video_bitrate(args, in_file, last_bitrate, \
                                          last_size, attempt)
            bitrate_list.append(bitrate)

            webm["video"] = video.video_settings(args, mode, bitrate)

            fps = in_file.v_prop.fps
            # 2 stages allow for height and frame rate to have same importance
            for stage in range(2, 0, -1):
                height = video.downscale_height(args, in_file.v_prop, bitrate,
                                                fps, stage)
                fps = video.drop_framerate(args, in_file.v_prop,
                                           bitrate, height)

            scale_filter = height != in_file.v_prop.height
            fps_filter = fps != in_file.v_prop.fps

            if scale_filter or fps_filter:
                filter_str = ""
                if scale_filter:
                    filter_str += "scale=-2:" + str(height) + ":flags=lanczos"
                if scale_filter and fps_filter:
                    filter_str += ","
                if fps_filter:
                    filter_str += "fps=" + str(fps)
                webm["filter"] = ["-vf", filter_str]

            print("+++")
            print("Current mode/attempt: %d (of 3) / %d (of %d)" \
                  % (mode+1, attempt+1, args.iterations))
            print("Current height/frame rate: %d / %.3f" % (height, fps))

            ffmpeg(args, raw, webm, out_path)

            # Manually enter out size when debug flag
            size = get_size(args.debug, out_path)
            size_list.append(size)

            print("Output size: %.2f MiB" % (size/1024**2))

            if size <= args.upper_limit:
                # To make final settings available to enhancer()
                in_file.mode = mode
                in_file.best_bitrate = bitrate
                in_file.best_size = size
                return
            # If >= 2% improvement, skip remaining attempts
            # Especially important during first mode (-qmax 50)
            if attempt > 0:
                diff = (size-last_size) / last_size
                if abs(diff) <= 0.02:
                    break

def enhancer(args, in_file, raw, webm):
    """
    Adjust video settings to raise output size above the undershoot limit.
    Fine tune video bitrate while using the same bitrate mode.
    Apply downscaling and frame dropping (unless disabled)

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input information
        param3: ffmpeg command (input -> raw pipe)
        param4: ffmpeg command (raw pipe -> WebM)
    """
    out_path = in_file.i_prop.out_path
    if args.mkv_fallback:
        temp_path = path.join(in_file.i_prop.out_dir, "temp.mkv")
    else:
        temp_path = path.join(in_file.i_prop.out_dir, "temp.webm")

    mode = in_file.mode
    bitrate_list = [in_file.best_bitrate]
    size_list = [in_file.best_size]

    iterations = args.iterations*2 + 1
    for attempt in range(1, iterations):
        last_bitrate = bitrate_list[attempt-1]
        last_size = size_list[attempt-1]

        bitrate = video.video_bitrate(args, in_file, last_bitrate, \
                                          last_size, attempt)
        bitrate_list.append(bitrate)

        webm["video"] = video.video_settings(args, mode, bitrate)

        fps = in_file.v_prop.fps
        # 2 stages allow for height and frame rate to have same importance
        for stage in range(2, 0, -1):
            height = video.downscale_height(args, in_file.v_prop, bitrate,
                                            fps, stage)
            fps = video.drop_framerate(args, in_file.v_prop,
                                       bitrate, height)

        scale_filter = height != in_file.v_prop.height
        fps_filter = fps != in_file.v_prop.fps

        if scale_filter or fps_filter:
            filter_str = ""
            if scale_filter:
                filter_str += "scale=-2:" + str(height) + ":flags=lanczos"
            if scale_filter and fps_filter:
                filter_str += ","
            if fps_filter:
                filter_str += "fps=" + str(fps)
            webm["filter"] = ["-vf", filter_str]

        print("+++")
        print("Enhance attempt: %d of %d" % (attempt, iterations-1))
        print("Current height/frame rate: %d / %.3f" % (height, fps))

        ffmpeg(args, raw, webm, temp_path)

        # Manually enter out size when debug flag
        size = get_size(args.debug, temp_path)
        size_list.append(size)

        print("Output size: %.2f MiB" % (size/1024**2))

        # Replace output with temp.webm if a better attempt
        # Avoids unnecessary encoding at the end with best settings
        if not args.debug and \
           in_file.best_size < size <= args.upper_limit:
            replace(temp_path, out_path)

        if args.lower_limit <= size <= args.upper_limit:
            return

        # If >= 2% improvement, skip remaining attempts
        # Especially important for short clips with high size limits
        if attempt > 1:
            diff = (size-last_size) / last_size
            if abs(diff) <= 0.02:
                break

def convert_file(args, in_file):
    """
    Call enhancer and limiter.
    Also manage out dir creation and log deletion.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input information

    Raises:
        Recoverable error if output is still too large
        Recoverable error if output is still too small
    """
    in_path = in_file.i_prop.out_path
    out_dir = in_file.i_prop.out_dir
    out_path = in_file.i_prop.out_path

    if not (path.exists(out_dir) or args.debug):
        mkdir(out_dir)

    raw = raw_command(args, in_file)
    webm = webm_command(args, in_file)
    limiter(args, in_file, raw, webm)

    # Output is still too large -> error
    if get_size(args.debug, out_path) > args.upper_limit:
        in_file.internal_error = True
        log_error(in_path, "too big")
    # Output is too small -> enhancer
    elif get_size(args.debug, out_path) < args.lower_limit:
        enhancer(args, in_file, raw, webm)
    # Output is still too small -> error
    if get_size(args.debug, out_path) < args.lower_limit:
        in_file.internal_error = True
        log_error(in_path, "too small")

    if path.exists("ffmpeg2pass-0.log"):
        remove("ffmpeg2pass-0.log")
