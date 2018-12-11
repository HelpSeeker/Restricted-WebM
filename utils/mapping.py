"""
Collection of functions regarding map settings for ffmpeg.

Functions:
    map_settings: Assemble ffmpeg map settings
"""

def map_settings(args, a_stream_count):
    """
    Assemble map settings for ffmpeg.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Number of input audio streams

    Returns:
        Map settings for ffmpeg
    """
    settings = ["-map", "0:v"]

    if args.audio:
        for index in range(a_stream_count):
            stream_selection = "0:a:" + str(index)
            settings.extend(["-map", stream_selection])
            if args.basic_format:
                break

    if args.subtitles:
        settings.extend(["-map", "0:s?"])

    return settings
