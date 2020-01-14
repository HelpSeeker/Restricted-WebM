#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
from textwrap import dedent, indent

# ANSI escape codes don't work on Windows, unless the user jumps through
# additional hoops (either by using 3rd-party software or enabling VT100
# emulation with Windows 10)
# colorama solves this issue by converting ANSI escape codes into the
# appropriate win32 calls (only on Windows)
# If colorama isn't available, disable colorized output on Windows
colors = True
try:
    import colorama
    colorama.init()
except ModuleNotFoundError:
    if os.name == "nt":
        colors = False

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Global constants
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

class ExitCodes:
    """Store exit codes for non-successful execution."""

    DEP = 1         # missing required software
    OPT = 2         # invalid user-specified option
    RUN = 3         # misc. runtime error
    SIZE = 4        # failed to fit all videos into size range
    INT = 5         # early termination was requested by the user (i.e. Ctrl+C)


class Colors:
    """Store ANSI escape codes for colorized output."""

    # https://en.wikipedia.org/wiki/ANSI_escape_code#Colors
    HEADER = '\033[1;36m'       # Cyan (bold)
    FILE = '\033[35m'           # Magenta
    INFO = '\033[32m'           # Green
    ERROR = '\033[31m'          # Red
    WARNING = '\033[33m'        # Yellow
    SUCCESS = '\033[32m'        # Green
    DEFAULT = '\033[39m'        # Default foreground color
    BOLD = '\033[1m'
    RESET = '\033[0m'

    def disable(self):
        """Disable colorized output by removing escape codes."""
        self.HEADER = ''
        self.FILE = ''
        self.INFO = ''
        self.ERROR = ''
        self.WARNING = ''
        self.SUCCESS = ''
        self.DEFAULT = ''
        self.BOLD = ''
        self.RESET = ''


# Create objects to hold constants
status = ExitCodes()
size_fail = False
fgcolors = Colors()
if not colors:
    fgcolors.disable()

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Classes
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

class DefaultOptions:
    """Stores general options"""

    # Set output verbosity
    #   0 -> quiet mode (only warnings and errors)
    #   1 -> default mode (0 + basic progress information)
    #   2 -> verbose mode (0 + 1 + FFmpeg options + size info)
    verbosity = 1

    # Enable audio output
    # Converts all available audio streams by default
    # Only has an effect, when the input comes with at least one audio stream
    audio = False

    # Upper size limit in MB
    limit = 3

    # FFmpeg filter string (https://ffmpeg.org/ffmpeg-filters.html)
    # Gets passed directly to FFmpeg (and will throw errors if wrong)
    f_user = None

    # Number of passes to use during 1st and 2nd bitrate mode
    # (CBR will always be done with a single pass)
    #   1 -> only really useful for more consistent quality for very low bitrate
    #        encodes or when converting GIFs while preserving transparency
    #   2 -> should always be preferred as libvpx doesn't offer effective
    #        bitrate control for single pass encodes
    passes = 2

    # Lower size limit as percentage of the upper one
    # 0 to disable, >0.95 (or >0.9 with --crf) is discouraged
    under = 0.75

    # How many attempts to make for each bitrate mode
    # This is an upper limit, the remaining attempts of a mode may be skipped
    # if the file size doesn't change enough (<1%)
    iters = 3

    # How many threads libvpx should use
    # FFmpeg discourages >16, but VP8 encoding doesn't scale well beyond 4-6
    threads = 1

    # How to trim the input video (same as FFmpeg's -ss and -to)
    # Values must be in seconds (int/float) or need to be passed to valid_time()
    # Negative time values aren't supported
    global_start = None
    global_end = None

    # Force 2 channels per audio stream
    # Useful to avoid wasting bitrate on surround sound or to use libopus
    # for otherwise unsupported channel configurations
    # IMPORTANT: Also force-converts mono input to stereo
    force_stereo = False

    # Limit the output to 1 video + 1 audio stream (no effect on subtitles)
    basic_format = False

    # Enable subtitle output
    # Input with image-based subtitles will be skipped by default
    subs = False

    # Use MKV as fallback container for input with image-based subtitles,
    # instead of skipping the files entirely
    # Has no effect if subtitle output is disabled
    mkv_fallback = False

    # Map input subtitles, but disable subtitle output
    # Useful to prevent unnecessary soft subs in the output while hardsubbing
    burn_subs = False

    # What video encoder to use
    #   libvpx     -> VP8
    #   libvpv-vp9 -> VP9
    # AV1 (via libaom or libsvt_av1) isn't supported
    v_codec = "libvpx"

    # Use CQ (constrained quality) instead of classic VBR
    crf = False

    # Skip 1st bitrate mode (VBR or CQ + min. quality)
    no_qmax = False

    # Skip 3rd bitrate mode (CBR; also allowed to drop frames)
    no_cbr = False

    # Bits per pixel threshold (steers downscaling and frame rate reduction)
    # Personal recommendations for VP8:
    #   < 0.01: bad quality
    #   ~ 0.04: med quality
    #   > 0.075: good quality
    bpp_thresh = 0.075

    # Preserve input transparency
    # Overrides any value of pix_fmt with "yuva420p"
    transparency = False

    # Pixel format to use
    # See "ffmpeg -h encoder=libvpx(-vp9)" for a full list of supported values
    pix_fmt = "yuv420p"

    # Min. height threshold for automatic downscaling
    # Has no influence on input that is already below the threshold
    min_height = 240

    # Max. height threshold for automatic downscaling
    # Can be used to force-downscale, but has to be higher than min_height
    max_height = None

    # Min. fps threshold for automatic frame rate reduction
    # Has no influence on input that is already below the threshold
    min_fps = 24

    # Max. fps threshold for automatic frame rate reduction
    # Can be used to force a lower frame rate, but has to be higher than min_fps
    max_fps = None

    # What audio encoder to use
    #   libvorbis -> Vorbis
    #   libopus   -> Opus (fails on some surround sound configurations)
    #   opus      -> Opus (not tested, but it should work in theory)
    a_codec = "libvorbis"

    # Disable audio copying (i.e. always reencode all audio)
    no_copy = False

    # Copy audio streams regardless of their bitrate
    # Audio streams will still be reencoded in case of unsupported audio
    # formats, -ss or audio filters
    force_copy = False

    # Min. audio threshold for automatic audio bitrate selection
    # Represents the audio bitrate per channel (e.g. 24 -> 48Kbps for stereo)
    min_audio = 24

    # Max. audio threshold for automatic audio bitrate selection
    # Represents the audio bitrate per channel (e.g. 80 -> 160Kbps for stereo)
    # Has to be higher than min_audio and >6 (limit for libvorbis)
    max_audio = None

    # Disable user set filters during the 1st of a 2-pass encode
    # Useful when very demanding filters are used (e.g. nlmeans)
    # Has no influence on automatically used filters (scale and fps)
    no_filter_firstpass = False

    # Set FFmpeg verbosity (ffmpeg -v/-loglevel)
    # Special option "stats" is a shortcut for "-v error -stats"
    ffmpeg_verbosity = "stats"

    # Enable debug mode
    # Prints FFmpeg commands without executing them
    debug = False


