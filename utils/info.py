"""
Collection of functions to gather input information.

Functions:
    format_output: Format ffprobe output
    length: Get input video duratio
    height: Get input video height
    ratio: Get input video ratio
    framerate: Get input video frame rate
    audio_stream_count: Get input audio stream count
    audio_channel_count: Get channel count of an audio stream
    audio_codec: Get input audio codec
    allowed_codec: Determine if codec is WebM compatible
    opus_fail: Test if libopus can handle specific audio stream
    audio_input_bitrate: Get input audio stream bitrate
    image_subtitles: Test if input has image-based subtitles
    audio_filters: Test for audio filters in the filter string
    video_filters: Test for video filters in the filter string
    output_size: Get output WebM size
    """

from os import path, mkdir, rmdir, remove
from subprocess import run, PIPE

def format_output(output):
    """
    Format ffprobe output for conversion to int/float.

    Params:
        param1: To be formatted output string (ffprobe output)

    Returns:
        Formatted string only containing a number
    """
    output = output.decode("utf-8")
    output = output.strip("\n")
    return output

def brute_length(in_path):
    """
    Get input length via a test encode.
    Allows to determine the length of animated GIFs and images.

    Params:
        param1: Path to the input file

    Returns:
        Length in seconds as float
    """
    out_dir = "webm_temp"
    out_name = "temp.mkv"
    out_path = path.join(out_dir, out_name)

    if not path.exists(out_dir):
        mkdir(out_dir)

    command = ["ffmpeg",
               "-v", "panic",
               "-i", in_path,
               "-map", "0:v",
               "-c:v", "libx264",
               "-preset", "ultrafast",
               "-crf", "51",
               out_path]

    run(command)
    output = length(out_path)

    if path.exists(out_path):
        remove(out_path)
    rmdir(out_dir)

    return output

def length(in_path):
    """
    Get video length.

    Params:
        param1: Path to the input file

    Returns:
        Length in seconds as float
    """
    command = ["ffprobe",
               "-v", "panic",
               "-show_entries", "format=duration",
               "-of", "default=noprint_wrappers=1:nokey=1",
               in_path]

    output = run(command, stdout=PIPE).stdout
    output = format_output(output)

    # for pictures (including animated GIF)
    if output == "N/A":
        return brute_length(in_path)
    return float(output)

def height(in_path):
    """
    Get video height.

    Params:
        param1: Path to the input file

    Returns:
        Height in pixels
    """
    command = ["ffprobe",
               "-v", "panic",
               "-select_streams", "v:0",
               "-show_entries", "stream=height",
               "-of", "default=noprint_wrappers=1:nokey=1",
               in_path]

    output = run(command, stdout=PIPE).stdout
    output = format_output(output)

    return int(output)

def ratio(in_path, in_height):
    """
    Get video display aspect ratio.

    Params:
        param1: Path to the input file
        param2: Video height of the input file

    Returns:
        Aspect ratio as float
    """
    command = ["ffprobe",
               "-v", "panic",
               "-select_streams", "v:0",
               "-show_entries", "stream=width",
               "-of", "default=noprint_wrappers=1:nokey=1",
               in_path]

    output = run(command, stdout=PIPE).stdout
    output = format_output(output)
    in_width = int(output)

    return float(in_width/in_height)

def framerate(in_path):
    """
    Get video frame rate.

    Params:
        param1: Path to the input file

    Returns:
        Frame rate as float
    """
    command = ["ffprobe",
               "-v", "panic",
               "-select_streams", "v:0",
               "-show_entries", "stream=avg_frame_rate",
               "-of", "default=noprint_wrappers=1:nokey=1",
               in_path]

    output = run(command, stdout=PIPE).stdout
    output = format_output(output)
    # for pictures (excluding animated GIF)
    if output == "0/0":
        return 1
    output = output.split("/")

    # ffprobe returns frame rate as x/y (e.g. 24/1, 30000/1001)
    return float(int(output[0])/int(output[1]))

def audio_stream_count(in_path):
    """
    Get audio stream count of the input file.

    Params:
        param1: Path to the input file

    Returns:
        Number of present input audio streams
    """
    # Loop through possible streams
    # Stops when ffprobe doesn't output stream index
    for index in range(0, 100):
        stream_selection = "a:" + str(index)
        command = ["ffprobe",
                   "-v", "panic",
                   "-select_streams", stream_selection,
                   "-show_entries", "stream=index",
                   "-of", "default=noprint_wrappers=1:nokey=1",
                   in_path]

        output = run(command, stdout=PIPE).stdout
        output = format_output(output)
        if output == "":
            return index

    return 0

def audio_channel_count(in_path, index):
    """
    Get channel count of an input audio stream.

    Params:
        param1: Path to the input file
        param2: Index of the specific audio stream

    Returns:
        Number of audio channels
    """
    stream_selection = "a:" + str(index)
    command = ["ffprobe",
               "-v", "error",
               "-select_streams", stream_selection,
               "-show_entries", "stream=channels",
               "-of", "default=noprint_wrappers=1:nokey=1",
               in_path]

    output = run(command, stdout=PIPE).stdout
    output = format_output(output)

    return int(output)

