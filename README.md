# Restricted-WebM

A Python script to produce WebMs within a certain file size limit.  
The goal is to automatically produce decent looking WebMs. Little to no user input or prior experience required.    

The old version (written in Bash) can be found [here](https://github.com/HelpSeeker/Restricted-WebM-legacy-).

### Requirements

* Python 3.6
* ffmpeg and ffprobe (both available via your PATH)

### Usage
```
python restrict.py [OPTIONS]... INPUT [INPUT]...

Basic options:

 -h, --help                 show this help message and exit
 -t, --trim                 prompt user for trim settings for each video
 -a, --audio                use input audio (if present)
 -s, --size <...>           specify file size limit in MiB (default: 3)
 -f, --filter <...>         pass custom ffmpeg filters
 -p, --passes {1,2}         force single/two-pass encoding (default: 2)
 -ss, --start <...>         specify start time for all input videos in sec.
 -to, --end <...>           specify end time for all input videos in sec.
 --subtitles                use input subtitles (if present)

Advanced options:
 
 -u, --undershoot <...>     specify undershoot limit (default 0.75)
 -i, --iterations <...>     iterations for each bitrate mode (default: 3)
 -fs, --force-stereo        force stereo audio output
 -bf, --basic-format        limit the output to max. one video/audio stream
 -mih, --min-height <...>   force min. output height (default: 240)
 -mah, --max-height <...>   force max. output height
 --bpp <...>                specify custom bpp threshold (default: 0.075)
 --min-fps <...>            specify the min. framerate threshold (default: 24)
 --max-fps <...>            specify a max. framerate threshold
 --opus                     use and allow Opus as audio codec
 --min-audio <...>          force min. audio channel bitrate (default: 24)
 --max-audio <...>          force max. audio channel bitrate (default: 96)
 --mkv-fallback             allow usage of MKV for image-based subtitles
 --no-filter-firstpass      disable filters during the first pass
 --no-copy                  disable stream copying
 --force-copy               force-copy compatible audio (!) streams
 --no-qmax                  skip the first bitrate mode (VBR with qmax)
 --audio-factor <...>       factor used to choose audio bitrate (default: 5.5)
 --debug                    only print ffmpeg commands
```

For further information consult the [wiki](https://github.com/HelpSeeker/Restricted-WebM/wiki)!
