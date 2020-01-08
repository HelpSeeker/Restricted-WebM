#!/usr/bin/env python3

import os
import sys
import json
import subprocess
from fnmatch import fnmatch

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Global constants
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Error codes
# 1 -> missing required software
# 2 -> invalid user-specified option
# 3 -> misc. runtime error
# 4 -> not all input videos could be fit into the file size range
# 5 -> termination was requested mid-way by the user (i.e. Ctrl+C)
err_stat = {
    'dep': 1,
    'opt': 2,
    'run': 3,
    'size': 4,
    'int': 5
}
size_fail = False

class Colors:
    """Store ANSI escape codes for colorized output."""

    # https://en.wikipedia.org/wiki/ANSI_escape_code#Colors
    FILE = '\033[35m'
    ATTEMPT = '\033[32m'
    HEADER = '\033[1;36m'
    FILE_INFO = FILE
    ATTEMPT_INFO = ATTEMPT
    SIZE_INFO = ATTEMPT
    RESET = '\033[0m'

    def disable(self):
        self.FILE = ''
        self.ATTEMPT = ''
        self.HEADER = ''
        self.FILE_INFO = ''
        self.ATTEMPT_INFO = ''
        self.SIZE_INFO = ''
        self.RESET = ''

fgcolors = Colors()

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Classes
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

class Options:
    """Stores general options"""

    # Common user settings
    verbosity = 1
    audio = False
    limit = 3
    f_user = None
    passes = 2
    under = 0.75
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
    height_reduction = 10
    min_quality = 50
    crf_value = 10
    min_bitrate_ratio = 0.9
    skip_limit = 0.01
    a_factor = 5.5
    fallback_codec = "libvorbis"
    temp_name = "temp"
    out_dir_name = "webm_done"

    # Don't touch
    f_audio = False
    f_video = False