class CustomArgumentParser(argparse.ArgumentParser):
    """Override ArgumentParser's automatic help text."""

    def format_help(self):
        """Return custom help text."""
        help_text = dedent(f"""\
        RestrictedWebM is a script to produce WebMs within a certain size range.

        Usage: {self.prog} [OPTIONS] INPUT [INPUT]...

        Input:
          Absolute or relative path to a video/image

        Common options:
          -h,  --help               show help
          -q,  --quiet              suppress non-error output
          -v,  --verbose            print verbose information
          -a,  --audio              enable audio output
          -s,  --size SIZE          limit max. output file size in MB (def: {self.get_default("limit")})
          -f,  --filters FILTERS    use custom ffmpeg filters
          -p,  --passes {{1,2}}       specify number of passes (def: {self.get_default("passes")})
          -u,  --undershoot RATIO   specify undershoot ratio (def: {self.get_default("under")})
          -i,  --iterations ITER    iterations for each bitrate mode (def: {self.get_default("iters")})
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
          --no-qmax                 skip first bitrate mode (VBR with qmax)
          --no-cbr                  skip last bitrate mode (CBR with frame dropping)
          --bpp BPP                 set custom bpp threshold (def: {self.get_default("bpp_thresh")})
          --transparency            preserve input transparency
          --pix-fmt FORMAT          choose color space (def: {self.get_default("pix_fmt")})
          --min-height HEIGHT       force min. output height (def: {self.get_default("min_height")})
          --max-height HEIGHT       force max. output height
          --min-fps FPS             force min. frame rate (def: {self.get_default("min_fps")})
          --max-fps FPS             force max. frame rate

        Advanced audio options:
          --opus                    use and allow Opus as audio codec
          --no-copy                 disable stream copying
          --force-copy              force-copy compatible (!) audio streams
          --min-audio RATE          force min. channel bitrate in Kbps (def: {self.get_default("min_audio")})
          --max-audio RATE          force max. channel bitrate in Kbps

        Misc. options:
          --no-filter-firstpass     disable user filters during the first pass
          --ffmpeg-verbosity LEVEL  change FFmpeg command verbosity (def: {self.get_default("ffmpeg_verbosity")})
          --debug                   only print ffmpeg commands

        All output will be saved in '{self.get_default("out_dir")}/'.
        '{self.get_default("out_dir")}/' is located in the same directory as the input.

        For more information visit:
        https://github.com/HelpSeeker/Restricted-WebM/wiki
        """)

        return help_text


