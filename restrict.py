#!/usr/bin/env python3

import os
import sys
import json
import subprocess
from fnmatch import fnmatch

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Global variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# options object also global (defined in main())

# ANSI escape codes for color output
# See https://en.wikipedia.org/wiki/ANSI_escape_code
color_current_input = '\033[0;35m'
color_attempt_info = '\033[0;32m'
color_verbose_header = '\033[1;36m'
color_general_settings = color_current_input
color_attempt_settings = color_attempt_info
color_size_infos = color_attempt_info
reset_color = '\033[0m'

# Error codes
# 1 -> missing required software
# 2 -> invalid user-specified option
# 3 -> misc. runtime error
# 4 -> not all input videos could be fit into the file size range
# 5 -> termination was requested mid-way by the user (i.e. Ctrl+C)
missing_dep = 1
err_option = 2
err_runtime = 3
err_size = 4
user_interrupt = 5
size_fail = False

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Default settings
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

class Options_Assembler:
    """
    Handles all actions regarding user options.

    -) assigns default options
    -) parses command line options
    -) checks for invalid user input
    """
    def __init__(self):
        """Assign default options"""

        # Common user settings
        self.verbosity = 1
        self.audio = False
        self.size_limit = 3
        self.passes = 2
        self.undershoot = 0.75
        self.iterations = 3
        self.threads = 1
        self.force_stereo = False
        self.basic_format = False
        # Subtitle options
        self.subtitles = False
        self.mkv_fallback = False
        self.burn_subs = False
        # Advanced video options
        self.v_codec = "libvpx"
        self.crf = False
        self.no_qmax = False
        self.bpp_thresh = 0.075
        self.transparency = False
        self.pix_fmt = "yuv420p"
        self.min_height = 240
        self.min_fps = 24
        # Advanced audio settings
        self.a_codec = "libvorbis"
        self.no_copy = False
        self.force_copy = False
        self.min_audio = 24
        # Misc settings
        self.no_filter_firstpass = False
        self.ffmpeg_verbosity = "stats"
        self.color = True
        self.debug = False

        # Advanced user settings
        self.fps_list = [60, 30, 25, 24, 22, 20, 18, 16, 14, 12, 10, 8, 6, 4, 2, 1]
        self.audio_test_dur = 60      # 0 for whole stream -> exact bitrate
        self.fallback_bitrate = 1     # Must be >0
        self.height_reduction = 10
        self.min_quality = 50
        self.crf_value = 10
        self.min_bitrate_ratio = 0.9
        self.skip_limit = 0.01
        self.audio_factor = 5.5
        self.fallback_codec = "libvorbis"
        self.temp_name = "temp"
        self.out_dir_name = "webm_done"

        # Initializations, which shouldn't be touched
        self.input_list = []

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def parse_options(self):
        """Parse command line arguments"""

        with_argument = ["-s", "--size",
                         "-f", "--filters",
                         "-p", "--passes",
                         "-u", "--undershoot",
                         "-i", "--iterations",
                         "-t", "--threads",
                         "-ss", "--start",
                         "-to", "--end",
                         "--bpp",
                         "--pix-fmt",
                         "--min-height",
                         "--max-height",
                         "--min-fps",
                         "--max-fps",
                         "--min-audio",
                         "--max-audio",
                         "--ffmpeg-verbosity"]

        position = 1
        while position < len(sys.argv):
            option = sys.argv[position]
            if option in with_argument:
                try:
                    argument = sys.argv[position+1]
                except IndexError:
                    err("Missing value for ", option, "!", sep="")
                    sys.exit(err_option)

            try:
                # Common options
                if option in ("-h", "--help"):
                    usage()
                    sys.exit(0)
                elif option in ("-q", "--quiet"):
                    self.verbosity = 0
                elif option in ("-v", "--verbose"):
                    self.verbosity = 2
                elif option in ("-a", "--audio"):
                    self.audio = True
                elif option in ("-s", "--size"):
                    self.size_limit = float(argument)
                elif option in ("-f", "--filters"):
                    self.user_filters = argument
                elif option in ("-p", "--passes"):
                    self.passes = int(argument)
                elif option in ("-u", "--undershoot"):
                    self.undershoot = float(argument)
                elif option in ("-i", "--iterations"):
                    self.iterations = int(argument)
                elif option in ("-t", "--threads"):
                    self.threads = int(argument)
                elif option in ("-ss", "--start"):
                    self.global_start = parse_time(argument)
                elif option in ("-to", "--end"):
                    self.global_end = parse_time(argument)
                elif option in ("-fs", "--force-stereo"):
                    self.force_stereo = True
                elif option in ("-bf", "--basic-format"):
                    self.basic_format = True
                # Subtitle options
                elif option == "--subtitles":
                    self.subtitles = True
                elif option == "--mkv-fallback":
                    self.mkv_fallback = True
                elif option == "--burn-subs":
                    self.burn_subs = True
                # Advanced video options
                elif option == "--vp9":
                    self.v_codec = "libvpx-vp9"
                elif option == "--crf":
                    self.crf = True
                elif option == "--no-qmax":
                    self.no_qmax = True
                elif option == "--bpp":
                    self.bpp_thresh = float(argument)
                elif option == "--transparency":
                    self.transparency = True
                    self.pix_fmt = "yuva420p"
                elif option == "--pix-fmt":
                    self.pix_fmt = argument
                elif option == "--min-height":
                    self.min_height = int(argument)
                elif option == "--max-height":
                    self.max_height = int(argument)
                elif option == "--min-fps":
                    self.min_fps = float(argument)
                elif option == "--max-fps":
                    self.max_fps = float(argument)
                # Advanced audio options
                elif option == "--opus":
                    self.a_codec = "libopus"
                elif option == "--no-copy":
                    self.no_copy = True
                elif option == "--force-copy":
                    self.force_copy = True
                elif option == "--min-audio":
                    self.min_audio = int(argument)
                elif option == "--max-audio":
                    self.max_audio = int(argument)
                # Misc. options
                elif option == "--no-filter-firstpass":
                    self.no_filter_firstpass = True
                elif option == "--ffmpeg-verbosity":
                    self.ffmpeg_verbosity = argument
                elif option == "--no-color":
                    self.color = False
                elif option == "--debug":
                    self.debug = True
                # Files and unknown arguments
                elif fnmatch(option, "-*"):
                    err("Unknown flag '", option, "'!", sep="")
                    err("Try '", os.path.basename(sys.argv[0]), \
                        " --help' for more information.", sep="")
                    sys.exit()
                else:
                    if os.path.isfile(option):
                        self.input_list.append(os.path.abspath(option))
                    else:
                        err("'", option, "' is no valid file.", sep="")
                        sys.exit()
            except ValueError:
                err("Invalid ", option, " ('", argument, "')!", sep="")
                sys.exit(err_option)

            if option in with_argument:
                position += 2
            else:
                position += 1

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def check_options(self):
        """Check validity of command line options"""

        # Special integer checks
        if self.passes not in (1, 2):
            err("Only 1 or 2 passes are supported!")
            sys.exit(err_option)
        elif self.iterations < 1:
            err("Script needs at least 1 iteration per mode!")
            sys.exit(err_option)
        elif self.min_height <= 0:
            err("Min. height must be greater than 0!")
            sys.exit(err_option)
        elif hasattr(self, "max_height") and self.max_height < self.min_height:
            err("Max. height can't be less than min. height!")
            sys.exit(err_option)
        elif self.threads <= 0:
            err("Thread count must be larger than 0!")
            sys.exit(err_option)
        elif self.threads > 16:
            # Just a warning
            err("More than 16 threads are not recommended.")
        elif hasattr(self, "max_audio") and self.max_audio < 6:
            err("Max. audio channel bitrate must be greater than 6 Kbps!")
            sys.exit(err_option)
        elif hasattr(self, "max_audio") and self.max_audio < self.min_audio:
            err("Max. audio channel bitrate can't be less than min. audio channel bitrate!")
            sys.exit(err_option)

        # Special float checks
        if self.size_limit <= 0:
            err("Target file size must be greater than 0!")
            sys.exit(err_option)
        elif hasattr(self, "global_end") and self.global_end <= 0:
            err("End time must be greater than 0!")
            sys.exit(err_option)
        elif hasattr(self, "global_start") and hasattr(self, "global_end") and \
             self.global_end <= self.global_start:
            err("End time must be greater than start time!")
            sys.exit(err_option)
        elif self.undershoot > 1:
            err("Undershoot ratio can't be greater than 1!")
            sys.exit(err_option)
        elif self.bpp_thresh <= 0:
            err("Bits per pixel threshold must be greater than 0!")
            sys.exit(err_option)
        elif hasattr(self, "max_fps") and self.max_fps < 1:
            err("Max. frame rate can't be less than 1!")
            sys.exit(err_option)
        elif hasattr(self, "max_fps") and self.max_fps < self.min_fps:
            err("Max. frame rate can't be less than min. frame rate!")
            sys.exit(err_option)

        # Check for mutually exclusive flags
        if self.force_copy and self.no_copy:
            err("--force-copy and --no-copy are mutually exclusive!")
            sys.exit(err_option)

        # Misc. checks
        if not self.input_list:
            err("No input files specified!")
            sys.exit(err_option)
        elif self.transparency and self.pix_fmt != "yuva420p":
            err("Only yuva420p supports transparency!")
            sys.exit(err_option)

        vp8_pix_fmt = ["yuv420p", "yuva420p"]
        vp9_pix_fmt = ["yuv420p", "yuva420p",
                       "yuv422p", "yuv440p", "yuv444p",
                       "yuv420p10le", "yuv422p10le", "yuv440p10le", "yuv444p10le",
                       "yuv420p12le", "yuv422p12le", "yuv440p12le", "yuv444p12le",
                       "gbrp", "gbrp10le", "gbrp12le"]

        if self.v_codec == "libvpx" and self.pix_fmt not in vp8_pix_fmt:
            err("'", self.pix_fmt, "' isn't supported by VP8!", sep="")
            err("See 'ffmpeg -h encoder=libvpx' for more infos.")
            sys.exit(err_option)
        elif self.v_codec == "libvpx-vp9" and self.pix_fmt not in vp9_pix_fmt:
            err("'", self.pix_fmt, "' isn't supported by VP9!", sep="")
            err("See 'ffmpeg -h encoder=libvpx-vp9' for more infos.")
            sys.exit(err_option)

        supported_verbosity = ["quiet", "panic", "fatal",
                               "error", "warning", "info",
                               "verbose", "debug", "trace",
                               "stats"]

        if self.ffmpeg_verbosity not in supported_verbosity:
            err("'", self.ffmpeg_verbosity, \
                "' isn't a supported FFmpeg verbosity level!", sep="")
            err("Supported levels:")
            err("  stats quiet panic fatal error warning info verbose debug trace")
            sys.exit(err_option)

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def check_user_filters(self):
        """Test user set filters"""

        self.audio_filters = False
        self.video_filters = False

        if not hasattr(self, "user_filters"):
            return

        # existing filters let copy fail
        # only crude test; stream specifiers will let it fail as well
        command = ["ffmpeg", "-v", "quiet",
                   "-f", "lavfi", "-i", "nullsrc",
                   "-f", "lavfi", "-i", "anullsrc",
                   "-t", "1", "-c:v", "copy",
                   "-filter_complex", self.user_filters,
                   "-f", "null", "-"]
        try:
            subprocess.check_call(command)
        except subprocess.CalledProcessError:
            self.video_filters = True

        command = ["ffmpeg", "-v", "quiet",
                   "-f", "lavfi", "-i", "nullsrc",
                   "-f", "lavfi", "-i", "anullsrc",
                   "-t", "1", "-c:a", "copy",
                   "-filter_complex", self.user_filters,
                   "-f", "null", "-"]
        try:
            subprocess.check_call(command)
        except subprocess.CalledProcessError:
            self.audio_filters = True

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Classes
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