class Values:
    """Gathers information about output settings"""

    def __init__(self):
        """Initialize all properties"""
        self.path = {}
        self.trim = {}
        self.audio = {}
        self.video = {}
        self.filter = {}

    def calc_path(self, in_file):
        """Gather all necessary infos regarding output paths"""
        in_name = os.path.basename(in_file)
        in_name = os.path.splitext(in_name)[0]
        in_dir = os.path.dirname(in_file)

        if in_name == opts.temp_name:
            err(in_file)
            err(f"Error! Input has reserved filename ('{opts.temp_name}')")
            sys.exit(err_stat['dep'])

        if out_image_subs(in_file):
            self.path['ext'] = ".mkv"
        else:
            self.path['ext'] = ".webm"

        out_name = in_name + self.path['ext']
        out_dir = os.path.join(in_dir, opts.out_dir_name)
        out_file = os.path.join(out_dir, out_name)

        self.path['dir'] = out_dir
        self.path['file'] = out_file
        self.path['temp'] = opts.temp_name + self.path['ext']

    def calc_trim(self, in_file, in_json):
        """Calculate values regarding trim settings"""
        try:
            dur = float(in_json['format']['duration'])
        except KeyError:
            # Brute-force detect, if ffprobe can't get duration (i.e. GIFs or other images)
            # Encodes input as AVC (fast) and reads duration from the output
            command = ["ffmpeg", "-y", "-v", "error",
                       "-i", in_file, "-map", "0:v",
                       "-c:v", "libx264", "-preset", "ultrafast", "-crf", "51",
                       opts.temp_name + ".mkv"]
            subprocess.run(command)

            command = ["ffprobe", "-v", "error",
                       "-show_format", "-show_streams",
                       "-print_format", "json", opts.temp_name + ".mkv"]
            out_json = subprocess.run(command, stdout=subprocess.PIPE).stdout
            out_json = json.loads(out_json)

            dur = float(out_json['format']['duration'])

        start = 0
        end = dur

        if opts.global_start and opts.global_start < dur:
            start = opts.global_start
        if opts.global_end and opts.global_end <= dur:
            end = opts.global_end

        self.trim['in_dur'] = dur
        self.trim['out_dur'] = round(end - start, 3)

    def calc_audio(self, in_json):
        """Calculate values regarding audio settings"""
        max_size = int(opts.limit*1024**2)

        self.audio['bitrate'] = 0
        self.audio['streams'] = 0
        self.audio['channels'] = 0
        # List to hold the individual stream output bitrates
        self.audio['#'] = []
        # 44100 is an arbitrary value to check later change
        self.audio['rate'] = 44100

        if not opts.audio:
            return

        streams = int(in_json['format']['nb_streams'])

        for s in range(streams):
            if in_json['streams'][s]['codec_type'] == "audio":
                if opts.force_stereo:
                    channels = 2
                else:
                    channels = int(in_json['streams'][s]['channels'])

                self.audio['#'].append(channels)
                self.audio['channels'] += channels
                self.audio['streams'] += 1

                if opts.basic_format:
                    break

        # formula originally based on my experience with stereo audio for 4MB WebMs
        # later on extended to accommodate more bitrates / channels
        factor = max_size*8 / (self.trim['out_dur']*self.audio['channels']*4*1000)
        # Audio factor decides how much of the size limit gets reserved for audio
        factor /= opts.a_factor

        if factor < 1:
            c_bitrate = 6
        elif factor < 2:
            c_bitrate = 8
        elif factor < 3:
            c_bitrate = 12
        elif factor < 4:
            c_bitrate = 16
        elif factor < 6:
            c_bitrate = 24
        elif factor < 8:
            c_bitrate = 32
        elif factor < 28:
            c_bitrate = 48
        elif factor < 72:
            c_bitrate = 64
        elif factor < 120:
            c_bitrate = 80
        else:
            c_bitrate = 96

        if c_bitrate < opts.min_audio:
            c_bitrate = opts.min_audio
        if opts.max_audio and c_bitrate > opts.max_audio:
            c_bitrate = opts.max_audio

        # Use internal stream count to get right audio index
        for s in range(self.audio['streams']):
            # Channel number already stored, so just mult. with channel bitrate
            self.audio['#'][s] *= c_bitrate
            self.audio['bitrate'] += self.audio['#'][s]

        # Downsample necessary for lower bitrates with libvorbis
        if c_bitrate <= 6:
            self.audio['rate'] = 8000
        elif c_bitrate <= 12:
            self.audio['rate'] = 12000
        elif c_bitrate <= 16:
            self.audio['rate'] = 24000

    def calc_video(self, sizes, init):
        """Calculate values regarding video settings"""
        max_size = int(opts.limit*1024**2)

        # Reset bitrate for each bitrate mode
        if init:
            bitrate = max_size*8 / (self.trim['out_dur']*1000) - self.audio['bitrate']
            bitrate = int(bitrate)
        else:
            # Size ratio dictates overall bitrate change, but audio bitrate is const
            # (v+a) = (v_old+a) * (max/curr)
            # v = v_old * (max/curr) + (max/curr - 1) * a
            a_offset = int((max_size/sizes.temp - 1) * self.audio['bitrate'])
            new_rate = int(self.video['bitrate'] * max_size/sizes.temp + a_offset)
            min_rate = int(self.video['bitrate'] * opts.min_bitrate_ratio)
            # Force min. decrease (% of last bitrate)
            if min_rate < new_rate < self.video['bitrate']:
                bitrate = min_rate
            else:
                bitrate = new_rate

        if bitrate <= 0:
            bitrate = opts.fallback_bitrate

        self.video['bitrate'] = bitrate

    def calc_filter(self, in_file, in_json):
        """Calculate values regarding (script) filter settings"""
        # Test for user set scale/fps filter
        if opts.f_user:
            user_scale = "scale" in opts.f_user
            user_fps = "fps" in opts.f_user
        else:
            user_scale = False
            user_fps = False

        h = in_json['streams'][0]['height']
        w = in_json['streams'][0]['width']
        ratio = w/h

        fps = in_json['streams'][0]['r_frame_rate'].split("/")
        # Sometimes gets reported as fractional, sometimes not
        if len(fps) == 2:
            fps = int(fps[0])/int(fps[1])
        elif len(fps) == 1:
            fps = float(fps[0])
        else:
            err("Unsuspected fps formatting in Values.calc_filter()!")
            sys.exit(err_stat['run'])

        # If user scale/fps filter -> test encode
        # Read the effect (i.e. changed resolution / frame rate) from output
        if user_scale or user_fps:
            command = ["ffmpeg", "-y", "-v", "error",
                       "-i", in_file, "-vframes", "1",
                       "-filter_complex", opts.f_user,
                       opts.temp_name + ".mkv"]
            subprocess.run(command)

            command = ["ffprobe", "-v", "error",
                       "-show_format", "-show_streams",
                       "-print_format", "json",
                       opts.temp_name + ".mkv"]
            out_json = subprocess.run(command, stdout=subprocess.PIPE).stdout
            out_json = json.loads(out_json)

            h = out_json['streams'][0]['height']
            w = out_json['streams'][0]['width']
            ratio = w/h

            fps = out_json['streams'][0]['r_frame_rate'].split("/")
            if len(fps) == 2:
                fps = int(fps[0])/int(fps[1])
            elif len(fps) == 1:
                fps = float(fps[0])
            else:
                err("Unsuspected fps formatting in Values.calc_filter()!")
                sys.exit(err_stat['run'])

        self.filter['in_height'] = h
        self.filter['out_height'] = h
        self.filter['in_fps'] = fps
        self.filter['out_fps'] = fps

        if user_scale and user_fps:
            return

        # Perform frame rate drop
        for f in opts.fps_list:
            if user_fps:
                break

            bpp = self.video['bitrate']*1000 / (fps*ratio*h**2)
            if bpp >= opts.bpp_thresh/2:
                break
            fps = f

        # Enfore frame rate thresholds
        if fps < opts.min_fps:
            fps = opts.min_fps
        if opts.max_fps and fps > opts.max_fps:
            fps = opts.max_fps
        if fps > self.filter['in_fps']:
            fps = self.filter['in_fps']
        self.filter['out_fps'] = fps

        # Perform downscale
        while True:
            if user_scale:
                break

            bpp = self.video['bitrate']*1000 / (fps*ratio*h**2)
            if bpp >= opts.bpp_thresh:
                break
            h -= opts.height_reduction

        # Enforce height thresholds
        if h < opts.min_height:
            h = opts.min_height
        if opts.max_height and h > opts.max_height:
            h = opts.max_height
        if h > self.filter['in_height']:
            h = self.filter['in_height']
        self.filter['out_height'] = h