class FileInfo:
    """Gathers information about output settings"""

    def __init__(self, in_path):
        """Initialize all properties."""
        # Subtitle-related
        self.image_subs = out_image_subs(in_path)

        # Path-related
        self.input = in_path
        ext = f"{'mkv' if self.image_subs else 'webm'}"
        self.name = os.path.splitext(os.path.basename(self.input))[0]
        self.output = f"{self.name}.{ext}"
        self.temp = f"{self.name}_{opts.suffix}.{ext}"

        command = [
            "ffprobe", "-v", "error", "-show_format", "-show_streams",
            "-print_format", "json", self.input
        ]
        info = subprocess.run(command, stdout=subprocess.PIPE).stdout
        info = json.loads(info)

        # Check input file for basic validity
        # Needs to be done here as the following steps could already fail
        self.valid = self.is_valid(info)
        if not self.valid:
            return

        # Duration-related
        try:
            self.in_dur = float(info['format']['duration'])
        except KeyError:
            self.in_dur = self.brute_input_duration()
        self.out_dur = self.calc_output_duration()

        # Audio-related
        a_streams = [s for s in info['streams'] if s['codec_type'] == "audio"]
        self.a_rate, self.a_list, self.a_sample = self.audio_properties(a_streams)

        # Video-related
        self.v_rate = self.init_video_bitrate()

        v_stream = info['streams'][0]
        self.in_height, self.in_fps, self.ratio = self.video_properties(v_stream)
        self.out_height = self.in_height
        self.out_fps = self.in_fps

    def is_valid(self, info):
        """Test for basic pitfalls that would lead to FFmpeg failure."""
        streams = [s['codec_type'] for s in info['streams']]
        if self.image_subs and not opts.mkv_fallback:
            err(f"{self.input}: "
                "Conversion of image-based subtitles not supported!")
            return False
        if streams[0] != "video":
            err(f"{self.input}: "
                "Unsupported stream order (first stream not video)!")
            return False
        if [s for s in streams[1:] if s == "video"]:
            err(f"{self.input}: "
                "Files with more than one video stream not supported!")
            return False

        return True

    def brute_input_duration(self):
        """Brute-force detect input duration for GIFs and other images."""
        # Encodes input as AVC (fast) and reads duration from the output
        ffmpeg = [
            "ffmpeg", "-y", "-v", "error", "-i", self.input, "-map", "0:v",
            "-c:v", "libx264", "-preset", "ultrafast", "-crf", "51",
            f"{self.name}_{opts.suffix}_.mkv"
        ]
        ffprobe = [
            "ffprobe", "-v", "error", "-show_format", "-show_streams",
            "-print_format", "json", f"{self.name}_{opts.suffix}.mkv"
        ]

        subprocess.run(ffmpeg)
        info = subprocess.run(ffprobe, stdout=subprocess.PIPE).stdout
        info = json.loads(info)

        return float(info['format']['duration'])

    def calc_output_duration(self):
        """Calculate output duration."""
        if not (opts.global_start or opts.global_end):
            return self.in_dur

        start = 0
        end = self.in_dur
        if opts.global_start and opts.global_start < end:
            start = opts.global_start
        if opts.global_end and opts.global_end < end:
            end = opts.global_end

        return round(end - start, 3)

    def audio_properties(self, streams):
        """Gather various audio properties (e.g. bitrate, sample rate)."""
        if not opts.audio:
            return (0, [], None)

        c_list = [int(s['channels']) if not opts.force_stereo else 2
                  for s in streams]
        if opts.basic_format:
            del c_list[1:]
        channels = sum(c_list)

        # Formula was originally based on my experience with stereo audio
        # for 4MB WebMs, but was later changed to accommodate more bitrates
        # and channels
        factor = opts.max_size*8 \
                 / (self.out_dur*channels*4*1000) \
                 / opts.a_factor
        c_rate = choose_audio_bitrate(factor)

        b_list = [c*c_rate for c in c_list]
        bitrate = sum(b_list)

        # Downsample necessary for lower bitrates with libvorbis
        if c_rate <= 6:
            sample = 8000
        elif c_rate <= 12:
            sample = 12000
        elif c_rate <= 16:
            sample = 24000
        else:
            sample = None

        return (bitrate, b_list, sample)

    def video_properties(self, stream):
        """Gather various video properties (e.g. height, fps)."""
        # If user scale/fps filter -> test encode
        # Read the effect (i.e. changed resolution / frame rate) from output
        if opts.user_scale or opts.user_fps:
            ffmpeg = [
                "ffmpeg", "-y", "-v", "error", "-i", self.input, "-vframes", "1",
                "-filter_complex", opts.f_user, f"{self.name}_{opts.suffix}.mkv"
            ]
            ffprobe = [
                "ffprobe", "-v", "error", "-show_format", "-show_streams",
                "-print_format", "json", f"{self.name}_{opts.suffix}.mkv"
            ]

            subprocess.run(ffmpeg)
            info = subprocess.run(ffprobe, stdout=subprocess.PIPE).stdout
            info = json.loads(info)
            stream = info['streams'][0]

        h = int(stream['height'])
        w = int(stream['width'])
        ratio = w/h
        try:
            num, den = stream['r_frame_rate'].split("/")
            fps = int(num)/int(den)
        except ValueError:
            fps = stream['r_frame_rate']

        return (h, fps, ratio)

    def init_video_bitrate(self):
        """Initialize video bitrate to theoretical value."""
        bitrate = int(opts.max_size*8 / (self.out_dur*1000) - self.a_rate)
        if bitrate <= 0:
            bitrate = opts.fallback_bitrate

        return bitrate

    def update_video_bitrate(self, size):
        """Update video bitrate based on output file size."""
        # Size ratio dictates overall bitrate change, but audio bitrate is const
        # (v+a) = (v_old+a) * (max/curr)
        # v = v_old * (max/curr) + (max/curr - 1) * a
        a_offset = int((opts.max_size/size - 1) * self.a_rate)
        new_rate = int(self.v_rate * opts.max_size/size + a_offset)
        min_rate = int(self.v_rate * opts.min_bitrate_ratio)
        # Force min. decrease (% of last bitrate)
        if min_rate < new_rate < self.v_rate:
            bitrate = min_rate
        else:
            bitrate = new_rate

        if bitrate <= 0:
            bitrate = opts.fallback_bitrate

        self.v_rate = bitrate

    def update_filters(self):
        """Update filter values based on the current video bitrate."""
        if opts.user_scale and opts.user_fps:
            return

        # Perform frame rate drop
        if not opts.user_fps:
            possible_fps = [
                f for f in opts.fps_list
                if self.v_rate*1000 / (f*self.ratio*self.in_height**2)
                >= opts.bpp_thresh / 2
            ]
            if not possible_fps:
                possible_fps = [opts.min_fps]
            fps = possible_fps[0]

            # Enfore frame rate thresholds
            if fps < opts.min_fps:
                fps = opts.min_fps
            if opts.max_fps and fps > opts.max_fps:
                fps = opts.max_fps
            if fps > self.in_fps:
                fps = self.in_fps
            self.out_fps = fps

        # Perform downscale
        if not opts.user_scale:
            possible_heights = [
                h for h in range(self.in_height, 0, opts.height_reduction)
                if self.v_rate*1000 / (self.out_fps*self.ratio*h**2)
                >= opts.bpp_thresh
            ]
            if not possible_heights:
                possible_heights = [opts.min_height]
            height = possible_heights[0]

            # Enforce height thresholds
            if height < opts.min_height:
                height = opts.min_height
            if opts.max_height and height > opts.max_height:
                height = opts.max_height
            if height > self.in_height:
                height = self.in_height
            self.out_height = height


