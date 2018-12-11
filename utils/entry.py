"""
Collection of functions regarding trim and input settings.

Functions:
    start_time: Get trim start duration
    end_time: Get trim end duration
    input_settings: Assemble ffmpeg input settings
"""

from utils.error import log_error
from utils.info import input_subtitles

def start_time(in_file):
    """
    Prompt user for start time.

    Params:
        param1: Object containing all input information

    Returns:
        Timecode in sec. when to start encoding the footage

    Raises:
        ValueError when start time isn't a number
        Recoverable error when negative start time
    """
    in_path = in_file.i_prop.in_path

    start = input("Specify start time in sec. (default: 0) : ")
    if start == "":
        start = 0

    try:
        start = float(start)
    except:
        raise ValueError("Start time must be a number!")

    if start < 0:
        in_file.internal_error = True
        log_error(in_path, "wrong trim")

    return start

def end_time(in_file, start, in_dur):
    """
    Prompt user for end time.

    Params:
        param1: Object containing all input information
        param2: Timecode when to start encoding
        param3: Duration of the input

    Returns:
        Timecode in sec. when to end encoding the footage

    Raises:
        ValueError when start time isn't a number
        Recoverable error when end/start time invalid
    """
    in_path = in_file.i_prop.in_path

    end = input("Specify end time in sec. (default: full length): ")
    if end == "":
        end = in_dur

    try:
        end = float(end)
    except:
        raise ValueError("End time must be a number!")

    if end < 0 or \
       end > in_dur or \
       end < start:
        in_file.internal_error = True
        log_error(in_path, "wrong trim")

    return end

def input_settings(args, in_file):
    """
    Assemble input settings for ffmpeg.

    Params:
        param1: Object containing all input information

    Returns:
        Input settings for ffmpeg
    """
    start = in_file.t_prop.start
    end = in_file.t_prop.end
    in_dur = in_file.t_prop.in_dur
    out_dur = in_file.t_prop.out_dur
    in_path = in_file.i_prop.in_path

    settings = []

    # ffmpeg syntax used:
    # -ss <start> -i <input> -t <duration>
    # In case of subtitles:
    # -i <input> -ss <start> -t <duration>
    if args.subtitles and input_subtitles(in_path):
        settings.extend(["-i", in_path])
        if start > 0:
            settings.extend(["-ss", str(start)])
    else:
        if start > 0:
            settings.extend(["-ss", str(start)])
        settings.extend(["-i", in_path])
    if end < in_dur:
        settings.extend(["-t", str(out_dur)])

    return settings