class Settings:
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

    def get_verbosity(self):
        """Assemble FFmpeg settings regarding verbosity"""
        if opts.ffmpeg_verbosity == "stats":
            self.verbosity.extend(["-v", "error", "-stats"])
        else:
            self.verbosity.extend(["-v", opts.ffmpeg_verbosity])

    def get_trim(self, in_file, val):
        """Assemble FFmpeg settings regarding input/trimming"""
        in_dur = val.trim['in_dur']

        if opts.global_start and opts.global_start < in_dur:
            self.input.extend(["-ss", str(opts.global_start)])

        self.input.extend(["-i", in_file])

        if opts.global_end and opts.global_end <= in_dur:
            self.input.extend(["-t", str(val.trim['out_dur'])])

    def get_map(self, val):
        """Assemble FFmpeg settings regarding mapping"""
        self.map.extend(["-map", "0:v"])

        for s in range(val.audio['streams']):
            if not opts.audio:
                break
            self.map.extend(["-map", "0:a:" + str(s) + "?"])
            if opts.basic_format:
                break

        if opts.subs:
            self.map.extend(["-map", "0:s?"])

    def get_subs(self, in_file):
        """Assemble FFmpeg settings regarding subtitles"""
        if not opts.subs:
            return

        if opts.burn_subs:
            self.subtitle.extend(["-sn"])
        elif out_image_subs(in_file):
            self.subtitle.extend(["-c:s", "copy"])
        else:
            self.subtitle.extend(["-c:s", "webvtt"])

    def get_audio(self, in_file, val):
        """Assemble FFmpeg settings regarding audio"""
        if not opts.audio:
            return

        for s in range(val.audio['streams']):
            s_bitrate = val.audio['#'][s]

            if audio_copy(in_file, s, s_bitrate):
                self.audio.extend(["-c:a:" + str(s), "copy"])
            elif opts.a_codec == "libopus" and opus_fallback(in_file, s):
                self.audio.extend(["-c:a:" + str(s), opts.fallback_codec])
                self.audio.extend(["-b:a:" + str(s), str(s_bitrate) + "K"])
            else:
                self.audio.extend(["-c:a:" + str(s), opts.a_codec])
                self.audio.extend(["-b:a:" + str(s), str(s_bitrate) + "K"])

            if opts.basic_format:
                break

        # -ac/-ar have no effect without audio encoding
        # there's no need for additional checks
        if opts.force_stereo:
            self.audio.extend(["-ac", "2"])
        if val.audio['rate'] < 44100:
            self.audio.extend(["-ar", str(val.audio['rate'])])

    def get_video(self, mode, val):
        """Assemble FFmpeg settings regarding video"""
        # Function gets called several times for a file
        # Resetting necessary
        self.video = []

        self.video.extend(["-c:v", opts.v_codec])
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

        self.video.extend(["-b:v", str(val.video['bitrate']) + "K"])

        if opts.crf and mode in (1, 2):
            self.video.extend(["-crf", str(opts.crf_value)])

        if mode == 1:
            self.video.extend(["-qmax", str(opts.min_quality)])
        elif mode == 3:
            self.video.extend(["-minrate:v", str(val.video['bitrate']) + "K",
                               "-maxrate:v", str(val.video['bitrate']) + "K",
                               "-bufsize", str(val.video['bitrate']*5) + "K",
                               "-skip_threshold", "100"])

        self.video.extend(["-threads", str(opts.threads)])

        # This check isn't necessary, but it avoids command bloat
        if opts.v_codec == "libvpx-vp9" and opts.threads > 1:
            self.video.extend(["-tile-columns", "6",
                               "-tile-rows", "2",
                               "-row-mt", "1"])

    def get_filters(self, val):
        """Assemble (script) filter string"""
        # Function gets called several times for a file
        # Resetting necessary
        self.filter = []

        out_h = val.filter['out_height']
        out_fps = val.filter['out_fps']
        in_h = val.filter['in_height']
        in_fps = val.filter['in_fps']

        f_scale = "scale=-2:" + str(out_h) + ":flags=lanczos"
        f_fps = "fps=" + str(out_fps)

        if out_h < in_h and out_fps < in_fps:
            self.filter.extend(["-vf", f_scale + "," + f_fps])
        elif out_h < in_h:
            self.filter.extend(["-vf", f_scale])
        elif out_fps < in_fps:
            self.filter.extend(["-vf", f_fps])