class ConvertibleFile:
    """Assembles FFmpeg settings"""

    def __init__(self, info):
        """Initialize all properties"""
        self.info = info
        self.valid = self.info.valid
        if not self.valid:
            return

        # Verbosity-related
        if opts.ffmpeg_verbosity == "stats":
            self.verbosity = ["-v", "error", "-stats"]
        else:
            self.verbosity = ["-v", opts.ffmpeg_verbosity]

        # Trim/input-related
        self.input = ["-i", self.info.input]
        if opts.global_start and opts.global_start < self.info.in_dur:
            self.input = ["-ss", str(opts.global_start)] + self.input
        if opts.global_end and opts.global_end <= self.info.in_dur:
            self.input.extend(["-t", str(self.info.out_dur)])

        # Map-related
        self.map = ["-map", "0:v"]
        if opts.subs or opts.burn_subs:
            self.map.extend(["-map", "0:s?"])
        if opts.audio:
            a_streams = [
                ["-map", f"0:a:{i}?"]
                for i in range(len(self.info.a_list))
                if opts.audio and not (opts.basic_format and i > 0)
            ]
            for s in a_streams:
                self.map.extend(s)

        # Subtitle-related
        if opts.burn_subs:
            self.subs = ["-sn"]
        elif self.info.image_subs:
            self.subs = ["-c:s", "copy"]
        elif opts.subs:
            self.subs = ["-c:s", "webvtt"]
        else:
            self.subs = []

        # Audio-related
        self.audio = self.init_audio_flags()

        # These get updated before each encoding attempt
        self.video = []
        self.filter = []

    def init_audio_flags(self):
        """Initialize audio-related FFmpeg options."""
        audio = []
        a_streams = [i for i in range(len(self.info.a_list))
                     if opts.audio and not (opts.basic_format and i > 0)]
        for s in a_streams:
            if audio_copy(self, s):
                audio.extend([f"-c:a:{s}", "copy"])
            elif opts.a_codec == "libopus" and opus_fallback(self.info.input, s):
                audio.extend([f"-c:a:{s}", opts.fallback_codec])
                audio.extend([f"-b:a:{s}", f"{self.info.a_list[s]}K"])
            else:
                audio.extend([f"-c:a:{s}", opts.a_codec])
                audio.extend([f"-b:a:{s}", f"{self.info.a_list[s]}K"])

        # -ac/-ar have no effect without audio encoding
        # there's no need for additional checks
        if opts.force_stereo:
            audio.extend(["-ac", "2"])
        if self.info.a_sample is not None:
            audio.extend(["-ar", str(self.info.a_sample)])

        return audio

    def update_video_flags(self, mode):
        """Update video-related FFmpeg options."""
        self.video = ["-c:v", opts.v_codec]
        self.video.extend(["-deadline", "good"])
        # -cpu-used defined in call_ffmpeg, since it depends on the pass

        # TO-DO:
        # Test how strong temporal filtering influences high quality encodes
        # Figure out how/why alpha channel support cuts short GIFs during 2-pass
        self.video.extend(["-pix_fmt", opts.pix_fmt])

        if opts.pix_fmt == "yuva420p":
            self.video.extend(["-auto-alt-ref", "0"])
        else:
            self.video.extend(["-auto-alt-ref", "1",
                               "-lag-in-frames", "25",
                               "-arnr-maxframes", "15",
                               "-arnr-strength", "6"])

        self.video.extend(["-b:v", f"{self.info.v_rate}K"])

        if opts.crf and mode in (1, 2):
            self.video.extend(["-crf", str(opts.crf_value)])

        if mode == 1:
            self.video.extend(["-qmax", str(opts.min_quality)])
        elif mode == 3:
            self.video.extend(["-minrate:v", f"{self.info.v_rate}K",
                               "-maxrate:v", f"{self.info.v_rate}K",
                               "-bufsize", f"{self.info.v_rate*5}K",
                               "-skip_threshold", "100"])

        self.video.extend(["-threads", str(opts.threads)])

        # This check isn't necessary, but it avoids command bloat
        if opts.v_codec == "libvpx-vp9" and opts.threads > 1:
            self.video.extend(["-tile-columns", "6",
                               "-tile-rows", "2",
                               "-row-mt", "1"])

    def update_filters_flags(self):
        """Update filter-related FFmpeg options."""
        f_scale = f"scale=-2:{self.info.out_height}:flags=lanczos"
        f_fps = f"fps={self.info.out_fps}"

        if self.info.out_height < self.info.in_height \
           and self.info.out_fps < self.info.in_fps:
            self.filter = ["-vf", f"{f_scale},{f_fps}"]
        elif self.info.out_height < self.info.in_height:
            self.filter = ["-vf", f_scale]
        elif self.info.out_fps < self.info.in_fps:
            self.filter = ["-vf", f_fps]

    def assemble_raw_command(self, ff_pass):
        """Assemble custom filter-applying FFmpeg command."""
        video = ["-c:v", "copy"]
        if opts.global_start or opts.f_video:
            video = ["-c:v", "rawvideo"]

        audio = ["-c:a", "copy"]
        if opts.global_start or opts.f_audio:
            audio = ["-c:a", "pcm_s16le"]

        if opts.no_filter_firstpass and opts.passes == 2 and ff_pass == 1:
            filters = []
        else:
            filters = ["-filter_complex", opts.f_user]

        command = ["ffmpeg", "-y", "-v", "error"]
        command.extend(self.input)
        command.extend(self.map)
        command.extend(video)
        command.extend(audio)
        command.extend(["-c:s", "copy"])
        command.extend(filters)
        command.extend(["-strict", "-2", "-f", "matroska", "-"])

        return command

    def assemble_command(self, mode, ff_pass):
        """Assemble final FFmpeg command, which creates the output file."""
        if opts.passes == 1 or mode == 3:
            output = ["-cpu-used", "0", self.info.temp]
        elif ff_pass == 1:
            output = ["-cpu-used", "5", "-passlogfile", self.info.name,
                      "-pass", "1", "-f", "null", "-"]
        elif ff_pass == 2:
            output = ["-cpu-used", "0", "-passlogfile", self.info.name,
                      "-pass", "2", self.info.temp]

        command = ["ffmpeg", "-y"]
        command.extend(self.verbosity)
        if opts.f_user:
            command.extend(["-i", "-", "-map", "0"])
        else:
            command.extend(self.input)
            command.extend(self.map)
        command.extend(self.video)
        command.extend(self.audio)
        command.extend(self.subs)
        command.extend(self.filter)
        command.extend(output)

        return command


