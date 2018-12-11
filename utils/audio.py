"""
Collection of functions regarding audio settings for ffmpeg.

Functions:
    channel_bitrate: Get uniform channel bitrate
    stream_bitrate: Get overall stream bitrate
    copy_stream: Decide if input stream should be copied
    audio_bitrate_sum: Get complete audio bitrate
    audio_settings: Assemble ffmpeg audio settings
"""

from utils.info import allowed_codec, opus_fail

def channel_bitrate(args, in_file):
    """
    Choose uniform audio channel bitrate.
    Decision is based on:
        -) output duration
        -) overall channel count
        -) file size limit

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input information

    Returns:
        To be used bitrate per audio channel
    """
    stream_count = in_file.a_prop.streams
    out_dur = in_file.t_prop.out_dur

    channels = 0
    for index in range(stream_count):
        if args.force_stereo:
            channels += 2
        else:
            channels += in_file.a_prop.channels[index]
        if args.basic_format:
            break

    # Original formula (aimed at 1 stereo audio stream)
    # factor = args.size*8*1000/(in_file.out_duration*5.5*32)
    factor = args.size*8*1000 / (out_dur*channels*2.75*32)

    # Numbers are based on personal experience with 4MB WebMs
    # Aimed at music, not speech
    if factor < 1:
        bitrate = 24
    elif factor < 2:
        bitrate = 32
    elif factor < 7:
        bitrate = 48
    elif factor < 14:
        bitrate = 64
    elif factor < 30:
        bitrate = 80
    else:
        bitrate = 96

    if bitrate > args.max_audio:
        bitrate = args.max_audio
    elif bitrate < args.min_audio:
        bitrate = args.min_audio

    return bitrate

def stream_bitrate(args, in_file, index):
    """
    Calculate output audio stream bitrate.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input information
        param3: Index of the specific audio stream

    Returns:
        To be used audio bitrate for the specific stream
    """
    bitrate = 0

    if args.force_stereo:
        channels = 2
    else:
        channels = in_file.a_prop.channels[index]
    bitrate = channels * channel_bitrate(args, in_file)

    return bitrate

def copy_stream(args, in_file, index):
    """
    Determine if input audio stream should be copied.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input information
        param3: Index of the specific audio stream

    Returns:
        True if stream should be copied
        False otherwise
    """
    in_path = in_file.i_prop.in_path
    out_bitrate = stream_bitrate(args, in_file, index)
    in_bitrate = in_file.a_prop.bitrate[index]

    if not args.no_copy and \
       not args.audio_filters and \
       not args.trim and \
       not args.start == 0 and \
       allowed_codec(args, in_path, index) and \
       (in_bitrate-5 <= out_bitrate or args.force_copy):
        return True

    return False

def audio_bitrate_sum(args, in_file):
    """
    Sum up the individual audio stream bitrates.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input information

    Returns:
        Total audio bitrate of the output
    """
    stream_count = in_file.a_prop.streams
    bitrate = 0

    for index in range(stream_count):
        if copy_stream(args, in_file, index):
            bitrate += in_file.a_prop.bitrate[index]
        else:
            bitrate += stream_bitrate(args, in_file, index)
        if args.basic_format:
            break

    return bitrate

def audio_settings(args, in_file):
    """
    Assemble audio settings for ffmpeg.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Object containing all input information

    Returns:
        Audio settings for ffmpeg
    """
    in_path = in_file.i_prop.in_path
    stream_count = in_file.a_prop.streams
    settings = []

    if not args.audio:
        return settings

    for index in range(stream_count):
        encoder_selection = "-c:a:" + str(index)
        bitrate_selection = "-b:a:" + str(index)

        encoder = "libvorbis"
        if args.opus and \
           (args.force_stereo or not opus_fail(in_path, index)):
            encoder = "libopus"

        bitrate = stream_bitrate(args, in_file, index)

        if copy_stream(args, in_file, index):
            settings.extend([encoder_selection, "copy"])
        else:
            settings.extend([encoder_selection, encoder,
                             bitrate_selection, str(bitrate) + "K"])

    if args.force_stereo:
        settings.extend(["-ac", "2"])

    return settings
