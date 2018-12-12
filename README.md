# Restricted-WebM

A Python script to produce WebMs within a certain file size limit.  
The goal is to produce decent looking videos while requiring minimum user experience/input.

### Requirements

* Python 3.6
* ffmpeg and ffprobe (both available via your PATH)

### Usage
```
python restrict.py [OPTIONS]... INPUT [INPUT]...
```

### Options

Option | Description
------ | -----------
`-h, --help` | Show a help text
`-t, --trim` | Prompt the user for start and end time, which are used to trim the input. Both values must be specified in seconds. The prompt appears for each input video
`-a, --audio` | Enable audio output. Vorbis is used by default
`-s, --size <...>` | Specify the file size limit in MiB. Default: 3
`-f, --filter <...>` | Pass custom ffmpeg filters. Using scale / fps will disable automatic downscaling / frame rate dropping
`-p, --passes {1,2}` | Use single- or 2-pass encoding. 2-pass encoding will offer a better bitrate control (basically broken during single pass) and the usage of alternate reference frames as well as temporal filtering. Single pass encoding should only be used when working with very low bitrates (< 200-300Kbps), as it provides a more consistent quality. Default: 2
`-u, --undershoot <...>` | Specify a minimum file size. It's specified as percentage of the upper file size limit. 0 -> no lower limit. 1 -> exactly the upper file size limit. Values up to 0.95 are usually no problem. Anything above will lead to a lot more encoding attempts for minimal gain. Default: 0.75
`-i, --iterations <...>` | Limit the maximum amount of encoding attempts. The script will make max. ix3 attempts to get the WebM below the file size limit. Additionally it will max. ix2 attempts to raise it above the undershoot limit. Default: 3
`-ss, --start <...>` | Start encoding all input videos at the specified time
`-to, --end <...>` | End encoding all input videos at the specified time
`-fs, --force-stereo` | Force 2 channel output audio
`-bf, --basic-format` | Ensure that the output only contains one video and max. one audio stream. This option has no influence on the number of subtitles
`-mih, --min-height <...>` | Specify min. output height. This option can't be used to upscale a video. Default: 240
`-mah, --max-height <...>` | Specify max. output height. Might be useful if you think the script doesn't apply enough downscaling (e.g. very difficult footage)
`--bpp <...>` | Define target bits per pixel value. Higher numbers mean a higher output quality at the cost of further of downscaling / frame rate reduction. 0.075 for high quality, 0.04 for moderate quality, <0.02 for low quality (experience values). Difficult footage needs higher values, easy footage can stand lower ones. Default: 0.075
`--min-fps <...>` | Specify min. output frame rate. This option can't be used to raise the original frame rate. Default: 24
`--max-fps <...>` | Specify max. output frame rate. To force a custom frame rate, either use `--max-fps x -min-fps x` or ffmpeg's fps filter
`--opus` | Use Opus as audio codec. This option is required to allow stream copying for Opus audio. Please note, ffmpeg currently has problems with certain surround sound configurations (see this [bugtracker](https://trac.ffmpeg.org/ticket/5718)). In such a case Vorbis will be used as fallback
`--subtitles` | Enable output subtitles. If input subtitles are present this will change ffmpeg's input syntax and lead to longer encoding times
`--min-audio <...>` | Specify a min. audio channel (!) bitrate. Can be used to raise the output audio bitrate. Default: 24
`--max-audio <...>` | Specify a max. audio channel (!) bitrate. Currently it can't be lowered below 24Kbps. Default: 96
`--mkv-fallback` | Use MKV as fallback container, when the input has image-based subtitles. Image-based subtitles can't be easily converted to text-based subtitles (which is necessary for WebM support) and will throw an error without this option set. Has no effect without the `--subtitles` flag
`--no-filter-firstpass` | Disable custom filters (via `-f <...>`) during the first pass when using 2-pass encoding. This can be useful when resource intensive filters get applied (e.g. nlmeans)
`--no-copy` | Disable audio stream copying
`--force-copy` | Force audio stream copying even if the bitrate is likely too high to achieve good enough video results. This option has no influence on audio streams that aren't WebM compatible, when audio filters are used or when the input gets trimmed
`--debug` | Prints the ffmpeg commands instead of executing them. Produces no output files. User gets prompted for the output size in MiB