class FileConverter:
    """Handle the conversion process of a convertible file."""

    def __init__(self):
        """Initialize all properties."""
        self.curr_size = 0
        self.best_size = 0
        self.last_size = 0

        # Bitrate modes (not in technically accurate sense):
        #   1 -> VBR/CQ + qmax
        #   2 -> VBR/CQ
        #   3 -> CBR

        # Set first mode to use
        if opts.no_qmax:
            self.min_mode = 2
        else:
            self.min_mode = 1
        # Set last mode to use
        if opts.no_cbr:
            self.max_mode = 2
        else:
            self.max_mode = 3
        # Initialize mode tracker with the first mode
        self.mode = self.min_mode

    def update_size(self, video):
        """Update size information after an encoding attempt."""
        # Save size from previous attempt for later rel. difference check
        self.last_size = self.curr_size
        # Get current attempt size
        if opts.debug:
            try:
                user = float(input("\nOutput size in MB: "))
            except ValueError:
                # Use empty input as shortcut to end debug mode (simulate success)
                user = opts.limit
            self.curr_size = int(user*1024**2)
        else:
            self.curr_size = os.path.getsize(video.info.temp)

        # Test if current size is the best attempt yet
        # True, if
        #   -> first try (no best size yet)
        #   -> best try too large; smaller than best try (still tries to limit)
        #   -> best try ok; bigger than best try and smaller than max size
        if not self.best_size \
           or self.curr_size < self.best_size and self.best_size > opts.max_size \
           or self.best_size < self.curr_size <= opts.max_size \
           and self.best_size < opts.max_size:
            self.best_size = self.curr_size
            if not opts.debug:
                os.replace(video.info.temp, video.info.output)

    def size_info(self):
        """Fetch info text about the currently saved file sizes."""
        if self.best_size > opts.max_size:
            color = fgcolors.ERROR
        elif self.best_size < opts.min_size:
            color = fgcolors.WARNING
        else:
            color = fgcolors.SUCCESS

        info = indent(dedent(f"""
            Curr. size: {round(self.curr_size/1024**2, 2)} MB
            Last size:  {round(self.last_size/1024**2, 2)} MB
            Best try:   {color}{round(self.best_size/1024**2, 2)}{fgcolors.DEFAULT} MB
            """), "  ")

        return info

    def skip_mode(self):
        """Check for insufficient file size change."""
        diff = abs((self.curr_size-self.last_size) / self.last_size)
        return bool(diff < opts.skip_limit)

    def limit_size(self, video):
        """Limit output size to the given upper limit."""
        while self.mode <= self.max_mode:
            for i in range(1, opts.iters+1):
                # Reset bitrate for 1st attempt of a new mode
                if i == 1:
                    video.info.v_rate = video.info.init_video_bitrate()
                else:
                    video.info.update_video_bitrate(self.curr_size)
                video.info.update_filters()
                video.update_video_flags(self.mode)
                video.update_filters_flags()

                msg(f"Mode {fgcolors.INFO}{self.mode}{fgcolors.DEFAULT} (of 3) | "
                    f"Attempt {fgcolors.INFO}{i}{fgcolors.DEFAULT} (of {opts.iters}) | "
                    f"Height: {fgcolors.INFO}{video.info.out_height}{fgcolors.DEFAULT} | "
                    f"FPS: {fgcolors.INFO}{video.info.out_fps}{fgcolors.DEFAULT}")
                msg(indent(dedent(f"""
                    Video:      {' '.join(video.video)}
                    Filters:    {' '.join(video.filter)}
                    """), "  "),
                    level=2)

                call_ffmpeg(video, self.mode)
                self.update_size(video)
                msg(self.size_info(), level=2)

                # Skip remaining iters, if change too small (defaul: <1%)
                if i > 1 and self.skip_mode():
                    break
                if self.best_size <= opts.max_size:
                    return

            self.mode += 1

    def raise_size(self, video):
        """Raise output size above the given lower limit."""
        for i in range(1, opts.iters+1):
            # don't re-initialize; adjust the last bitrate from limit_size()
            video.info.update_video_bitrate(self.curr_size)
            video.info.update_filters()
            video.update_video_flags(self.mode)
            video.update_filters_flags()

            msg(f"Enhance Attempt {fgcolors.INFO}{i}{fgcolors.DEFAULT} (of {opts.iters}) | "
                f"Height: {fgcolors.INFO}{video.info.out_height}{fgcolors.DEFAULT} | "
                f"FPS: {fgcolors.INFO}{video.info.out_fps}{fgcolors.DEFAULT}")
            msg(indent(dedent(f"""
                Video:      {' '.join(video.video)}
                Filters:    {' '.join(video.filter)}
                """), "  "),
                level=2)

            call_ffmpeg(video, self.mode)
            self.update_size(video)
            msg(self.size_info(), level=2)

            # Skip remaining iters, if change too small (defaul: <1%)
            if self.skip_mode():
                return
            if opts.min_size <= self.best_size <= opts.max_size:
                return

    def process(self, video):
        """Process (i.e. convert) a single input video."""
        global size_fail

        self.limit_size(video)
        if self.best_size > opts.max_size:
            err(f"{os.path.abspath(video.info.output)}: Still too large",
                color=fgcolors.WARNING)
            size_fail = True
            return
        if self.best_size >= opts.min_size:
            return

        self.raise_size(video)
        if self.best_size < opts.min_size:
            err(f"{os.path.abspath(video.info.output)}: Still too small",
                color=fgcolors.WARNING)
            size_fail = True

    def reset(self):
        """Reset instance variables after conversion."""
        self.curr_size = 0
        self.best_size = 0
        self.last_size = 0
        self.mode = self.min_mode

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def err(*args, level=0, color=fgcolors.ERROR, **kwargs):
    """Print to stderr."""
    if level <= opts.verbosity:
        sys.stderr.write(color)
        print(*args, file=sys.stderr, **kwargs)
    sys.stderr.write(fgcolors.RESET)
    sys.stdout.write(fgcolors.RESET)


def msg(*args, level=1, color=fgcolors.DEFAULT, **kwargs):
    """Print to stdout based on verbosity level."""
    if level < opts.verbosity:
        # Print "lower-level" info bold in more verbose modes
        sys.stdout.write(fgcolors.BOLD)
    if level <= opts.verbosity:
        sys.stdout.write(color)
        print(*args, **kwargs)
    sys.stderr.write(fgcolors.RESET)
    sys.stdout.write(fgcolors.RESET)


