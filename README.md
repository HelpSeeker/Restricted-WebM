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
`-s, --size <...>` | Specify the file size limit in MiB. Default: 3 MiB
`-f, --filter <...>` | Pass custom ffmpeg filters. Using scale / fps will disable automatic downscaling / frame rate dropping
`-p, --passes {1,2}` | Use single- or 2-pass encoding. By default 2-pass encoding will be used. This will offer a better bitrate control (libvpx's single pass bitrate control is broken and will require more attempts) and the usage of alternate reference frames as well as temporal filtering. Single pass encoding should only be used when working with very low bitrates (< 200-300Kbps), as it provides a more consistent quality
`-u, --undershoot <...>` | Specify a minimum file size. This lower limit is specified as percentage of the upper file size limit. 0 equals no lower limit, 1 would require the output to be exactly the upper file size limit. Values up to 0.95 are usually no problem. Anything above will lead to a lot more encoding attempts for minimal gain. Default: 0.75
`-i, --iterations <...>` | Limit the maximum amount of attempts per bitrate mode.  