class SizeData:
    """Save and manage output file sizes"""

    def __init__(self):
        """Initialize all properties"""
        self.temp = 0
        self.out = 0
        self.last = 0

    def update(self, temp_file, out_file, enhance):
        """Update all properties during the limiting process"""
        if opts.debug:
            try:
                user = float(input("Output size in MB: "))
            except ValueError:
                # Use empty input as shortcut to end debug mode (simulate success)
                user = opts.limit

            self.last = self.temp
            self.temp = int(user * 1024**2)
        else:
            self.last = self.temp
            self.temp = os.path.getsize(temp_file)

        if enhance:
            if self.out < self.temp <= int(opts.limit * 1024**2):
                self.out = self.temp
                if not opts.debug:
                    os.replace(temp_file, out_file)
        else:
            if not self.out or self.temp < self.out:
                self.out = self.temp
                if not opts.debug:
                    os.replace(temp_file, out_file)

    def skip_mode(self):
        """Check for insufficient change"""
        diff = abs((self.temp-self.last) / self.last)

        return bool(diff < opts.skip_limit)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def err(*args, **kwargs):
    """Print to stderr"""
    print(*args, file=sys.stderr, **kwargs)


def usage():
    """Print help text"""
    print(f"""Usage: {os.path.basename(sys.argv[0])} [OPTIONS] INPUT [INPUT]...

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

All output will be saved in '{opts.out_dir_name}/'.
'{opts.out_dir_name}/' is located in the same directory as the input.

For more information visit:
https://github.com/HelpSeeker/Restricted-WebM-in-Bash/wiki""")