def audio_codec(in_path, index):
    """
    Get codec name of an input audio stream.

    Params:
        param1: Path to the input file
        param2: Index of the specific audio stream

    Returns:
        Full name of the audio codec (lowercase)
    """
    stream_selection = "a:" + str(index)
    command = ["ffprobe",
               "-v", "panic",
               "-select_streams", stream_selection,
               "-show_entries", "stream=codec_long_name",
               "-of", "default=noprint_wrappers=1:nokey=1",
               in_path]

    output = run(command, stdout=PIPE).stdout
    output = format_output(output)

    return str.lower(output)

def allowed_codec(args, in_path, index):
    """
    Test if input audio codec is WebM compatible.
    Opus only gets accepted with the --opus flag set.

    Params:
        param1: Object containing all arguments (created by argparse)
        param2: Path to the input file
        param3: Index of the specific audio stream

    Returns:
        True if input is Vorbis (or Opus, if --opus is used)
        False otherwise
    """
    allowed = ["vorbis"]
    if args.opus:
        allowed.extend(["opus"])

    in_codec = audio_codec(in_path, index)
    for out_codec in allowed:
        if out_codec in in_codec:
            return True

    return False

def opus_fail(in_path, index):
    """
    Test if libopus fails to encode an audio stream.
    Some surround sound arrangements fail due to ffmpeg remapping issues.
    See: https://trac.ffmpeg.org/ticket/5718

    Params:
        param1: Path to the input file
        param2: Index of the specific audio stream

    Returns:
        True if libopus fails to encode the stream
        False if it succeeds
    """
    stream_selection = "0:a:" + str(index)

    command = ["ffmpeg",
               "-v", "panic",
               "-i", in_path,
               "-t", "0.1",
               "-map", stream_selection,
               "-c:a", "libopus"
               "-f", "null", "-"]

    return bool(run(command).returncode)

def audio_input_bitrate(in_path, index):
    """
    Get bitrate of an input audio stream.

    Params:
        param1: Path to the input file
        param2: Index of the specific audio stream

    Returns:
        Bitrate in Kbps as int
    """
    out_dir = "webm_temp"
    out_name = "temp.mkv"
    out_path = path.join(out_dir, out_name)
    stream_selection = "0:a:" + str(index)

    if not path.exists(out_dir):
        mkdir(out_dir)

    # Only copies the first 5 seconds
    # Close enough to the total avg. bitrate
    ffmpeg = ["ffmpeg",
              "-v", "panic",
              "-i", in_path,
              "-t", "5",
              "-map", stream_selection,
              "-c:a", "copy",
              out_path]

    ffprobe = ["ffprobe",
               "-v", "panic",
               "-show_entries", "format=bit_rate",
               "-of", "default=noprint_wrappers=1:nokey=1",
               out_path]

    run(ffmpeg)
    output = run(ffprobe, stdout=PIPE).stdout
    output = format_output(output)

    if path.exists(out_path):
        remove(out_path)
    rmdir(out_dir)

    return int(int(output)/1000)

def input_subtitles(in_path):
    """
    Check the existence of input subtitles.

    Params:
        param1: Path to the input file

    Returns:
        True if input subtitles are present
        False otherwise
    """
    command = ["ffprobe",
               "-v", "panic",
               "-select_streams", "s:0",
               "-show_entries", "stream=index",
               "-of", "default=noprint_wrappers=1:nokey=1",
               in_path]

    output = run(command, stdout=PIPE).stdout
    output = format_output(output)
    if output != "":
        return True

    return False

def image_subtitles(in_path):
    """
    Test if subtitles of an input file are text- or image-based.

    Params:
        param1: Path to the input file

    Returns:
        True if subtitles are image-based
        False if they are text-based
    """
    command = ["ffmpeg",
               "-v", "panic",
               "-i", in_path,
               "-t", "0.1",
               "-map", "0:s?",
               "-c:s", "webvtt",
               "-f", "null", "-"]

    return bool(run(command).returncode)

def audio_filters(filters):
    """
    Test if user set filter string contains audio filters.

    Params:
        param1: Custom user filter string

    Returns:
        True if audio filters are being used
        False otherwise
    """
    if filters == "":
        return False

    command = ["ffmpeg",
               "-v", "panic",
               "-f", "lavfi",
               "-i", "anullsrc",
               "-t", "0.1",
               "-map", "0:a?",
               "-c:a", "copy",
               "-filter_complex", filters,
               "-f", "null", "-"]

    return bool(run(command).returncode)

def video_filters(filters):
    """
    Test if user set filter string contains video filters.

    Params:
        param1: Custom user filter string

    Returns:
        True if video filters are being used
        False otherwise
    """
    if filters == "":
        return False

    command = ["ffmpeg",
               "-v", "panic",
               "-f", "lavfi",
               "-i", "nullsrc",
               "-t", "0.1",
               "-map", "0:v",
               "-c:v", "copy",
               "-filter_complex", filters,
               "-f", "null", "-"]

    return bool(run(command).returncode)

def output_size(out_path):
    """
    Get file size of the converted output WebM/MKV.

    Params:
        param1: Path to the output file

    Returns:
        File size in Bytes
    """
    command = ["ffprobe",
               "-v", "panic",
               "-show_entries", "format=size",
               "-of", "default=noprint_wrappers=1:nokey=1",
               out_path]

    output = run(command, stdout=PIPE).stdout
    output = format_output(output)

    return int(output)
