# Restricted-WebM

A script to produce WebMs within a certain file size limit.

The goal is to automatically produce decent looking WebMs. Little to no user input or prior experience required.

**Alternative versions:**
* [New Bash version](https://github.com/HelpSeeker/Restricted-WebM/tree/bash)
* [Original (legacy) Bash version](https://github.com/HelpSeeker/Restricted-WebM/tree/legacy)

## Usage

```
Usage: restrict.py [OPTIONS] INPUT [INPUT]...

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
```

## Requirements

* Python 3
* [FFmpeg (incl. ffprobe)](https://www.ffmpeg.org/)

***

For further information consult the [wiki](https://github.com/HelpSeeker/Restricted-WebM/wiki)!