def check_prereq():
    """check existence of required software"""
    reqs = ["ffmpeg", "ffprobe"]

    for r in reqs:
        try:
            subprocess.run([r], stdout=subprocess.DEVNULL, \
                                stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            err(f"Error: {r} not found!")
            sys.exit(err_stat['dep'])


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
                sys.exit(err_stat['opt'])

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
            elif opt in ("-v", "--verbose"):
                opts.verbosity = 2
            elif opt in ("-a", "--audio"):
                opts.audio = True
            elif opt in ("-s", "--size"):
                opts.limit = float(arg)
            elif opt in ("-f", "--filters"):
                opts.f_user = arg
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
            sys.exit(err_stat['opt'])


def check_options():
    """Check validity of command line options"""
    # Check for input files
    if not input_list:
        err("No input files specified!")
        sys.exit(err_stat['opt'])

    # Special integer checks
    if opts.passes not in (1, 2):
        err("Only 1 or 2 passes are supported!")
        sys.exit(err_stat['opt'])
    elif opts.iters < 1:
        err("Script needs at least 1 iteration per mode!")
        sys.exit(err_stat['opt'])
    elif opts.min_height <= 0:
        err("Min. height must be greater than 0!")
        sys.exit(err_stat['opt'])
    elif opts.max_height and opts.max_height < opts.min_height:
        err("Max. height can't be less than min. height!")
        sys.exit(err_stat['opt'])
    elif opts.threads <= 0:
        err("Thread count must be larger than 0!")
        sys.exit(err_stat['opt'])
    elif opts.threads > 16:
        # Just a warning
        err("More than 16 threads are not recommended.")
    elif opts.max_audio and opts.max_audio < 6:
        err("Max. audio channel bitrate must be greater than 6 Kbps!")
        sys.exit(err_stat['opt'])
    elif opts.max_audio and opts.max_audio < opts.min_audio:
        err("Max. audio channel bitrate can't be less than min. audio channel bitrate!")
        sys.exit(err_stat['opt'])

    # Special float checks
    if opts.limit <= 0:
        err("Target file size must be greater than 0!")
        sys.exit(err_stat['opt'])
    elif opts.global_end and opts.global_end <= 0:
        err("End time must be greater than 0!")
        sys.exit(err_stat['opt'])
    elif opts.global_start and opts.global_end and \
         opts.global_end <= opts.global_start:
        err("End time must be greater than start time!")
        sys.exit(err_stat['opt'])
    elif opts.under > 1:
        err("Undershoot ratio can't be greater than 1!")
        sys.exit(err_stat['opt'])
    elif opts.bpp_thresh <= 0:
        err("Bits per pixel threshold must be greater than 0!")
        sys.exit(err_stat['opt'])
    elif opts.max_fps and opts.max_fps < 1:
        err("Max. frame rate can't be less than 1!")
        sys.exit(err_stat['opt'])
    elif opts.max_fps and opts.max_fps < opts.min_fps:
        err("Max. frame rate can't be less than min. frame rate!")
        sys.exit(err_stat['opt'])

    # Check for mutually exclusive flags
    if opts.force_copy and opts.no_copy:
        err("--force-copy and --no-copy are mutually exclusive!")
        sys.exit(err_stat['opt'])

    # Misc. checks
    if opts.transparency and opts.pix_fmt != "yuva420p":
        err("Only yuva420p supports transparency!")
        sys.exit(err_stat['opt'])

    vp8_pix_fmt = ["yuv420p", "yuva420p"]
    vp9_pix_fmt = ["yuv420p", "yuva420p",
                   "yuv422p", "yuv440p", "yuv444p",
                   "yuv420p10le", "yuv422p10le", "yuv440p10le", "yuv444p10le",
                   "yuv420p12le", "yuv422p12le", "yuv440p12le", "yuv444p12le",
                   "gbrp", "gbrp10le", "gbrp12le"]

    if opts.v_codec == "libvpx" and opts.pix_fmt not in vp8_pix_fmt:
        err(f"'{opts.pix_fmt}' isn't supported by VP8!")
        err("See 'ffmpeg -h encoder=libvpx' for more infos.")
        sys.exit(err_stat['opt'])
    elif opts.v_codec == "libvpx-vp9" and opts.pix_fmt not in vp9_pix_fmt:
        err(f"'{opts.pix_fmt}' isn't supported by VP9!")
        err("See 'ffmpeg -h encoder=libvpx-vp9' for more infos.")
        sys.exit(err_stat['opt'])

    loglevels = ["quiet", "panic", "fatal",
                 "error", "warning", "info",
                 "verbose", "debug", "trace",
                 "stats"]

    if opts.ffmpeg_verbosity not in loglevels:
        err(f"'{opts.ffmpeg_verbosity}' isn't a supported FFmpeg verbosity level!")
        err("Supported levels:")
        err(loglevels)
        sys.exit(err_stat['opt'])


def check_filters():
    """Test user set filters"""
    global opts

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
        sys.exit(err_stat['opt'])

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


def print_options():
    """Print all settings for verbose output"""
    print(fgcolors.HEADER, end="")
    print("\n### Settings for the current session ###\n", end=fgcolors.RESET+"\n")

    print(f"""Paths:
  Temporary filename:          {opts.temp_name}
  Destination directory name:  {opts.out_dir_name}

Size:
  Max. size (MB):              {opts.limit}
  Undershoot ratio:            {opts.under}
  Max. size (Bytes):           {int(opts.limit*1024**2)}
  Min. size (Bytes):           {int(opts.limit*1024**2*opts.under)}

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
  Possible frame rates:        {opts.fps_list}

Misc.:
  Only 1 video/audio stream:   {opts.basic_format}
  FFmpeg verbosity level:      {opts.ffmpeg_verbosity}
  Debug mode:                  {opts.debug}""")


def print_file_info(flags, val):
    """Print general (i.e. not adjusted during iterations) settings"""
    print(fgcolors.FILE_INFO, end="")
    print(f"""  Verbosity:  {flags.verbosity}
  Input/trim: {flags.input}
  Mapping:    {flags.map}
  Audio:      {flags.audio}
  Subtitles:  {flags.subtitle}
  Output:     {val.path['file']}""", end=fgcolors.RESET+"\n")


def print_iter_info(flags):
    """Print attempt (i.e. adjusted during iterations) settings"""
    print(fgcolors.ATTEMPT_INFO, end="")
    print(f"""  Video:      {flags.video}
  Filters:    {flags.filter}""", end=fgcolors.RESET+"\n")


def print_size_info(sizes):
    """Print size information"""
    print(fgcolors.SIZE_INFO, end="")
    print(f"""  Curr. size: {sizes.temp}
  Last size:  {sizes.last}
  Best try:   {sizes.out}""", end=fgcolors.RESET+"\n")


def resolve_dir(out_dir):
    """Change into output directory"""
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


def call_ffmpeg(out_file, flags, mode):
    """Execute FFmpeg (and assemble pass specific settings)"""
    v_raw = ["-c:v", "copy"]
    a_raw = ["-c:a", "copy"]
    f_raw = []
    if opts.global_start or opts.f_video:
        v_raw = ["-c:v", "rawvideo"]
    if opts.global_start or opts.f_audio:
        a_raw = ["-c:a", "pcm_s16le"]
    if opts.f_user:
        f_raw = ["-filter_complex", opts.f_user]

    for p in range(1, opts.passes+1):
        if opts.passes == 1 or mode == 3:
            p_flags = ["-cpu-used", "0", out_file]
        elif p == 1:
            p_flags = ["-cpu-used", "5", "-pass", "1", "-f", "null", "-"]
            if opts.no_filter_firstpass:
                f_raw = []
            if os.path.exists("ffmpeg2pass-0.log"):
                continue
        elif p == 2:
            p_flags = ["-cpu-used", "0", "-pass", "2", out_file]
            if opts.no_filter_firstpass and opts.f_user:
                f_raw = ["-filter_complex", opts.f_user]

        if opts.f_user:
            raw = ["ffmpeg", "-y", "-v", "error"]
            raw.extend(flags.input)
            raw.extend(flags.map)
            raw.extend(v_raw)
            raw.extend(a_raw)
            raw.extend(["-c:s", "copy"])
            raw.extend(f_raw)
            raw.extend(["-strict", "-2", "-f", "matroska", "-"])

        webm = ["ffmpeg", "-y"]
        webm.extend(flags.verbosity)
        if opts.f_user:
            webm.extend(["-i", "-", "-map", "0"])
        else:
            webm.extend(flags.input)
            webm.extend(flags.map)
        webm.extend(flags.video)
        webm.extend(flags.audio)
        webm.extend(flags.subtitle)
        webm.extend(flags.filter)
        webm.extend(p_flags)

        if opts.debug:
            if opts.f_user:
                print(raw)
            print(webm)
        else:
            if opts.f_user:
                raw_pipe = subprocess.Popen(raw, \
                                            stdout=subprocess.PIPE, \
                                            bufsize=10**8)
                subprocess.run(webm, stdin=raw_pipe.stdout)
            else:
                subprocess.run(webm)

        if mode == 3:
            break


def limit_size(in_file, in_json, val, flags, sizes):
    """Limit output size to be <=max_size"""
    max_size = int(opts.limit*1024**2)

    # VBR + qmax (1), VBR (2) and CBR (3)
    modes = 3
    # omit CBR when --no-cbr is used
    if opts.no_cbr:
        modes = 2

    for m in range(1, modes+1):
        if m == 1 and opts.no_qmax:
            continue

        for i in range(1, opts.iters+1):
            # i == 1 re-initialize, otherwise adjust
            val.calc_video(sizes, init=i == 1)
            val.calc_filter(in_file, in_json)
            flags.get_video(m, val)
            flags.get_filters(val)

            if opts.verbosity >= 1:
                print(fgcolors.ATTEMPT, end="")
                print(f"Mode: {m} (of 3) | Attempt {i} (of {opts.iters})", end=" | ")
                print(f"Height: {val.filter['out_height']}", end=" | ")
                print(f"FPS: {val.filter['out_fps']}", end=fgcolors.RESET+"\n")
            if opts.verbosity >= 2:
                print_iter_info(flags)

            call_ffmpeg(val.path['temp'], flags, m)

            sizes.update(val.path['temp'], val.path['file'], enhance=False)

            if opts.verbosity >= 2:
                print_size_info(sizes)

            # Skip remaining iters, if change too small (defaul: <1%)
            if i > 1 and sizes.skip_mode():
                break
            if sizes.out <= max_size:
                return m

    return m


def raise_size(in_file, in_json, m, val, flags, sizes):
    """Raise output size to be >=min_size (and still <=max_size)"""
    max_size = int(opts.limit*1024**2)
    min_size = int(opts.limit*1024**2*opts.under)

    for i in range(1, opts.iters+1):
        if min_size <= sizes.out <= max_size:
            return

        # don't re-initialize; adjust the last bitrate from limit_size()
        val.calc_video(sizes, init=False)
        val.calc_filter(in_file, in_json)
        flags.get_video(m, val)
        flags.get_filters(val)

        if opts.verbosity >= 1:
            print(fgcolors.ATTEMPT, end="")
            print(f"Enhance Attempt: {i} (of {opts.iters})", end=" | ")
            print(f"Height: {val.filter['out_height']}", end=" | ")
            print(f"FPS: {val.filter['out_fps']}", end=fgcolors.RESET+"\n")
        if opts.verbosity >= 2:
            print_iter_info(flags)

        call_ffmpeg(val.path['temp'], flags, m)

        sizes.update(val.path['temp'], val.path['file'], enhance=True)

        if opts.verbosity >= 2:
            print_size_info(sizes)

        # Skip remaining iters, if change too small (defaul: <1%)
        if sizes.skip_mode():
            return


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
    global size_fail

    check_prereq()
    parse_cli()
    if not opts.color:
        fgcolors.disable()
    check_options()
    check_filters()

    max_size = int(opts.limit*1024**2)
    min_size = int(opts.limit*1024**2*opts.under)

    if opts.verbosity >= 2:
        print_options()
        print(fgcolors.HEADER, end="")
        print("\n### Start conversion ###\n", end=fgcolors.RESET+"\n")

    for in_file in input_list:
        val = Values()
        flags = Settings()
        sizes = SizeData()

        if opts.verbosity >= 1:
            print(fgcolors.FILE, end="")
            print(f"Current file: {in_file}", end=fgcolors.RESET+"\n")

        val.calc_path(in_file)

        if val.path['ext'] == ".mkv" and not opts.mkv_fallback:
            err(in_file)
            err("Error: Conversion of image-based subtitles not supported!")
            clean()
            continue

        resolve_dir(val.path['dir'])

        command = ["ffprobe", "-v", "error",
                   "-show_format", "-show_streams",
                   "-print_format", "json", in_file]
        in_json = subprocess.run(command, stdout=subprocess.PIPE).stdout
        in_json = json.loads(in_json)

        # Check for basic stream order assumptions
        # First stream: video stream
        # Everything afterwards: non-video streams
        if not in_json['streams'][0]['codec_type'] == "video":
            err(in_file)
            err("Error: Unsupported stream order (first stream not video)!")
            clean()
            continue
        try:
            if in_json['streams'][1]['codec_type'] == "video":
                err(in_file)
                err("Error: More than one video stream per file not supported!")
                clean()
                continue
        except IndexError:
            pass

        val.calc_trim(in_file, in_json)
        val.calc_audio(in_json)

        flags.get_verbosity()
        flags.get_trim(in_file, val)
        flags.get_map(val)
        flags.get_subs(in_file)
        flags.get_audio(in_file, val)

        if opts.verbosity >= 2:
            print_file_info(flags, val)

        mode = limit_size(in_file, in_json, val, flags, sizes)
        if sizes.out > max_size:
            err(val.path['file'])
            err("Error: Still too large!")
            size_fail = True
            clean()
            continue

        raise_size(in_file, in_json, mode, val, flags, sizes)
        if sizes.out < min_size:
            err(val.path['file'])
            err("Error: Still too small!")
            size_fail = True

        clean()


# Execute main function
if __name__ == '__main__':
    opts = Options()
    input_list = []

    try:
        main()
    except KeyboardInterrupt:
        err("User Interrupt!")
        clean()
        sys.exit(err_stat['int'])
    if opts.verbosity >= 2:
        print(fgcolors.HEADER)
        print("### Finished ###\n", end=fgcolors.RESET+"\n")
    if size_fail:
        sys.exit(err_stat['size'])
    sys.exit(0)
