"""
Collection of functions regarding internal error handling.

Functions:
    check_args: Check CLI input validity
    log_error: Log internal error messages
"""

from datetime import datetime

def check_args(args):
    """
    Raise errors for invalid command line arguments / mutually exclusive flags.

    Params:
        param1: Object containing all arguments (created by argparse)
    """
    if args.min_audio < 24 or args.max_audio < 24:
        raise ValueError("Max/min bitrate too low (must be >= 24 Kbps)!")

    if args.start < 0 or args.end < 0:
        raise ValueError("--start/--end can't be less than 0!")

    if args.end != 0 and args.end <= args.start:
        raise ValueError("--end can't be less or equal than --start!")

    if (args.start != 0 or args.end != 0) and args.trim:
        raise ValueError("--start/--end and --trim are mutually exclusive!")

    if args.no_copy and args.force_copy:
        raise ValueError("--no-copy/--force-copy are mutually exclusive!")

    if args.undershoot < 0 or args.undershoot > 1:
        raise ValueError("--undershoot must be in the range [0, 1]!")

    if args.bpp <= 0:
        raise ValueError("--bpp must be greater than 0!")

    if args.min_height <= 0:
        raise ValueError("--min-height must be greater than 0!")

    if args.max_height <= 0:
        raise ValueError("--max-height must be greater than 0!")

    if args.min_height > args.max_height:
        raise ValueError("--min-height can't be greater than --max-height!")

    if args.min_fps < 1:
        raise ValueError("--min-fps can't be less than 0!")

    if args.min_fps > args.max_fps:
        raise ValueError("--max-fps can't be less than --min-fps!")

def log_error(path, err_type):
    """
    Document errors occurring during script execution.
    Output time stamp, affected file and error message to an error log.

    Params:
        param1: Path of the affected file
        param2: Error identifier
    """
    log = open("webm_error.log", "a")
    time = str(datetime.now())

    if err_type == "image-based subtitles":
        message = "Image-based subtitles can't be converted to WebVTT!"
    elif err_type == "wrong trim":
        message = "Invalid start and/or end time specified!"
    elif err_type == "non-existent input":
        message = "Input file doesn't exist!"
    elif err_type == "too big":
        message = "Couldn't fit video within the file size limit!"
    elif err_type == "too small":
        message = "Couldn't raise file size above the undershoot limit!"
    elif err_type == "wrong start":
        message = "--start <...> is greater than or equal the input duration!"
    elif err_type == "wrong end":
        message = "--end <...> is greater than the input duration!"

    log.write("Time: " + time + "\n")
    log.write("File: " + path + "\n")
    log.write("Description: " + message + "\n\n")
    log.close()
