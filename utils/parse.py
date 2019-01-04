"""Provide the command line arguments for argparse."""

import argparse

def parsed_args():
    """
    Define CLI options and create args object.

    Returns:
        Object containing all arguments and input paths
    """
    parser = argparse.ArgumentParser()

    parser.add_argument("input", nargs="+", \
                        help="file to convert")
    parser.add_argument("-t", "--trim", action="store_true", \
                        help="prompt user for trim settings for each video")
    parser.add_argument("-a", "--audio", action="store_true", \
                        help="use input audio (if present)")
    parser.add_argument("-s", "--size", type=float, default=3, \
                        help="specify file size limit in MiB (default: 3)")
    parser.add_argument("-f", "--filter", type=str, default="", \
                        help="pass custom ffmpeg filters")
    parser.add_argument("-p", "--passes", type=int, default=2, choices=[1, 2], \
                        help="force single/two-pass encoding (default: 2)")
    parser.add_argument("-u", "--undershoot", type=float, default=0.75, \
                        help="specify undershoot limit (default 0.75)")
    parser.add_argument("-i", "--iterations", type=int, default=3, \
                        help="iterations for each bitrate mode (default: 3)")
    parser.add_argument("-ss", "--start", type=float, default=0, \
                        help="specify start time for all input videos in sec.")
    parser.add_argument("-to", "--end", type=float, default=0, \
                        help="specify end time for all input videos in sec.")
    parser.add_argument("-fs", "--force-stereo", action="store_true", \
                        help="force stereo audio output")
    parser.add_argument("-bf", "--basic-format", action="store_true", \
                        help="limit the output to max. one video/audio stream")
    parser.add_argument("-mih", "--min-height", type=int, default=240, \
                        help="force min. output height (default: 240)")
    parser.add_argument("-mah", "--max-height", type=int, default=9999, \
                        help="force max. output height")
    parser.add_argument("--bpp", type=float, default=0.075, \
                        help="specify custom bpp threshold (default: 0.075)")
    parser.add_argument("--min-fps", type=float, default=24, \
                        help="specify the min. framerate threshold (default: 24)")
    parser.add_argument("--max-fps", type=float, default=9999, \
                        help="specify a max. framerate threshold")
    parser.add_argument("--opus", action="store_true", \
                        help="use and allow Opus as audio codec")
    parser.add_argument("--subtitles", action="store_true", \
                        help="use input subtitles (if present)")
    parser.add_argument("--transparency", action="store_true", \
                        help="preserve input transparency")
    parser.add_argument("--min-audio", type=int, default=6, \
                        help="force min. audio channel bitrate (default: 6)")
    parser.add_argument("--max-audio", type=int, default=9999, \
                        help="force max. audio channel bitrate")
    parser.add_argument("--mkv-fallback", action="store_true", \
                        help="allow usage of MKV for image-based subtitles")
    parser.add_argument("--no-filter-firstpass", action="store_true", \
                        help="disable filters during the first pass")
    parser.add_argument("--no-copy", action="store_true", \
                        help="disable stream copying")
    parser.add_argument("--force-copy", action="store_true", \
                        help="force-copy compatible audio (!) streams")
    parser.add_argument("--no-qmax", action="store_true", \
                        help="skip the first bitrate mode (VBR with qmax)")
    parser.add_argument("--audio-factor", type=float, default=5.5, \
                        help="factor used to choose audio bitrate (default: 5.5)")
    parser.add_argument("--debug", action="store_true", \
                        help="only print ffmpeg commands")

    return parser.parse_args()