class Values_Assembler:
    """Gathers information about output settings"""
    def __init__(self):
        """Initialize all properties"""

        self.trim = {}
        self.audio = {}
        self.video = {}
        self.filter = {}

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def calculate_trim_values(self, in_file, input_info):
        """Calculate values regarding trim settings"""

        try:
            duration = float(input_info['format']['duration'])
        except KeyError:
            # Brute-force detect, if ffprobe can't get duration (i.e. GIFs or other images)
            # Encodes input as AVC (fast) and reads duration from the output
            command = ["ffmpeg", "-y", "-v", "error",
                       "-i", in_file, "-map", "0:v",
                       "-c:v", "libx264", "-preset", "ultrafast", "-crf", "51",
                       options.temp_name + ".mkv"]
            subprocess.run(command)

            command = ["ffprobe", "-v", "error",
                       "-show_format", "-show_streams",
                       "-print_format", "json", options.temp_name + ".mkv"]
            output_info = subprocess.run(command, stdout=subprocess.PIPE).stdout
            output_info = json.loads(output_info)

            duration = float(output_info['format']['duration'])

        start = 0
        end = duration

        if hasattr(options, "global_start") and options.global_start < duration:
            start = options.global_start
        if hasattr(options, "global_end") and options.global_end <= duration:
            end = options.global_end

        self.trim['dur'] = round(end - start, 3)

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def calculate_audio_values(self, input_info):
        """Calculate values regarding audio settings"""

        max_size = int(options.size_limit*1024**2)

        self.audio['bitrate'] = 0
        self.audio['streams'] = 0
        self.audio['channels'] = 0
        self.audio['#'] = []
        # 44100 is an arbitrary value to check later change
        self.audio['rate'] = 44100

        if not options.audio:
            return

        stream_count = int(input_info['format']['nb_streams'])

        for stream in range(stream_count):
            if input_info['streams'][stream]['codec_type'] == "audio":
                if options.force_stereo:
                    channels = 2
                else:
                    channels = int(input_info['streams'][stream]['channels'])

                self.audio['#'].append(channels)
                self.audio['channels'] += channels
                self.audio['streams'] += 1

                if options.basic_format:
                    break

        # formula originally based on my experience with stereo audio for 4MB WebMs
        # later on extended to accommodate more bitrates / channels
        factor = max_size*8 / (self.trim['dur']*self.audio['channels']*4*1000)
        # Audio factor decides how much of the size limit gets reserved for audio
        factor /= options.audio_factor

        if factor < 1:
            channel_bitrate = 6
        elif factor < 2:
            channel_bitrate = 8
        elif factor < 3:
            channel_bitrate = 12
        elif factor < 4:
            channel_bitrate = 16
        elif factor < 6:
            channel_bitrate = 24
        elif factor < 8:
            channel_bitrate = 32
        elif factor < 28:
            channel_bitrate = 48
        elif factor < 72:
            channel_bitrate = 64
        elif factor < 120:
            channel_bitrate = 80
        else:
            channel_bitrate = 96

        if channel_bitrate < options.min_audio:
            channel_bitrate = options.min_audio
        if hasattr(options, "max_audio") and channel_bitrate > options.max_audio:
            channel_bitrate = options.max_audio

        for stream in range(self.audio['streams']):
            self.audio['#'][stream] *= channel_bitrate
            self.audio['bitrate'] += self.audio['#'][stream]

        # Downsample necessary for lower bitrates with libvorbis
        if channel_bitrate <= 6:
            self.audio['rate'] = 8000
        elif channel_bitrate <= 12:
            self.audio['rate'] = 12000
        elif channel_bitrate <= 16:
            self.audio['rate'] = 24000

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def calculate_video_values(self):
        """Calculate values regarding video settings"""

        max_size = int(options.size_limit*1024**2)

        self.video['bitrate'] = int(max_size*8 \
                                    / (self.trim['dur']*1000) \
                                    - self.audio['bitrate'])

        if self.video['bitrate'] <= 0:
            self.video['bitrate'] = options.fallback_bitrate

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def calculate_filter_values(self, in_file, input_info, bitrate):
        """Calculate values regarding (script) filter settings"""

        # Test for user set scale/fps filter
        if hasattr(options, "user_filters"):
            user_scale = "scale" in options.user_filters
            user_fps = "fps" in options.user_filters
        else:
            user_scale = False
            user_fps = False

        height = input_info['streams'][0]['height']
        width = input_info['streams'][0]['width']
        aspect_ratio = width/height

        raw_fps = input_info['streams'][0]['r_frame_rate'].split("/")
        if raw_fps == 2:
            fps = int(raw_fps[0])/int(raw_fps[0])
        else:
            fps = float(raw_fps[0])

        # If user scale/fps filter -> test encode
        # Read the effect (i.e. changed resolution / frame rate) from output
        if user_scale or user_fps:
            command = ["ffmpeg", "-y", "-v", "error",
                       "-i", in_file, "-vframes", "1",
                       "-filter_complex", options.user_filters,
                       options.temp_name + ".mkv"]
            subprocess.run(command)

            command = ["ffprobe", "-v", "error",
                       "-show_format", "-show_streams",
                       "-print_format", "json",
                       options.temp_name + ".mkv"]
            output_info = subprocess.run(command, stdout=subprocess.PIPE).stdout
            output_info = json.loads(output_info)

            height = output_info['streams'][0]['height']
            width = output_info['streams'][0]['width']
            aspect_ratio = width/height

            raw_fps = output_info['streams'][0]['r_frame_rate'].split("/")
            if raw_fps == 2:
                fps = int(raw_fps[0])/int(raw_fps[0])
            else:
                fps = float(raw_fps[0])

        self.filter['in_height'] = height
        self.filter['out_height'] = height
        self.filter['in_fps'] = fps
        self.filter['out_fps'] = fps

        if user_scale and user_fps:
            return

        # Perform frame rate drop
        for new_fps in options.fps_list:
            if user_fps:
                break

            bpp = bitrate*1000 / (fps*aspect_ratio*height**2)
            if bpp >= options.bpp_thresh/2:
                break
            fps = new_fps

        # Enfore frame rate thresholds
        if fps < options.min_fps:
            fps = options.min_fps
        if hasattr(options, "max_fps") and fps > options.max_fps:
            fps = options.max_fps
        if fps > self.filter['in_fps']:
            fps = self.filter['in_fps']
        self.filter['out_fps'] = fps

        # Perform downscale
        while True:
            if user_scale:
                break

            bpp = bitrate*1000 / (fps*aspect_ratio*height**2)
            if bpp >= options.bpp_thresh:
                break
            height -= options.height_reduction

        # Enforce height thresholds
        if height < options.min_height:
            height = options.min_height
        if hasattr(options, "max_height") and height > options.max_height:
            height = options.max_height
        if height > self.filter['in_height']:
            height = self.filter['in_height']
        self.filter['out_height'] = height

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

