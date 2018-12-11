"""Define classes to hold input video and output settings information."""

from os import path, mkdir, rmdir, remove
from subprocess import run

from utils.error import log_error
from utils.entry import start_time, end_time
from utils import info

class InputProperties():
    """Contain input properties (paths)."""

    def __init__(self, in_path, ext):
        """Get input and output paths."""
        # os.path used for better compatibility
        self.in_path = in_path
        self.in_dir = path.dirname(self.in_path)
        self.in_name = path.splitext(path.basename(self.in_path))[0]

        self.out_name = self.in_name + ext
        self.out_dir = path.join(self.in_dir, "webm_done")
        self.out_path = path.join(self.out_dir, self.out_name)

class TimeProperties():
    """Contain time/trim properties."""

    def __init__(self, args, in_file):
        """Get duration, start and end time."""
        in_path = in_file.i_prop.in_path
        self.in_dur = info.length(in_path)
        self.start = 0
        self.end = self.in_dur

        if args.trim:
            self.start = start_time(in_file)
            self.end = end_time(in_file, self.start, self.in_dur)
        if args.start != 0:
            if args.start >= self.in_dur:
                in_file.internal_error = True
                log_error(in_path, "wrong start")
                return
            self.start = args.start
        if args.end != 0:
            if args.end > self.in_dur:
                in_file.internal_error = True
                log_error(in_path, "wrong end")
                return
            self.end = args.end
        self.out_dur = self.end - self.start

class AudioProperties():
    """Contain audio properties."""

    def __init__(self, in_path):
        """Store information of the input audio streams in lists."""
        self.streams = info.audio_stream_count(in_path)
        self.channels = []
        self.bitrate = []
        self.codec = []

        for index in range(self.streams):
            self.channels.append(info.audio_channel_count(in_path, index))
            self.bitrate.append(info.audio_input_bitrate(in_path, index))
            self.codec.append(info.audio_codec(in_path, index))

class VideoProperties():
    """Contain video properties."""

    def __init__(self, args, in_path):
        """Get video stream properties."""
        # When custom video filters, get settings after applying filters
        if args.video_filters:
            out_dir = "webm_temp"
            out_name = "temp.mkv"
            out_path = path.join(out_dir, out_name)

            if not path.exists(out_dir):
                mkdir(out_dir)

            command = ["ffmpeg",
                       "-v", "panic",
                       "-i", in_path,
                       "-t", "0.1",
                       "-map", "0:v",
                       "-c:v", "rawvideo",
                       "-filter_complex", args.filter,
                       "-strict", "-2",
                       out_path]

            run(command)

            self.fps = info.framerate(out_path)
            self.height = info.height(out_path)
            self.ratio = info.ratio(out_path, self.height)

            if path.exists(out_path):
                remove(out_path)
            rmdir(out_dir)
        else:
            self.fps = info.framerate(in_path)
            self.height = info.height(in_path)
            self.ratio = info.ratio(in_path, self.height)

class InputVideo():
    """Contain all infos about the input file."""

    def __init__(self, args, in_path):
        """Check file existence and store all input information."""
        self.internal_error = False

        if not path.exists(in_path):
            self.internal_error = True
            log_error(in_path, "non-existent input")
            return

        # Get subtitle infos
        self.image_sub = info.image_subtitles(in_path)

        ext = ".webm"
        if args.subtitles:
            if self.image_sub and args.mkv_fallback:
                ext = ".mkv"
            elif self.image_sub:
                self.internal_error = True
                log_error(in_path, "image-based subtitles")
                return

        self.i_prop = InputProperties(in_path, ext)
        self.t_prop = TimeProperties(args, self)
        self.a_prop = AudioProperties(in_path)
        self.v_prop = VideoProperties(args, in_path)
