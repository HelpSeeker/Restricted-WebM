## Overview

By default this script takes a long time to produce webms. The main reason is the usage of -threads 1 in the ffmpeg commands. While very slow, as it only uses a fraction of your CPU's capabilities, it produces a very predictable output filesize (-/+1% when using the same settings for consecutive tries). Some functionality of the script depends on this to skip unnecessary encoding attempts.
Additionally multi-threading for VP8 and VP9 is rather weird (some might even call it stupid). The max. number of threads utilized depends on the video's width. Max. threads = width / 500 (always rounded down). So if you want to encode e.g. a 1920x1080 video you can use 3 threads maximum, even if you specify more via the -threads option.

To provide a way to fully utilize your CPU (therefore avoiding this weird restriction) and still produce a predictable file size, the fast encoding mode uses a different approach. The video gets split into n parts (n being specified by the user). These parts then get encoded at the same time. Given enough parts this will fully utilize your CPU. Afterwards the individual clips will be combined into the final video (without any additional losses, as you can copy those streams into the same container).

**Note that this only applies to the video footage.** The audio stream gets encoded normally, as the audio can't be trimmed with the necessary precision. Audible cuts would be the result of converting the audio in separate parts.

## How to choose n?
n <= 1 will be silently ignored while the script reverts to its normal behaviour. n > 1 will result in an overall faster encoding speed. Ideally n should be the number of threads your CPU has. This way you will achieve 100% CPU usage. You can set n even higher, but this will have barely any additional effect on the encoding speed.

## Fast encoding and audio showcase mode

These two don't work together. The 1fps frame rate makes it too inaccurate to split the video into individual parts and the keyframe interval adjustment (currently the only way to adjust the file size during audio showcase mode) isn't applicable.  
**Therefore the audio showcase mode automatically deactivates the fast encoding mode.**

## Drawbacks

Right now there are several drawbacks to the fast encoding mode, which is why it's not the default behaviour.

### File size difference compared to normal mode

The resulting file size will differ from one continuous encoding attempt. In my experience this is heavily influenced by the used bitrate mode and whether you use VP8 or VP9.
For VP8 the constrained quality mode seems to produce the most consistent results (differences range between <0.1 to 0.5 MiB). Classic VBR leads to an explosion in file size for very high bitrates (effectively doubling the file size at 10Mbps). While not being used in this script, constant quality mode has the opposite effect and becomes unpredictable for high crf values (i.e. low bitrates), albeit not as bad as with VBR.

I didn't perform many tests with VP9 yet, but it seems even less predictable than VP8.

### Decreased output quality for difficult footage

The fast encoding mode shouldn't be used for difficult encodes. The encoder will likely produce worse results as the bitrate allocation is done separately for each part of the video, with all parts having the same importance.  
For example the encoder might decide to use less bitrate on the last 30 seconds of a video, as the first 30 seconds depict more movement and therefore need a higher bitrate to achieve the same visual quality. When split into individual parts, the encoder doesn't know about the last 30 seconds (which are done in a different part) and can't optimize the bitrate allocation for the entire video.  

2-pass VP9 is the only option that produces worse but acceptable results in such a situation.

### High RAM usage

Running a great number of ffmpeg instances parallel consumes quite a bit of RAM. A combination of powerful CPU (e.g. 16 threads) and <=8GB RAM can lead to problems. If you experience problems under Linux, check your [swappiness](https://en.wikipedia.org/wiki/Swappiness) and if necessary lower n.

### Time-based filters

This problem is fairly obvious. Splitting the original video into separate parts prevent ffmpeg from applying time-based filters correctly. Telling it to fade to black after 90 seconds has no effect, if each individual clip is only 50 seconds long.
The exception to this shortcoming are audio filters. Due to the audio getting encoded in one go, you can still apply audio time-based filters like you always would. However, this may take a long time (an explanation can be found further down). Therefore the script prompts the user once at the very beginning whether or not it should assume (any) audio filters, if

* the fast encoding mode is active
* the user set custom filters
* audio gets encoded

```
~~~~~~~~~~~~~~~~~~
ATTENTION!
Please specify if your filter string contains audio filters.
Choosing 1 (Yes) will lead to audio filters getting applied. This may take some time for long videos.
Choosing 2 (No) will lead to no audio filters getting applied. This will speed up the conversion.
~~~~~~~~~~~~~~~~~~
1) Yes
2) No
Assume audio filters? 
```

**Why may it take long?** Because of two factors playing together.  
1. The user defined filters are one long string. The script doesn't know which filters get applied. They could be video or audio filters.  
2. ffmpeg doesn't suppress the video stream, if video filters get applied.  

Knowing these two facts, there can be 2 possible outcomes when trying to only encode the audio:
1. The user told the script that there will be no audio filters -> no filter string gets applied -> fast audio-only conversion
2. The user told the script that there will be audio filters -> filter string gets applied -> video stream can't be suppressed -> ffmpeg falls back on a default video encoder (in this case libtheora) -> slow video/audio conversion

The second outcome can be problematic. It might not matter for a 30 second clip, but it does for a 30 minute video.