class Settings_Assembler:
    """Assembles FFmpeg settings"""
    def __init__(self):
        """Initialize all properties"""
        self.verbosity = []
        self.input = []
        self.map = []
        self.subtitle = []
        self.audio = []
        self.video = []
        self.filter = []

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def get_verbosity_settings(self):
        """Assemble FFmpeg settings regarding verbosity"""

        if options.ffmpeg_verbosity == "stats":
            self.verbosity.extend(["-v", "error", "-stats"])
        else:
            self.verbosity.extend(["-v", options.ffmpeg_verbosity])

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def get_input_settings(self, in_file, input_info, values):
        """Assemble FFmpeg settings regarding input/trimming"""

        in_dur = float(input_info['format']['duration'])

        if hasattr(options, "global_start") and \
           options.global_start < in_dur:
            self.input.extend(["-ss", str(options.global_start)])
        self.input.extend(["-i", in_file])
        if hasattr(options, "global_end") and \
           options.global_end <= in_dur:
            self.input.extend(["-t", str(values.trim['dur'])])

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def get_map_settings(self, values):
        """Assemble FFmpeg settings regarding mapping"""

        self.map.extend(["-map", "0:v"])

        for stream in range(values.audio['streams']):
            if not options.audio:
                break
            self.map.extend(["-map", "0:a:" + str(stream) + "?"])
            if options.basic_format:
                break

        if options.subtitles:
            self.map.extend(["-map", "0:s?"])

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def get_subtitle_settings(self, in_file):
        """Assemble FFmpeg settings regarding subtitles"""

        if not options.subtitles:
            return

        if options.burn_subs:
            self.subtitle.extend(["-sn"])
        elif output_image_subtitles(in_file):
            self.subtitle.extend(["-c:s", "copy"])
        else:
            self.subtitle.extend(["-c:s", "webvtt"])

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def get_audio_settings(self, in_file, values):
        """Assemble FFmpeg settings regarding audio"""

        if not options.audio:
            return

        for stream in range(values.audio['streams']):
            if audio_copy(in_file, stream, values.audio['#'][stream]):
                self.audio.extend(["-c:a:" + str(stream), "copy"])
            elif options.a_codec == "libopus" and opus_fallback(in_file, stream):
                self.audio.extend(["-c:a:" + str(stream), options.fallback_codec])
                self.audio.extend(["-b:a:" + str(stream),
                                   str(values.audio['#'][stream]) + "K"])
            else:
                self.audio.extend(["-c:a:" + str(stream), options.a_codec])
                self.audio.extend(["-b:a:" + str(stream),
                                   str(values.audio['#'][stream]) + "K"])

            if options.basic_format:
                break

        # -ac/-ar have no effect without audio encoding
        # there's no need for additional checks
        if options.force_stereo:
            self.audio.extend(["-ac", "2"])
        if values.audio['rate'] < 44100:
            self.audio.extend(["-ar", values.audio['rate']])

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def get_video_settings(self, mode, bitrate):
        """Assemble FFmpeg settings regarding video"""

        # Function gets called several times for a file
        # Resetting necessary
        self.video = []

        self.video.extend(["-c:v", options.v_codec])
        self.video.extend(["-deadline", "good"])
        # -cpu-used defined in call_ffmpeg, since it depends on the pass

        # TO-DO:
        # Test how strong temporal filtering influences high quality encodes
        # Figure out how/why alpha channel support cuts short GIFs during 2-pass
        self.video.extend(["-pix_fmt", options.pix_fmt])

        if options.pix_fmt == "yuva420p":
            self.video.extend(["-auto-alt-ref", "0"])
        else:
            self.video.extend(["-auto-alt-ref", "1",
                               "-lag-in-frames", "25",
                               "-arnr-maxframes", "15",
                               "-arnr-strength", "6"])

        self.video.extend(["-b:v", str(bitrate) + "K"])

        if options.crf and mode in (1, 2):
            self.video.extend(["-crf", str(options.crf_value)])

        if mode == 1:
            self.video.extend(["-qmax", str(options.min_quality)])
        elif mode == 3:
            self.video.extend(["-minrate:v", str(bitrate) + "K",
                               "-maxrate:v", str(bitrate) + "K"])

        self.video.extend(["-threads", str(options.threads)])

        # This check isn't necessary, but it avoids command bloat
        if options.v_codec == "libvpx-vp9" and options.threads > 1:
            self.video.extend(["-tile-columns", "6",
                               "-tile-rows", "2",
                               "-row-mt", "1"])

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    def get_filter_settings(self, values):
        """Assemble (script) filter string"""

        # Function gets called several times for a file
        # Resetting necessary
        self.filter = []

        out_height = values.filter['out_height']
        out_fps = values.filter['out_fps']
        in_height = values.filter['in_height']
        in_fps = values.filter['in_fps']

        scale_string = "scale=-2:" + str(out_height) + ":flags=lanczos"
        fps_string = "fps=" + str(out_fps)

        if out_height < in_height and out_fps < in_fps:
            self.filter.extend(["-vf", scale_string + "," + fps_string])
        elif out_height < in_height:
            self.filter.extend(["-vf", scale_string])
        elif out_fps < in_fps:
            self.filter.extend(["-vf", fps_string])

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def err(*args, **kwargs):
    """Print to stderr"""
    print(*args, file=sys.stderr, **kwargs)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def usage():
    """Print help text"""

    print(
"""Usage: restrict.py [OPTIONS] INPUT [INPUT]...

Input:
  Absolute or relative path to a video/image

Common options:
  -h,  --help               show help
  -q,  --quiet              suppress non-error output
  -v,  --verbose            print verbose information
  -a,  --audio              enable audio output
  -s,  --size SIZE          limit max. output file size in MB (def: 3)
  -f,  --filters FILTERS    use custom ffmpeg filters
  -p,  --passes {1,2}       specify number of passes (def: 2)
  -u,  --undershoot RATIO   specify undershoot ratio (def: 0.75)
  -i,  --iterations ITER    iterations for each bitrate mode (def: 3)
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
  --bpp BPP                 set custom bpp threshold (def: 0.075)
  --transparency            preserve input transparency
  --pix-fmt FORMAT          choose color space (def: yuv420p)
  --min-height HEIGHT       force min. output height (def: 240)
  --max-height HEIGHT       force max. output height
  --min-fps FPS             force min. frame rate (def: 24)
  --max-fps FPS             force max. frame rate

Advanced audio options:
  --opus                    use and allow Opus as audio codec
  --no-copy                 disable stream copying
  --force-copy              force-copy compatible (!) audio streams
  --min-audio RATE          force min. channel bitrate in Kbps (def: 24)
  --max-audio RATE          force max. channel bitrate in Kbps

Misc. options:
  --no-filter-firstpass     disable user filters during the first pass
  --ffmpeg-verbosity LEVEL  change FFmpeg command verbosity (def: stats)
  --no-color                disable colorized output
  --debug                   only print ffmpeg commands

All output will be saved in 'webm_done/'.
'webm_done/' is located in the same directory as the input.

For more information visit:
https://github.com/HelpSeeker/Restricted-WebM-in-Bash/wiki"""
    )

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def check_requirements():
    """check existence of required software"""

    requirements = ["ffmpeg", "ffprobe"]

    for requirement in requirements:
        try:
            subprocess.run([requirement], stdout=subprocess.DEVNULL, \
                                          stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            err("Error: ", requirement, " not found!", sep="")
            sys.exit()

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def parse_time(in_time):
    """Parse input time syntax and check for validity"""

    # Check FFmpeg support
    # Easiest to just test it with ffmpeg (reasonable fast even for >1h durations)
    command = ["ffmpeg", "-v", "quiet",
               "-f", "lavfi", "-i", "anullsrc",
               "-t", in_time, "-c", "copy",
               "-f", "null", "-"]
    try:
        subprocess.check_call(command)
    except subprocess.CalledProcessError:
        err("Invalid time ('", in_time, "')! For the supported syntax see:", sep="")
        err("https://ffmpeg.org/ffmpeg-utils.html#time-duration-syntax")
        sys.exit(err_option)

    time_array = in_time.split(":")
    if len(time_array) == 3:
        time_in_sec = 3600*int(time_array[0]) + 60*int(time_array[1]) + \
                      float(time_array[2])
    elif len(time_array) == 2:
        time_in_sec = 60*int(time_array[0]) + float(time_array[1])
    elif len(time_array) == 1:
        time_in_sec = float(time_array[0])

    return time_in_sec

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def print_options():
    """Print all settings for verbose output"""

    max_size = int(options.size_limit*1024**2)
    min_size = int(options.size_limit*1024**2*options.undershoot)

    if options.color:
        print(color_verbose_header, end="")
    print("\n### Settings for the current session ###\n", end=reset_color+"\n")

    print("Paths:")
    print("  Temporary filename:         ", options.temp_name)
    print("  Destination directory name: ", options.out_dir_name)
    print()
    print("Size:")
    print("  Max. size (MB):             ", options.size_limit)
    print("  Undershoot ratio:           ", options.undershoot)
    print("  Max. size (Bytes):          ", max_size)
    print("  Min. size (Bytes):          ", min_size)
    print()
    print("Trimming:")
    if hasattr(options, "global_start"):
        print("  Start time (sec):           ", options.global_start)
    if hasattr(options, "global_end"):
        print("  End time (sec):             ", options.global_end)
    print()
    print("Video:")
    print("  Encoder:                    ", options.v_codec)
    print("  Passes:                     ", options.passes)
    print("  Threads:                    ", options.threads)
    print("  Color space:                ", options.pix_fmt)
    print("  Use CQ instead of VBR:      ", options.crf)
    print("  CRF:                        ", options.crf_value)
    print("  qmax:                       ", options.min_quality)
    print("  Fallback bitrate (Kbps):    ", options.fallback_bitrate)
    print("  Omit min. quality qmax:     ", options.no_qmax)
    print("  Iterations/bitrate mode:    ", options.iterations)
    print("  Mode skip threshold:        ", options.skip_limit)
    print("  Min. bitrate ratio:         ", options.min_bitrate_ratio)
    print()
    print("Audio:")
    print("  Audio output:               ", options.audio)
    print("  Encoder:                    ", options.a_codec)
    print("  Fallback encoder:           ", options.fallback_codec)
    print("  Force stereo:               ", options.force_stereo)
    print("  Min. channel bitrate (Kbps):", options.min_audio)
    if hasattr(options, "max_audio"):
        print("  Max. channel bitrate (Kbps):", options.max_audio)
    print("  Stream copying disabled:    ", options.no_copy)
    print("  Ignore bitrate for copying: ", options.force_copy)
    print("  Bitrate test duration (sec):", options.audio_test_dur)
    print("  Audio factor:               ", options.audio_factor)
    print()
    print("Subtitles:")
    print("  Subtitle support:           ", options.subtitles)
    print("  MKV as fallback:            ", options.mkv_fallback)
    print("  Discard after hardsubbing:  ", options.burn_subs)
    print()
    print("Filters:")
    if hasattr(options, "user_filters"):
        print("  User filters:               ", options.user_filters)
    print("  Contains video filters:     ", options.video_filters)
    print("  Contains audio filters:     ", options.audio_filters)
    print("  Omit during 1st pass:       ", options.no_filter_firstpass)
    print("  BPP threshold:              ", options.bpp_thresh)
    print("  Min. height threshold:      ", options.min_height)
    if hasattr(options, "max_height"):
        print("  Max. height threshold:      ", options.max_height)
    print("  Height reduction step:      ", options.height_reduction)
    print("  Min. frame rate threshold:  ", options.min_fps)
    if hasattr(options, "max_fps"):
        print("  Max. frame rate threshold:  ", options.max_fps)
    print("  Possible frame rates:       ", options.fps_list)
    print()
    print("Misc.:")
    print("  Only 1 video/audio stream:  ", options.basic_format)
    print("  FFmpeg verbosity level:     ", options.ffmpeg_verbosity)
    print("  Debug mode:                 ", options.debug)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def print_general_settings(settings, output):
    """Print general (i.e. not adjusted during iterations) settings"""

    if options.color:
        print(color_general_settings, end="")

    print("  Verbosity: ", settings.verbosity)
    print("  Input/trim:", settings.input)
    print("  Mapping:   ", settings.map)
    print("  Audio:     ", settings.audio)
    print("  Subtitles: ", settings.subtitle)
    print("  Output:    ", output)
    print(end=reset_color+"\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def print_attempt_settings(settings):
    """Print attempt (i.e. adjusted during iterations) settings"""

    if options.color:
        print(color_attempt_settings, end="")

    print("  Video:     ", settings.video)
    print("  Filters:   ", settings.filter, end=reset_color+"\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def print_size_infos(sizes):
    """Print size information"""

    if options.color:
        print(color_size_infos, end="")

    print("  Curr. size:", sizes['temp'])
    print("  Last size: ", sizes['last'])
    print("  Best try:  ", sizes['out'])
    print(end=reset_color+"\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def resolve_paths(in_path, ext):
    """Handle output path"""

    in_name = os.path.basename(in_path)
    in_name = os.path.splitext(in_name)[0]
    in_dir = os.path.dirname(in_path)

    out_name = in_name + ext
    out_dir = os.path.join(in_dir, options.out_dir_name)
    output = os.path.join(out_dir, out_name)

    if in_name == options.temp_name:
        err(in_path)
        err("Error! Input has reserved filename ('", \
            options.temp_name, "').", sep="")
        sys.exit()

    if not os.path.exists(out_dir):
        os.mkdir(out_dir)
    os.chdir(out_dir)

    return output

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def audio_copy(in_file, stream, out_rate):
    """Decide if input audio stream should be copied"""

    if hasattr(options, "global_start") or \
       options.audio_filters or options.no_copy:
        return False

    # Shorter values speed up test, but only approximate avg. bitrate
    # 0 will copy entire audio stream -> exact
    copy_dur = []
    if options.audio_test_dur:
        copy_dur = ["-t", str(options.audio_test_dur)]

    command = ["ffmpeg", "-y", "-v", "error",
               "-i", in_file]
    command.extend(copy_dur)
    command.extend(["-map", "0:a:" + str(stream),
                    "-c", "copy", options.temp_name + ".mkv"])
    subprocess.run(command)

    command = ["ffprobe", "-v", "error",
               "-show_format", "-show_streams",
               "-print_format", "json",
               options.temp_name + ".mkv"]
    output_info = subprocess.run(command, stdout=subprocess.PIPE).stdout
    output_info = json.loads(output_info)

    in_rate = output_info['format']['bit_rate']
    in_codec = output_info['streams'][0]['codec_name']

    codec_list = ["vorbis"]
    if options.a_codec == "libopus":
        codec_list.append("opus")

    # *1.05 since bitrate allocation is no exact business
    if in_codec in codec_list and \
       options.force_copy and in_rate <= out_rate*1000*1.05:
        return True

    return False

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def opus_fallback(in_file, stream):
    """Test if audio fallback encoder is necessary"""

    if options.force_stereo:
        return False

    # Certain channel configurations will throw an error
    # See: https://trac.ffmpeg.org/ticket/5718
    command = ["ffmpeg", "-v", "quiet",
               "-i", in_file, "-t", "1",
               "-map", "0:a:" + str(stream),
               "-c:a", "libopus", "-f", "null", "-"]

    try:
        subprocess.check_call(command)
    except subprocess.CalledProcessError:
        return True

    return False

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def output_image_subtitles(in_file):
    """Test if output would include image-based subtitles"""

    if not options.subtitles or options.burn_subs:
        return False

    # FFmpeg only supports text->text and bitmap->bitmap conversions
    # bitmap->text in general is a complex topic
    command = ["ffmpeg", "-v", "quiet",
               "-i", in_file, "-t", "1",
               "-map", "0:s?", "-c:s", "webvtt",
               "-f", "null", "-"]

    try:
        subprocess.check_call(command)
    except subprocess.CalledProcessError:
        return True

    return False

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def call_ffmpeg(out_path, settings):
    """Execute FFmpeg (and assemble pass specific settings)"""

    raw_video = ["-c:v", "copy"]
    raw_audio = ["-c:a", "copy"]
    raw_filter = []
    if hasattr(options, "global_start") or options.video_filters:
        raw_video = ["-c:v", "rawvideo"]
    if hasattr(options, "global_start") or options.audio_filters:
        raw_audio = ["-c:a", "pcm_s16le"]
    if hasattr(options, "user_filters"):
        raw_filter = ["-filter_complex", options.user_filters]

    for ffmpeg_pass in range(1, options.passes+1):
        if options.passes == 1:
            pass_settings = ["-cpu-used", "0", out_path]
        elif ffmpeg_pass == 1:
            pass_settings = ["-cpu-used", "5", "-pass", "1", "-f", "null", "-"]
            if options.no_filter_firstpass:
                raw_filter = []
            if os.path.exists("ffmpeg2pass-0.log"):
                continue
        elif ffmpeg_pass == 2:
            pass_settings = ["-cpu-used", "0", "-pass", "2", out_path]
            if options.no_filter_firstpass and \
               hasattr(options, "user_filters"):
                raw_filter = ["-filter_complex", options.user_filters]

        if hasattr(options, "user_filters"):
            raw_command = ["ffmpeg", "-y", "-v", "error"]
            raw_command.extend(settings.input)
            raw_command.extend(settings.map)
            raw_command.extend(raw_video)
            raw_command.extend(raw_audio)
            raw_command.extend(["-c:s", "copy"])
            raw_command.extend(raw_filter)
            raw_command.extend(["-strict", "-2", "-f", "matroska", "-"])

        webm_command = ["ffmpeg", "-y"]
        webm_command.extend(settings.verbosity)
        if hasattr(options, "user_filters"):
            webm_command.extend(["-i", "-", "-map", "0"])
        else:
            webm_command.extend(settings.input)
            webm_command.extend(settings.map)
        webm_command.extend(settings.video)
        webm_command.extend(settings.audio)
        webm_command.extend(settings.subtitle)
        webm_command.extend(settings.filter)
        webm_command.extend(pass_settings)

        if options.debug:
            if hasattr(options, "user_filters"):
                print(raw_command)
            print(webm_command)
        else:
            if hasattr(options, "user_filters"):
                raw_out = subprocess.Popen(raw_command, \
                                           stdout=subprocess.PIPE, \
                                           bufsize=10**8)
                subprocess.run(webm_command, stdin=raw_out.stdout)
            else:
                subprocess.run(webm_command)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def limit_size(in_file, temp_file, out_file, input_info, values, settings):
    """Limit output size to be <=max_size"""

    max_size = int(options.size_limit*1024**2)

    sizes = {
        'user': 0,
        'temp': 0,
        'last': 0,
        'out': 0
    }

    modes = 3
    for mode in range(1, modes+1):
        if mode == 1 and options.no_qmax:
            continue

        for iteration in range(1, options.iterations+1):
            # Reset bitrate for each bitrate mode
            if iteration == 1:
                bitrate = values.video['bitrate']
            # Force min. decrease (% of last bitrate; default: 90%)
            elif bitrate*max_size/sizes['temp'] > bitrate*options.min_bitrate_ratio:
                bitrate = int(bitrate*options.min_bitrate_ratio)
            else:
                bitrate = int(bitrate*max_size/sizes['temp'])

            if bitrate <= 0:
                bitrate = options.fallback_bitrate

            values.calculate_filter_values(in_file, input_info, bitrate)
            settings.get_video_settings(mode, bitrate)
            settings.get_filter_settings(values)

            if options.verbosity >= 1:
                if options.color:
                    print(color_attempt_info, end="")
                print("Mode: {} (of 3)".format(mode), end=" | ")
                print("Attempt: {} ".format(iteration), end="")
                print("(of {})".format(options.iterations), end=" | ")
                print("Height: {}".format(values.filter['out_height']), end=" | ")
                print("FPS: {}".format(values.filter['out_fps']), end=reset_color+"\n")
            if options.verbosity >= 2:
                print_attempt_settings(settings)

            call_ffmpeg(temp_file, settings)

            # Debug doesn't produce output; specify manually
            if options.debug:
                sizes['user'] = int(input("Output size in MB: "))
                sizes['last'] = sizes['temp']
                sizes['temp'] = int(sizes['user']*1024**2)
                if not sizes['out'] or sizes['temp'] < sizes['out']:
                    sizes['out'] = sizes['temp']
            else:
                sizes['last'] = sizes['temp']
                sizes['temp'] = os.path.getsize(temp_file)
                if not sizes['out'] or sizes['temp'] < sizes['out']:
                    os.replace(temp_file, out_file)
                    sizes['out'] = sizes['temp']

            if options.verbosity >= 2:
                print_size_infos(sizes)

            # Skip remaining iters, if change too small (defaul: <1%)
            
            if iteration != 1:
                diff = abs((sizes['temp']-sizes['last']) / sizes['last'])
                if diff < options.skip_limit:
                    break
            if sizes['out'] <= max_size:
                break

        if sizes['out'] <= max_size:
            break

    exit_info = {
        'mode': mode,
        'bitrate': bitrate,
        'sizes': sizes
    }

    return exit_info

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def enhance_size(in_file, temp_file, out_file, input_info, limit_info, values, settings):
    """Enhance output size to be >=min_size (and still <=max_size)"""

    max_size = int(options.size_limit*1024**2)
    min_size = int(options.size_limit*1024**2*options.undershoot)

    sizes = limit_info['sizes']

    mode = limit_info['mode']
    bitrate = limit_info['bitrate']

    for iteration in range(1, options.iterations+1):
        if min_size <= sizes['out'] <= max_size:
            break

        # Force min. decrease (% of last bitrate; default: 90%)
        if bitrate*max_size/sizes['temp'] < bitrate and \
           bitrate*max_size/sizes['temp'] > bitrate*options.min_bitrate_ratio:
            bitrate = int(bitrate*options.min_bitrate_ratio)
        else:
            bitrate = int(bitrate*max_size/sizes['temp'])

        if bitrate <= 0:
            bitrate = options.fallback_bitrate

        values.calculate_filter_values(in_file, input_info, bitrate)
        settings.get_video_settings(mode, bitrate)
        settings.get_filter_settings(values)

        if options.verbosity >= 1:
            if options.color:
                print(color_attempt_info, end="")
            print("Enhance Attempt: {} ".format(iteration), end="")
            print("(of {})".format(options.iterations), end=" | ")
            print("Height: {}".format(values.filter['out_height']), end=" | ")
            print("FPS: {}".format(values.filter['out_fps']), end=reset_color+"\n")
        if options.verbosity >= 2:
            print_attempt_settings(settings)

        call_ffmpeg(temp_file, settings)

        # Debug doesn't produce output; specify manually
        if options.debug:
            sizes['user'] = int(input("Output size in MB: "))
            sizes['last'] = sizes['temp']
            sizes['temp'] = int(sizes['user']*1024**2)
            if sizes['temp'] < sizes['out']:
                sizes['out'] = sizes['temp']
        else:
            sizes['last'] = sizes['temp']
            sizes['temp'] = os.path.getsize(temp_file)
            if sizes['out'] < sizes['temp'] <= max_size:
                os.replace(temp_file, out_file)
                sizes['out'] = sizes['temp']

        if options.verbosity >= 2:
            print_size_infos(sizes)

        # Skip remaining iters, if change too small (defaul: <1%)
        diff = abs((sizes['temp']-sizes['last']) / sizes['last'])
        if diff < options.skip_limit:
            break

    exit_info = {
        'mode': mode,
        'bitrate': bitrate,
        'sizes': sizes
    }

    return exit_info

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def clean():
    """Clean leftover file in the workspace"""

    for ext in [".webm", ".mkv"]:
        if os.path.exists(options.temp_name + ext):
            os.remove(options.temp_name + ext)
    if options.passes == 2:
        if os.path.exists("ffmpeg2pass-0.log"):
            os.remove("ffmpeg2pass-0.log")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main script
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def main():
    """Main function body"""
    global size_fail, options

    check_requirements()

    options = Options_Assembler()
    options.parse_options()
    options.check_options()
    options.check_user_filters()

    max_size = int(options.size_limit*1024**2)
    min_size = int(options.size_limit*1024**2*options.undershoot)

    if options.verbosity >= 2:
        print_options()
        if options.color:
            print(color_verbose_header, end="")
        print("\n### Start conversion ###\n", end=reset_color+"\n")

    for video in options.input_list:
        ext = ".webm"

        if options.verbosity >= 1:
            if options.color:
                print(color_current_input, end="")
            print("Current file:", video, end=reset_color+"\n")

        if output_image_subtitles(video):
            if not options.mkv_fallback:
                err(video)
                err("Error: Conversion of image-based subtitles not supported!")
                clean()
                continue
            else:
                ext = ".mkv"

        output = resolve_paths(video, ext)

        command = ["ffprobe", "-v", "error",
                   "-show_format", "-show_streams",
                   "-print_format", "json", video]
        input_info = subprocess.run(command, stdout=subprocess.PIPE).stdout
        input_info = json.loads(input_info)

        # Check for basic stream order assumptions
        # First stream: video stream
        # Everything afterwards: non-video streams
        if not input_info['streams'][0]['codec_type'] == "video":
            err(video)
            err("Error: Unsupported stream order (first stream not video)!")
            clean()
            continue
        try:
            if input_info['streams'][1]['codec_type'] == "video":
                err(video)
                err("Error: More than one video stream per file not supported!")
                clean()
                continue
        except IndexError:
            pass

        values = Values_Assembler()
        values.calculate_trim_values(video, input_info)
        values.calculate_audio_values(input_info)
        values.calculate_video_values()

        settings = Settings_Assembler()
        settings.get_verbosity_settings()
        settings.get_input_settings(video, input_info, values)
        settings.get_map_settings(values)
        settings.get_subtitle_settings(video)
        settings.get_audio_settings(video, values)

        if options.verbosity >= 2:
            print_general_settings(settings, output)

        limit_info = limit_size(video, options.temp_name + ext, output, \
                                input_info, values, settings)
        if limit_info['sizes']['out'] > max_size:
            err(output)
            err("Error: Still too large!")
            size_fail = True
            clean()
            continue

        enhance_info = enhance_size(video, options.temp_name + ext, output, \
                                    input_info, limit_info, values, settings)
        if enhance_info['sizes']['out'] < min_size:
            err(output)
            err("Error: Still too small!")
            size_fail = True

        clean()

# Execute main function
if len(sys.argv) == 1:
    usage()
    sys.exit(0)
try:
    main()
except KeyboardInterrupt:
    err("User Interrupt!")
    clean()
    sys.exit()
if options.verbosity >= 2:
    if options.color:
        print(color_verbose_header)
    print("### Finished ###\n", end=reset_color+"\n")
if size_fail:
    sys.exit(err_size)
sys.exit(0)