def check_prereq():
    """Test if all required software is installed."""
    reqs = ["ffmpeg", "ffprobe"]

    for r in reqs:
        try:
            subprocess.run([r], stdout=subprocess.DEVNULL, \
                                stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            err(f"Error: {r} not found!")
            sys.exit(status.DEP)


def positive_int(string):
    """Convert string provided by argparse to a positive int."""
    try:
        value = int(string)
        if value <= 0:
            raise ValueError
    except ValueError:
        error = f"invalid positive int value: {string}"
        raise argparse.ArgumentTypeError(error)

    return value


def positive_float(string):
    """Convert string provided by argparse to a positive float."""
    try:
        value = float(string)
        if value <= 0:
            raise ValueError
    except ValueError:
        error = f"invalid positive float value: {string}"
        raise argparse.ArgumentTypeError(error)

    return value


def valid_time(string):
    """Convert string provided by argparse to time in seconds."""
    # Just test validity with FFmpeg (reasonable fast even for >1h durations)
    command = ["ffmpeg", "-v", "quiet",
               "-f", "lavfi", "-i", "anullsrc",
               "-t", string, "-c", "copy",
               "-f", "null", "-"]
    try:
        subprocess.check_call(command)
    except subprocess.CalledProcessError:
        error = f"invalid FFmpeg time syntax: {string}"
        raise argparse.ArgumentTypeError(error)

    # Split into h, m and s
    time = [float(t) for t in string.split(":")]
    if len(time) == 3:
        sec = 3600*time[0] + 60*time[1] + time[2]
    elif len(time) == 2:
        sec = 60*time[0] + time[1]
    elif len(time) == 1:
        sec = time[0]

    if sec <= 0:
        error = f"invalid positive time value: {string}"
        raise argparse.ArgumentTypeError(error)

    return sec


def valid_file(string):
    """Convert string provided by argparse to valid file path."""
    path = os.path.abspath(string)
    if not os.path.exists(path):
        error = f"file doesn't exist: {path}"
        raise argparse.ArgumentTypeError(error)
    if not os.path.isfile(path):
        error = f"not a regular file: {path}"
        raise argparse.ArgumentTypeError(error)

    return path


def analyze_filters(filters):
    """Test user set filters"""
    if not filters:
        return (False, False)

    # existing filters let copy fail
    # only crude test; stream specifiers will let it fail as well
    command = ["ffmpeg", "-v", "quiet",
               "-f", "lavfi", "-i", "nullsrc",
               "-f", "lavfi", "-i", "anullsrc",
               "-t", "1", "-c:v", "copy",
               "-filter_complex", filters,
               "-f", "null", "-"]
    try:
        subprocess.check_call(command)
        video = False
    except subprocess.CalledProcessError:
        video = True

    command = ["ffmpeg", "-v", "quiet",
               "-f", "lavfi", "-i", "nullsrc",
               "-f", "lavfi", "-i", "anullsrc",
               "-t", "1", "-c:a", "copy",
               "-filter_complex", filters,
               "-f", "null", "-"]
    try:
        subprocess.check_call(command)
        audio = False
    except subprocess.CalledProcessError:
        audio = True

    return (video, audio)


def parse_cli():
    """Parse command line arguments."""
    defaults = DefaultOptions()
    parser = CustomArgumentParser(usage="%(prog)s [OPTIONS] INPUT [INPUT]...")

    # Input
    parser.add_argument("files", nargs="+", type=valid_file)
    # Common Options
    verbosity = parser.add_mutually_exclusive_group()
    verbosity.add_argument("-q", "--quiet", dest="verbosity", action="store_const",
                           const=0, default=defaults.verbosity)
    verbosity.add_argument("-v", "--verbose", dest="verbosity", action="store_const",
                           const=2, default=defaults.verbosity)
    parser.add_argument("-a", "--audio", action="store_true",
                        default=defaults.audio)
    parser.add_argument("-s", "--size", dest="limit", type=positive_float,
                        default=defaults.limit)
    parser.add_argument("-f", "--filters", dest="f_user",
                        default=defaults.f_user)
    parser.add_argument("-p", "--passes", type=int, default=defaults.passes,
                        choices=[1, 2])
    parser.add_argument("-u", "--undershoot", dest="under", type=float,
                        default=defaults.under)
    parser.add_argument("-i", "--iterations", dest="iters", type=positive_int,
                        default=defaults.iters)
    parser.add_argument("-t", "--threads", type=positive_int,
                        default=defaults.threads)
    parser.add_argument("-ss", "--start", dest="global_start", type=valid_time,
                        default=defaults.global_start)
    parser.add_argument("-to", "--end", dest="global_end", type=valid_time,
                        default=defaults.global_end)
    parser.add_argument("-fs", "--force-stereo", action="store_true",
                        default=defaults.force_stereo)
    parser.add_argument("-bf", "--basic-format", action="store_true",
                        default=defaults.basic_format)
    # Subtitle Options
    parser.add_argument("--subtitles", dest="subs", action="store_true",
                        default=defaults.subs)
    parser.add_argument("--mkv-fallback", action="store_true",
                        default=defaults.mkv_fallback)
    parser.add_argument("--burn-subs", action="store_true",
                        default=defaults.burn_subs)
    # Advanced Video Options
    parser.add_argument("--vp9", dest="v_codec", action="store_const",
                        const="libvpx-vp9", default=defaults.v_codec)
    parser.add_argument("--crf", action="store_true", default=defaults.crf)
    parser.add_argument("--no-qmax", action="store_true",
                        default=defaults.no_qmax)
    parser.add_argument("--no-cbr", action="store_true",
                        default=defaults.no_cbr)
    parser.add_argument("--bpp", dest="bpp_thresh", type=positive_float,
                        default=defaults.bpp_thresh)
    parser.add_argument("--transparency", action="store_true",
                        default=defaults.transparency)
    parser.add_argument(
        "--pix-fmt", default=defaults.pix_fmt,
        choices=[
            "yuv420p", "yuva420p",
            "yuv422p", "yuv440p", "yuv444p",
            "yuv420p10le", "yuv422p10le", "yuv440p10le", "yuv444p10le",
            "yuv420p12le", "yuv422p12le", "yuv440p12le", "yuv444p12le",
            "gbrp", "gbrp10le", "gbrp12le",
        ]
    )
    parser.add_argument("--min-height", type=positive_int,
                        default=defaults.min_height)
    parser.add_argument("--max-height", type=positive_int,
                        default=defaults.max_height)
    parser.add_argument("--min-fps", type=positive_float,
                        default=defaults.min_fps)
    parser.add_argument("--max-fps", type=positive_float,
                        default=defaults.max_fps)
    # Advanced Audio Options
    parser.add_argument("--opus", dest="a_codec", action="store_const",
                        const="libopus", default=defaults.a_codec)
    copy_action = parser.add_mutually_exclusive_group()
    copy_action.add_argument("--no-copy", action="store_true",
                             default=defaults.no_copy)
    copy_action.add_argument("--force-copy", action="store_true",
                             default=defaults.force_copy)
    parser.add_argument("--min-audio", type=positive_int,
                        default=defaults.min_audio)
    parser.add_argument("--max-audio", type=positive_int,
                        default=defaults.max_audio)
    # Misc. Options
    parser.add_argument("--no-filter-firstpass", action="store_true",
                        default=defaults.no_filter_firstpass)
    parser.add_argument(
        "--ffmpeg-verbosity", default=defaults.ffmpeg_verbosity,
        choices=[
            "quiet", "panic", "fatal",
            "error", "warning", "info",
            "verbose", "debug", "trace",
            "stats",
        ]
    )
    parser.add_argument("--debug", action="store_true", default=defaults.debug)

    # Advanced User Options
    parser.set_defaults(
        fps_list=[60, 30, 25, 24, 22, 20, 18, 16, 14, 12, 10, 8, 6, 4, 2, 1],
        audio_test_dur=60,            # 0 for whole stream -> exact bitrate
        fallback_bitrate=1,           # Must be >0
        height_reduction=-10,         # Must be <0
        min_quality=50,
        crf_value=10,
        min_bitrate_ratio=0.9,
        skip_limit=0.01,
        a_factor=5.5,
        fallback_codec="libvorbis",
        suffix="temp",
        out_dir="webm_done",
    )

    args = parser.parse_args()

    # Store size limits in Bytes
    args.max_size = int(args.limit*1024**2)
    args.min_size = int(args.limit*1024**2*args.under)
    # Scan user filter-string for the scale and fps filter
    args.user_scale = bool(args.f_user and "scale" in args.f_user)
    args.user_fps = bool(args.f_user and "fps" in args.f_user)
    # Set pixel format according to transparency flag
    # Makes sure that --transparency overwrites --pix-fmt
    if args.transparency:
        args.pix_fmt = "yuva420p"
    # Check type of applied user filters
    args.f_video, args.f_audio = analyze_filters(args.f_user)

    return args


def additional_checks():
    """Check for invalid options that aren't detected by argparse."""
    # Warn againts excessive thread usage
    if opts.threads > 6 and opts.v_codec == "libvpx":
        err("VP8 encoding via libvpx doesn't scale well beyond 4-6 threads.",
            color=fgcolors.WARNING)
    if opts.threads > 16:
        err("Using more than 16 threads is not recommended.",
            color=fgcolors.WARNING)

    # Special integer checks
    if opts.max_height and opts.max_height < opts.min_height:
        err("Max. height can't be less than min. height!")
        sys.exit(status.OPT)
    elif opts.max_audio and opts.max_audio < 6:
        err("Max. audio channel bitrate must be greater than 6 Kbps!")
        sys.exit(status.OPT)
    elif opts.max_audio and opts.max_audio < opts.min_audio:
        err("Max. audio channel bitrate can't be less than min. audio channel bitrate!")
        sys.exit(status.OPT)
    # Special float checks
    elif opts.global_start and opts.global_end and \
         opts.global_end <= opts.global_start:
        err("End time must be greater than start time!")
        sys.exit(status.OPT)
    elif not 0 <= opts.under <= 1:
        err("Undershoot must be in range [0,1]!")
        sys.exit(status.OPT)
    elif opts.max_fps and opts.max_fps < 1 or opts.min_fps < 1:
        err("Frame rates can't be less than 1!")
        sys.exit(status.OPT)
    elif opts.max_fps and opts.max_fps < opts.min_fps:
        err("Max. frame rate can't be less than min. frame rate!")
        sys.exit(status.OPT)

    vp8_pix_fmt = ["yuv420p", "yuva420p"]
    if opts.v_codec == "libvpx" and opts.pix_fmt not in vp8_pix_fmt:
        err(f"'{opts.pix_fmt}' isn't supported by VP8!")
        err("See 'ffmpeg -h encoder=libvpx' for more infos.",
            color=fgcolors.DEFAULT)
        sys.exit(status.OPT)


def choose_audio_bitrate(factor):
    """Choose audio bitrate per channel (based on personal experience)."""
    if factor < 1:
        bitrate = 6
    elif factor < 2:
        bitrate = 8
    elif factor < 3:
        bitrate = 12
    elif factor < 4:
        bitrate = 16
    elif factor < 6:
        bitrate = 24
    elif factor < 8:
        bitrate = 32
    elif factor < 28:
        bitrate = 48
    elif factor < 72:
        bitrate = 64
    elif factor < 120:
        bitrate = 80
    else:
        bitrate = 96

    if bitrate < opts.min_audio:
        bitrate = opts.min_audio
    if opts.max_audio and bitrate > opts.max_audio:
        bitrate = opts.max_audio

    return bitrate


def print_options():
    """Print all settings for verbose output"""
    msg("\n### Settings for the current session ###\n",
        level=2, color=fgcolors.HEADER)

    msg(dedent(f"""\
        Paths:
          Suffix for temporary files:  {opts.suffix}
          Destination directory name:  {opts.out_dir}

        Size:
          Max. size:                   {opts.limit} MB
          Undershoot ratio:            {opts.under}
          Max. size:                   {opts.max_size} Bytes
          Min. size:                   {opts.min_size} Bytes

        Trimming:
          Start time:                  {f'{opts.global_start} sec' if opts.global_start else None}
          End time:                    {f'{opts.global_end} sec' if opts.global_end else None}

        Video:
          Encoder:                     {opts.v_codec}
          Passes:                      {opts.passes}
          Threads:                     {opts.threads}
          Color space:                 {opts.pix_fmt}
          Use CQ instead of VBR:       {opts.crf}
          CRF:                         {opts.crf_value}
          qmax:                        {opts.min_quality}
          Fallback bitrate:            {opts.fallback_bitrate} Kbps
          Skip VBR with min. quality:  {opts.no_qmax}
          Skip CBR:                    {opts.no_cbr}
          Iterations/bitrate mode:     {opts.iters}
          Mode skip threshold:         {opts.skip_limit}
          Min. bitrate ratio:          {opts.min_bitrate_ratio}

        Audio:
          Audio output:                {opts.audio}
          Encoder:                     {opts.a_codec}
          Fallback encoder:            {opts.fallback_codec}
          Force stereo:                {opts.force_stereo}
          Min. channel bitrate:        {opts.min_audio} Kbps
          Max. channel bitrate:        {f'{opts.max_audio} Kbps' if opts.max_audio else None}
          Stream copying disabled:     {opts.no_copy}
          Ignore bitrate for copying:  {opts.force_copy}
          Bitrate test duration:       {f'{opts.audio_test_dur} sec' if opts.audio_test_dur else 'full duration'}
          Audio factor:                {opts.a_factor}

        Subtitles:
          Subtitle support:            {opts.subs or opts.burn_subs}
          MKV as fallback:             {opts.mkv_fallback}
          Discard after hardsubbing:   {opts.burn_subs}

        Filters:
          User filters:                {opts.f_user}
          Contains video filters:      {opts.f_video}
          Contains audio filters:      {opts.f_audio}
          Omit during 1st pass:        {opts.no_filter_firstpass}
          BPP threshold:               {opts.bpp_thresh} bpp
          Min. height threshold:       {opts.min_height}
          Max. height threshold:       {opts.max_height if opts.max_height else None}
          Height reduction step:       {opts.height_reduction}
          Min. frame rate threshold:   {opts.min_fps} fps
          Max. frame rate threshold:   {f'{opts.max_fps} fps' if opts.max_fps else None}
          Possible frame rates:        {', '.join([str(f) for f in opts.fps_list])}

        Misc.:
          Only 1 video/audio stream:   {opts.basic_format}
          FFmpeg verbosity level:      {opts.ffmpeg_verbosity}
          Debug mode:                  {opts.debug}"""), level=2)


def resolve_path(in_path):
    """Change into output directory"""
    out_dir = os.path.join(os.path.dirname(in_path), opts.out_dir)
    if not os.path.exists(out_dir):
        os.mkdir(out_dir)
    os.chdir(out_dir)


def audio_copy(video, stream):
    """Decide if input audio stream should be copied"""
    if opts.global_start or opts.f_audio or opts.no_copy:
        return False

    # Shorter values speed up test, but only approximate avg. bitrate
    # 0 will copy entire audio stream -> exact
    copy_dur = []
    if opts.audio_test_dur:
        copy_dur = ["-t", str(opts.audio_test_dur)]

    command = ["ffmpeg", "-y", "-v", "error", "-i", video.info.input]
    command.extend(copy_dur)
    command.extend(["-map", f"0:a:{stream}", "-c", "copy",
                    f"{video.info.name}_{opts.suffix}.mkv"])
    subprocess.run(command)

    command = ["ffprobe", "-v", "error",
               "-show_format", "-show_streams",
               "-print_format", "json",
               f"{video.info.name}_{opts.suffix}.mkv"]
    info = subprocess.run(command, stdout=subprocess.PIPE).stdout
    info = json.loads(info)

    in_rate = int(info['format']['bit_rate'])
    in_codec = info['streams'][0]['codec_name']
    out_rate = video.info.a_list[stream]

    codecs = ["vorbis"]
    if opts.a_codec == "libopus":
        codecs.append("opus")

    # *1.05 since bitrate allocation is no exact business
    if in_codec in codecs and (opts.force_copy or in_rate <= out_rate*1000*1.05):
        return True

    return False


def opus_fallback(in_file, stream):
    """Test if audio fallback encoder is necessary"""
    if opts.force_stereo:
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


def out_image_subs(in_file):
    """Test if output would include image-based subtitles"""
    if not opts.subs or opts.burn_subs:
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


def call_ffmpeg(video, mode):
    """Run FFmpeg to create the output."""
    # Print placeholder line, if FFmpeg output is suppressed
    if opts.ffmpeg_verbosity not in ["info", "verbose", "debug", "trace", "stats"]:
        msg("Converting...")

    for p in range(1, opts.passes+1):
        if (opts.passes == 2 or mode == 3) and p == 1 \
           and os.path.exists(f"{video.info.name}-0.log"):
            continue

        if opts.debug:
            if opts.f_user:
                print(' '.join(video.assemble_raw_command(p)))
            print(' '.join(video.assemble_command(mode, p)))
        else:
            if opts.f_user:
                raw_pipe = subprocess.Popen(
                    video.assemble_raw_command(p),
                    stdout=subprocess.PIPE,
                    bufsize=10**8
                )
                subprocess.run(
                    video.assemble_command(mode, p),
                    stdin=raw_pipe.stdout
                )
            else:
                subprocess.run(video.assemble_command(mode, p))

        # Always run 3rd mode (CBR) with only one pass
        if mode == 3:
            break


def clean(video):
    """Clean leftover file in the workspace"""
    for f in [f"{video.info.name}_{opts.suffix}.{e}" for e in ["webm", "mkv"]]:
        if os.path.exists(f):
            os.remove(f)
    if opts.passes == 2 and os.path.exists(f"{video.info.name}-0.log"):
        os.remove(f"{video.info.name}-0.log")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main script
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def main():
    """Main function body"""
    print_options()

    msg("\n### Start conversion ###\n", level=2, color=fgcolors.HEADER)
    restrictor = FileConverter()

    for i, path in enumerate(opts.files, start=1):
        resolve_path(path)
        video = ConvertibleFile(FileInfo(path))
        if not video.valid:
            clean(video)
            continue

        msg(f"File {fgcolors.FILE}{i}{fgcolors.DEFAULT} (of {len(opts.files)}): "
            f"{fgcolors.FILE}{video.info.input}{fgcolors.DEFAULT}")
        msg(indent(dedent(f"""
            Verbosity:  {' '.join(video.verbosity)}
            Input/trim: {' '.join(video.input)}
            Mapping:    {' '.join(video.map)}
            Audio:      {' '.join(video.audio)}
            Subtitles:  {' '.join(video.subs)}
            Output:     {os.path.abspath(video.info.output)}
            """), "  "),
            level=2)

        try:
            restrictor.process(video)
            restrictor.reset()
        finally:
            clean(video)


# Execute main function
if __name__ == '__main__':
    check_prereq()
    opts = parse_cli()
    additional_checks()

    try:
        main()
    except KeyboardInterrupt:
        err("\nUser Interrupt!", color=fgcolors.WARNING)
        sys.exit(status.INT)

    msg("\n### Finished ###\n", level=2, color=fgcolors.HEADER)
    if size_fail:
        sys.exit(status.SIZE)
    sys.exit(0)
