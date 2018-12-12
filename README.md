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

Option | Description
------ | -----------
`-h, --help` | Show a help text
`-t, --trim` | Prompt the user for start and end time, which are used to trim the input. Both values must be specified in seconds. The prompt appears for each input video
`-a, --audio` | Enable audio output. By default the audio gets encoded as Vorbis
`-s, --size <...>` | Specify the file size limit in MiB. Default: 3
`-f, --filter <...>` | Pass custom ffmpeg filters. Using scale / fps will disable automatic downscaling / frame rate dropping
`-p, --passes {1,2}` | Use single- or 2-pass encoding. By default 2-pass encoding will be used. This will offer a better bitrate control (libvpx's single pass bitrate control is broken and will require more attempts) and the usage of alternate reference frames as well as temporal filtering. Single pass encoding should only be used when working with very low bitrates (< 200-300Kbps), as it provides a more consistent quality
`-u, --undershoot <...>` | Specify a minimum file size. This lower limit is specified as percentage of the upper file size limit. 0 equals no lower limit, 1 would require the output to be exactly the upper file size limit. Values up to 0.95 are usually no problem. Anything above will lead to a lot more encoding attempts for minimal gain. Default: 0.75
`-i, --iterations <...>` | Limit the maximum amount of attempts per bitrate mode. Default: 3. There are three bitrate modes (VBR with qmax, VBR without qmax and CBR), so the total amount of attempts to reach the file size limit is i * 3 (9 by default). Additionally the script tries i * 2 (so 6 by default) times to reach the undershoot limit
`-ss, --start <...>` | Start encoding all input videos at the specified time. Useful if one tries to avoid the constant trim prompts
`-to, --end <...>` | End encoding all input videos at the specified time. Useful if one tries to avoid the constant trim prompts.
`-fs, --force-stereo` | Force 2 channel output audio. Gets applied to all streams
`-bf, --basic-format` | Ensure that the output only has one video and one audio stream. All additional audio streams after the first one get discarded. This option has no influence on the number of subtitles
`-mih, --min-height <...>` | Specify min. output height. The script will stop downscaling once this limit is reached, even if the bpp value didn't reach its threshold yet. This option can't be used to upscale a video. Default: 240
`-mah, --max-height <...>` | Specify max. output height. Even if the bpp threshold was already reached, the script will downscale further to reach this limit. Might be useful if you think the script doesn't apply enough downscaling (e.g. very difficult footage)
`--bpp <...>` | The main way of defining the output quality. The amount of downscaling / frame rate reduction is based on this value. Default: 0.075 (for high quality output). 0.04 is usually a good value for moderate qualtity WebMs. 0.02 and below produce low quality footage. For difficult input footage (e.g. lots of camera movement) it might be wise to raise this value. Easy input footage can stand lower values
`--min-fps <...>` | Specify min. output frame rate. The script won't reduce the frame rate past this limit, even if the bpp value didn't reach its threshold yet. This option can't be used to produce an output frame rate greater than the input frame rate. Default: 24
`--max-fps <...>` | Specify max. output frame rate. Please note that --max-fps can't be lower than --min-fps. To force a lower output frame rate it's wiser to use ffmpeg's fps filter
