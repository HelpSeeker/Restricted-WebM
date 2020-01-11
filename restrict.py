#!/usr/bin/env python3

import os
import sys
import json
import subprocess
from fnmatch import fnmatch
from textwrap import dedent, indent

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
fgcolors = Colors()
size_fail = False

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Classes
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

class Options:
    """Stores general options"""

    # Common user settings
    verbosity = 1
    audio = False
    limit = 3
    max_size = int(limit*1024**2)
    f_user = None
    passes = 2
    under = 0.75
    min_size = int(limit*1024**2*under)
    iters = 3
    threads = 1
    global_start = None
    global_end = None
    force_stereo = False
    basic_format = False

    # Subtitle options
    subs = False
    mkv_fallback = False
    burn_subs = False

    # Advanced video options
    v_codec = "libvpx"
    crf = False
    no_qmax = False
    no_cbr = False
    bpp_thresh = 0.075
    transparency = False
    pix_fmt = "yuv420p"
    min_height = 240
    max_height = None
    min_fps = 24
    max_fps = None

    # Advanced audio settings
    a_codec = "libvorbis"
    no_copy = False
    force_copy = False
    min_audio = 24
    max_audio = None

    # Misc settings
    no_filter_firstpass = False
    ffmpeg_verbosity = "stats"
    color = True
    debug = False

    # Advanced user settings
    fps_list = [60, 30, 25, 24, 22, 20, 18, 16, 14, 12, 10, 8, 6, 4, 2, 1]
    audio_test_dur = 60      # 0 for whole stream -> exact bitrate
    fallback_bitrate = 1     # Must be >0
    height_reduction = -10   # Must be <0
    min_quality = 50
    crf_value = 10
    min_bitrate_ratio = 0.9
    skip_limit = 0.01
    a_factor = 5.5
    fallback_codec = "libvorbis"
    temp_name = "temp"
    out_dir = "webm_done"

    # Don't touch
    f_audio = False
    f_video = False
    user_scale = False
    user_fps = False


class FileInfo:
    """Gathers information about output settings"""

    def __init__(self, in_path):
        """Initialize all properties."""
        # Path-related
        self.input = in_path
        self.ext, self.output, self.temp = self.gather_paths()

        command = [
            "ffprobe", "-v", "error", "-show_format", "-show_streams",
            "-print_format", "json", self.input
        ]
        info = subprocess.run(command, stdout=subprocess.PIPE).stdout
        info = json.loads(info)

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

    def gather_paths(self):
        """Gather all necessary infos regarding output paths."""
        name = os.path.basename(self.input)
        name = os.path.splitext(name)[0]

        ext = f"{'mkv' if out_image_subs(self.input) else 'webm'}"
        out = f"{name}.{ext}"
        temp = f"{opts.temp_name}.{ext}"

        return (ext, out, temp)

    def brute_input_duration(self):
        """Brute-force detect input duration for GIFs and other images."""
        # Encodes input as AVC (fast) and reads duration from the output
        ffmpeg = [
            "ffmpeg", "-y", "-v", "error", "-i", self.input, "-map", "0:v",
            "-c:v", "libx264", "-preset", "ultrafast", "-crf", "51",
            opts.temp_name + ".mkv"
        ]
        ffprobe = [
            "ffprobe", "-v", "error", "-show_format", "-show_streams",
            "-print_format", "json", f"{opts.temp_name}.mkv"
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
                "-filter_complex", opts.f_user, f"{opts.temp_name}.mkv"
            ]
            ffprobe = [
                "ffprobe", "-v", "error", "-show_format", "-show_streams",
                "-print_format", "json", f"{opts.temp_name}.mkv"
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
        if opts.subs:
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
        if not opts.subs:
            self.subs = []
        elif opts.burn_subs:
            self.subs = ["-sn"]
        elif out_image_subs(self.info.input):
            self.subs = ["-c:s", "copy"]
        else:
            self.subs = ["-c:s", "webvtt"]

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
            if audio_copy(self.info.input, s, self.info.a_list[s]):
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
            output = ["-cpu-used", "5", "-pass", "1", "-f", "null", "-"]
        elif ff_pass == 2:
            output = ["-cpu-used", "0", "-pass", "2", self.info.temp]

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
            Best try:   {color}{round(self.best_size/1024**2, 2)}{fgcolors.RESET} MB
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


def usage():
    """Print help text"""
    print(dedent(f"""\
        Usage: {os.path.basename(sys.argv[0])} [OPTIONS] INPUT [INPUT]...

        Input:
          Absolute or relative path to a video/image

        Common options:
          -h,  --help               show help
          -q,  --quiet              suppress non-error output
          -v,  --verbose            print verbose information
          -a,  --audio              enable audio output
          -s,  --size SIZE          limit max. output file size in MB (def: {opts.limit})
          -f,  --filters FILTERS    use custom ffmpeg filters
          -p,  --passes {{1,2}}       specify number of passes (def: {opts.passes})
          -u,  --undershoot RATIO   specify undershoot ratio (def: {opts.under})
          -i,  --iterations ITER    iterations for each bitrate mode (def: {opts.iters})
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
          --no-cbr                  skip the last bitrate mode (CBR with frame dropping)
          --bpp BPP                 set custom bpp threshold (def: {opts.bpp_thresh})
          --transparency            preserve input transparency
          --pix-fmt FORMAT          choose color space (def: {opts.pix_fmt})
          --min-height HEIGHT       force min. output height (def: {opts.min_height})
          --max-height HEIGHT       force max. output height
          --min-fps FPS             force min. frame rate (def: {opts.min_fps})
          --max-fps FPS             force max. frame rate

        Advanced audio options:
          --opus                    use and allow Opus as audio codec
          --no-copy                 disable stream copying
          --force-copy              force-copy compatible (!) audio streams
          --min-audio RATE          force min. channel bitrate in Kbps (def: {opts.min_audio})
          --max-audio RATE          force max. channel bitrate in Kbps

        Misc. options:
          --no-filter-firstpass     disable user filters during the first pass
          --ffmpeg-verbosity LEVEL  change FFmpeg command verbosity (def: {opts.ffmpeg_verbosity})
          --no-color                disable colorized output
          --debug                   only print ffmpeg commands

        All output will be saved in '{opts.out_dir}/'.
        '{opts.out_dir}/' is located in the same directory as the input.

        For more information visit:
        https://github.com/HelpSeeker/Restricted-WebM-in-Bash/wiki"""))


def check_prereq():
    """check existence of required software"""
    reqs = ["ffmpeg", "ffprobe"]

    for r in reqs:
        try:
            subprocess.run([r], stdout=subprocess.DEVNULL, \
                                stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            err(f"Error: {r} not found!")
            sys.exit(status.DEP)


def parse_cli():
    """Parse command line arguments"""
    global opts, input_list

    if not sys.argv[1:]:
        usage()
        sys.exit(0)

    with_arg = ["-s", "--size",
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

    pos = 1
    while pos < len(sys.argv):
        opt = sys.argv[pos]
        if opt in with_arg:
            try:
                arg = sys.argv[pos+1]
            except IndexError:
                err(f"Missing value for '{opt}'!")
                sys.exit(status.OPT)

            pos += 2
        else:
            pos += 1

        try:
            # Common options
            if opt in ("-h", "--help"):
                usage()
                sys.exit(0)
            elif opt in ("-q", "--quiet"):
                opts.verbosity = 0
                opts.ffmpeg_verbosity = "warning"
            elif opt in ("-v", "--verbose"):
                opts.verbosity = 2
            elif opt in ("-a", "--audio"):
                opts.audio = True
            elif opt in ("-s", "--size"):
                opts.limit = float(arg)
            elif opt in ("-f", "--filters"):
                opts.f_user = arg
                opts.user_scale = "scale" in arg
                opts.user_fps = "fps" in arg
            elif opt in ("-p", "--passes"):
                opts.passes = int(arg)
            elif opt in ("-u", "--undershoot"):
                opts.under = float(arg)
            elif opt in ("-i", "--iterations"):
                opts.iters = int(arg)
            elif opt in ("-t", "--threads"):
                opts.threads = int(arg)
            elif opt in ("-ss", "--start"):
                opts.global_start = parse_time(arg)
            elif opt in ("-to", "--end"):
                opts.global_end = parse_time(arg)
            elif opt in ("-fs", "--force-stereo"):
                opts.force_stereo = True
            elif opt in ("-bf", "--basic-format"):
                opts.basic_format = True
            # Subtitle options
            elif opt == "--subtitles":
                opts.subs = True
            elif opt == "--mkv-fallback":
                opts.mkv_fallback = True
            elif opt == "--burn-subs":
                opts.burn_subs = True
            # Advanced video options
            elif opt == "--vp9":
                opts.v_codec = "libvpx-vp9"
            elif opt == "--crf":
                opts.crf = True
            elif opt == "--no-qmax":
                opts.no_qmax = True
            elif opt == "--no-cbr":
                opts.no_cbr = True
            elif opt == "--bpp":
                opts.bpp_thresh = float(arg)
            elif opt == "--transparency":
                opts.transparency = True
                opts.pix_fmt = "yuva420p"
            elif opt == "--pix-fmt":
                opts.pix_fmt = arg
            elif opt == "--min-height":
                opts.min_height = int(arg)
            elif opt == "--max-height":
                opts.max_height = int(arg)
            elif opt == "--min-fps":
                opts.min_fps = float(arg)
            elif opt == "--max-fps":
                opts.max_fps = float(arg)
            # Advanced audio options
            elif opt == "--opus":
                opts.a_codec = "libopus"
            elif opt == "--no-copy":
                opts.no_copy = True
            elif opt == "--force-copy":
                opts.force_copy = True
            elif opt == "--min-audio":
                opts.min_audio = int(arg)
            elif opt == "--max-audio":
                opts.max_audio = int(arg)
            # Misc. options
            elif opt == "--no-filter-firstpass":
                opts.no_filter_firstpass = True
            elif opt == "--ffmpeg-verbosity":
                opts.ffmpeg_verbosity = arg
            elif opt == "--no-color":
                opts.color = False
            elif opt == "--debug":
                opts.debug = True
            # Files and unknown arguments
            elif fnmatch(opt, "-*"):
                err(f"Unknown flag '{opt}'!")
                err(f"Try '{os.path.basename(sys.argv[0])} --help' for more information.")
                sys.exit()
            else:
                if os.path.isfile(opt):
                    input_list.append(os.path.abspath(opt))
                else:
                    err(f"'{opt}' is no valid file.")
                    sys.exit()
        except ValueError:
            err(f"Invalid {opt} ('{arg}')!")
            sys.exit(status.OPT)

    # Additional option-independent steps
    opts.max_size = int(opts.limit*1024**2)
    opts.min_size = int(opts.limit*1024**2*opts.under)


def check_options():
    """Check validity of command line options"""
    # Check for input files
    if not input_list:
        err("No input files specified.", color=fgcolors.WARNING)
        sys.exit(status.OPT)
    for i in input_list:
        name = os.path.basename(i)
        name = os.path.splitext(name)[0]
        if name == opts.temp_name:
            err(f"{i} has reserved filename!")
            sys.exit(status.DEP)

    # Special integer checks
    if opts.passes not in (1, 2):
        err("Only 1 or 2 passes are supported!")
        sys.exit(status.OPT)
    elif opts.iters < 1:
        err("Script needs at least 1 iteration per mode!")
        sys.exit(status.OPT)
    elif opts.min_height <= 0:
        err("Min. height must be greater than 0!")
        sys.exit(status.OPT)
    elif opts.max_height and opts.max_height < opts.min_height:
        err("Max. height can't be less than min. height!")
        sys.exit(status.OPT)
    elif opts.threads <= 0:
        err("Thread count must be larger than 0!")
        sys.exit(status.OPT)
    elif opts.threads > 16:
        # Just a warning
        err("More than 16 threads are not recommended.", color=fgcolors.WARNING)
    elif opts.max_audio and opts.max_audio < 6:
        err("Max. audio channel bitrate must be greater than 6 Kbps!")
        sys.exit(status.OPT)
    elif opts.max_audio and opts.max_audio < opts.min_audio:
        err("Max. audio channel bitrate can't be less than min. audio channel bitrate!")
        sys.exit(status.OPT)

    # Special float checks
    if opts.limit <= 0:
        err("Target file size must be greater than 0!")
        sys.exit(status.OPT)
    elif opts.global_end and opts.global_end <= 0:
        err("End time must be greater than 0!")
        sys.exit(status.OPT)
    elif opts.global_start and opts.global_end and \
         opts.global_end <= opts.global_start:
        err("End time must be greater than start time!")
        sys.exit(status.OPT)
    elif opts.under > 1:
        err("Undershoot ratio can't be greater than 1!")
        sys.exit(status.OPT)
    elif opts.bpp_thresh <= 0:
        err("Bits per pixel threshold must be greater than 0!")
        sys.exit(status.OPT)
    elif opts.max_fps and opts.max_fps < 1:
        err("Max. frame rate can't be less than 1!")
        sys.exit(status.OPT)
    elif opts.max_fps and opts.max_fps < opts.min_fps:
        err("Max. frame rate can't be less than min. frame rate!")
        sys.exit(status.OPT)

    # Check for mutually exclusive flags
    if opts.force_copy and opts.no_copy:
        err("--force-copy and --no-copy are mutually exclusive!")
        sys.exit(status.OPT)

    # Misc. checks
    if opts.transparency and opts.pix_fmt != "yuva420p":
        err("Only yuva420p supports transparency!")
        sys.exit(status.OPT)

    vp8_pix_fmt = ["yuv420p", "yuva420p"]
    vp9_pix_fmt = ["yuv420p", "yuva420p",
                   "yuv422p", "yuv440p", "yuv444p",
                   "yuv420p10le", "yuv422p10le", "yuv440p10le", "yuv444p10le",
                   "yuv420p12le", "yuv422p12le", "yuv440p12le", "yuv444p12le",
                   "gbrp", "gbrp10le", "gbrp12le"]

    if opts.v_codec == "libvpx" and opts.pix_fmt not in vp8_pix_fmt:
        err(f"'{opts.pix_fmt}' isn't supported by VP8!")
        err("See 'ffmpeg -h encoder=libvpx' for more infos.")
        sys.exit(status.OPT)
    elif opts.v_codec == "libvpx-vp9" and opts.pix_fmt not in vp9_pix_fmt:
        err(f"'{opts.pix_fmt}' isn't supported by VP9!")
        err("See 'ffmpeg -h encoder=libvpx-vp9' for more infos.")
        sys.exit(status.OPT)

    loglevels = ["quiet", "panic", "fatal",
                 "error", "warning", "info",
                 "verbose", "debug", "trace",
                 "stats"]

    if opts.ffmpeg_verbosity not in loglevels:
        err(f"'{opts.ffmpeg_verbosity}' isn't a supported FFmpeg verbosity level!")
        err("Supported levels:")
        err(loglevels)
        sys.exit(status.OPT)


def check_filters():
    """Test user set filters"""
    if not opts.f_user:
        return

    # existing filters let copy fail
    # only crude test; stream specifiers will let it fail as well
    command = ["ffmpeg", "-v", "quiet",
               "-f", "lavfi", "-i", "nullsrc",
               "-f", "lavfi", "-i", "anullsrc",
               "-t", "1", "-c:v", "copy",
               "-filter_complex", opts.f_user,
               "-f", "null", "-"]
    try:
        subprocess.check_call(command)
    except subprocess.CalledProcessError:
        opts.f_video = True

    command = ["ffmpeg", "-v", "quiet",
               "-f", "lavfi", "-i", "nullsrc",
               "-f", "lavfi", "-i", "anullsrc",
               "-t", "1", "-c:a", "copy",
               "-filter_complex", opts.f_user,
               "-f", "null", "-"]
    try:
        subprocess.check_call(command)
    except subprocess.CalledProcessError:
        opts.f_audio = True


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
        err(f"Invalid time ('{in_time}')! For the supported syntax see:")
        err("https://ffmpeg.org/ffmpeg-utils.html#time-duration-syntax")
        sys.exit(status.OPT)

    # Split into h, m and s
    in_time = in_time.split(":")
    in_time = [float(t) for t in in_time]
    if len(in_time) == 3:
        time_in_sec = 3600*in_time[0] + 60*in_time[1] + in_time[2]
    elif len(in_time) == 2:
        time_in_sec = 60*in_time[0] + in_time[1]
    elif len(in_time) == 1:
        time_in_sec = in_time[0]

    return time_in_sec


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
          Temporary filename:          {opts.temp_name}
          Destination directory name:  {opts.out_dir}

        Size:
          Max. size (MB):              {opts.limit}
          Undershoot ratio:            {opts.under}
          Max. size (Bytes):           {opts.max_size}
          Min. size (Bytes):           {opts.min_size}

        Trimming:
          Start time (sec):            {opts.global_start if opts.global_start else "-"}
          End time (sec):              {opts.global_end if opts.global_end else "-"}

        Video:
          Encoder:                     {opts.v_codec}
          Passes:                      {opts.passes}
          Threads:                     {opts.threads}
          Color space:                 {opts.pix_fmt}
          Use CQ instead of VBR:       {opts.crf}
          CRF:                         {opts.crf_value}
          qmax:                        {opts.min_quality}
          Fallback bitrate (Kbps):     {opts.fallback_bitrate}
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
          Min. channel bitrate (Kbps): {opts.min_audio}
          Max. channel bitrate (Kbps): {opts.max_audio if opts.max_audio else "-"}
          Stream copying disabled:     {opts.no_copy}
          Ignore bitrate for copying:  {opts.force_copy}
          Bitrate test duration (sec): {opts.audio_test_dur}
          Audio factor:                {opts.a_factor}

        Subtitles:
          Subtitle support:            {opts.subs}
          MKV as fallback:             {opts.mkv_fallback}
          Discard after hardsubbing:   {opts.burn_subs}

        Filters:
          User filters:                {opts.f_user}
          Contains video filters:      {opts.f_video}
          Contains audio filters:      {opts.f_audio}
          Omit during 1st pass:        {opts.no_filter_firstpass}
          BPP threshold:               {opts.bpp_thresh}
          Min. height threshold:       {opts.min_height}
          Max. height threshold:       {opts.max_height if opts.max_height else "-"}
          Height reduction step:       {opts.height_reduction}
          Min. frame rate threshold:   {opts.min_fps}
          Max. frame rate threshold:   {opts.max_fps if opts.max_fps else "-"}
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


def audio_copy(in_file, stream, out_rate):
    """Decide if input audio stream should be copied"""
    if opts.global_start or opts.f_audio or opts.no_copy:
        return False

    # Shorter values speed up test, but only approximate avg. bitrate
    # 0 will copy entire audio stream -> exact
    copy_dur = []
    if opts.audio_test_dur:
        copy_dur = ["-t", str(opts.audio_test_dur)]

    command = ["ffmpeg", "-y", "-v", "error", "-i", in_file]
    command.extend(copy_dur)
    command.extend(["-map", "0:a:" + str(stream),
                    "-c", "copy", opts.temp_name + ".mkv"])
    subprocess.run(command)

    command = ["ffprobe", "-v", "error",
               "-show_format", "-show_streams",
               "-print_format", "json",
               opts.temp_name + ".mkv"]
    out_json = subprocess.run(command, stdout=subprocess.PIPE).stdout
    out_json = json.loads(out_json)

    in_rate = out_json['format']['bit_rate']
    in_codec = out_json['streams'][0]['codec_name']

    codecs = ["vorbis"]
    if opts.a_codec == "libopus":
        codecs.append("opus")

    # *1.05 since bitrate allocation is no exact business
    if in_codec in codecs and opts.force_copy and in_rate <= out_rate*1000*1.05:
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
           and os.path.exists("ffmpeg2pass-0.log"):
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


def clean():
    """Clean leftover file in the workspace"""
    for ext in [".webm", ".mkv"]:
        if os.path.exists(opts.temp_name + ext):
            os.remove(opts.temp_name + ext)
    if opts.passes == 2:
        if os.path.exists("ffmpeg2pass-0.log"):
            os.remove("ffmpeg2pass-0.log")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main script
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def main():
    """Main function body"""
    check_prereq()
    parse_cli()
    if not opts.color:
        fgcolors.disable()
    check_options()
    check_filters()
    print_options()

    msg("\n### Start conversion ###\n", level=2, color=fgcolors.HEADER)
    restrictor = FileConverter()

    for i, path in enumerate(input_list):
        resolve_path(path)
        video = ConvertibleFile(FileInfo(path))

        msg(f"File {fgcolors.FILE}{i+1}{fgcolors.DEFAULT} (of {len(input_list)}): "
            f"{fgcolors.FILE}{video.info.input}{fgcolors.DEFAULT}")

        if video.info.ext == "mkv" and not opts.mkv_fallback:
            err(f"{video.info.input}: "
                "Conversion of image-based subtitles not supported!")
            clean()
            continue

        # Check for basic stream order assumptions
        # First stream: video stream
        # Everything afterwards: non-video streams
        # if not in_json['streams'][0]['codec_type'] == "video":
            # err(i)
            # err("Error: Unsupported stream order (first stream not video)!")
            # clean()
            # continue
        # try:
            # if in_json['streams'][1]['codec_type'] == "video":
                # err(i)
                # err("Error: More than one video stream per file not supported!")
                # clean()
                # continue
        # except IndexError:
            # pass

        msg(indent(dedent(f"""
            Verbosity:  {' '.join(video.verbosity)}
            Input/trim: {' '.join(video.input)}
            Mapping:    {' '.join(video.map)}
            Audio:      {' '.join(video.audio)}
            Subtitles:  {' '.join(video.subs)}
            Output:     {os.path.abspath(video.info.output)}
            """), "  "),
            level=2)

        restrictor.process(video)
        restrictor.reset()

        clean()


# Execute main function
if __name__ == '__main__':
    opts = Options()
    input_list = []

    try:
        main()
    except KeyboardInterrupt:
        err("\nUser Interrupt!", color=fgcolors.WARNING)
        clean()
        sys.exit(status.INT)

    msg("\n### Finished ###\n", level=2, color=fgcolors.HEADER)
    if size_fail:
        sys.exit(status.SIZE)
    sys.exit(0)
