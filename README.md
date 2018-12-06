# Restricted-Webm
A bash script to create webms within a certain file size limit (mainly targeted at 4chan).

The goal is to produce webms that fit within a specified size limit, while producing the maximum possible quality and requiring minimum user input. If you want fast encoding speed, then this script isn't for you.  

```
Usage: convert.sh [-h] [-t] [-a] [-q] [-n] [-x threads] [-s file_size_limit] [-c { auto | manual | video }] [-f filters] 
		    [-u undershoot_limit] [-i iterations] [-g height_threshold] [-b bpp_threshold] [-m HQ_min_audio_bitrate]
	
Main options:

	-h: Show Help.
	-t: Enable trim mode.
	-a: Enable audio encoding.
	-q: Enable HQ (high quality) mode. Higher bpp threshold, higher min. audio bitrate and 2-pass encoding.
	-n: Use the newer codecs VP9/Opus instead of VP8/Vorbis.
	-x cores: Fast encoding mode (experimental). For 100% CPU usage specify your CPU's number of threads.
	-s file_size_limit: Specify the file size limit in MB. Default value is 3.
	    4chan limits:
	        /gif/ and /wsg/: 4MB - audio allowed - max. 300 seconds
	        all other boards: 3MB - no audio allowed - max. 120 seconds
	    8chan limits:
	        all boards: 8MB - audio allowed
	-c { auto | manual | video }: Enable audio showcase mode. Supersedes -a, -u and -q flag.
	    auto: Use images with matching filename in showcase_pictures
	    manual: Enter path to picture manually for each video
	    video: Apply settings to videos in to_convert
	-f filters: Add custom ffmpeg filters. Refer to ffmpeg's documentation for further information.
	
Advanced options:
(default values can be changed permanently in the beginning of the script)

	-u undershoot_limit: Define what percentage of the file size limit must be utilized. Default value: 0.75 (75%).
	-i iterations: Define how many encoding attempts there will be for each bitrate mode. Default value is 3.
	-g height_threshold: Set the minimum pixel height the output webm should have. Default value: 180.
	-b bpp_threshold: Set the minimum bpp value the output webm should have (higher values -> higher quality, more downscaling). 
			    Default value: 0.04 for normal, 0.075 for HQ/audio showcase mode.
	-m HQ_min_audio_bitrate: Set the minimum audio bitrate for HQ mode. Default value: 96.
```

**Requirements:**  
ffmpeg (with libvpx, libvpx-vp9, libvorbis and libopus enabled)  
ffprobe  
```
Folder structure:

Restricted-Webm/
│
├── convert.sh
│
├── showcase_pictures/ (only when using the audio showcase mode with the auto option)
│     │ 
│     │ (the following files are pictures with the same name as the files in to_convert/; extension doesn't matter)
│     │ file01.jpg
│     │ file02.png
│     │ file03.gif
│     │ ...
│
├── to_convert/
      │ 
      │ file01
      │ file02
      │ file03
      │ ...

```


For further information consult the [wiki](https://github.com/HelpSeeker/Restricted-Webm/wiki)!

## Rewrite

I'm currently working on rewriting this script from scratch. 

convert.sh was the first extensive script I've ever written and it's far from being perfect. A patchwork job that got bigger and bigger over time.  
It is lacking in several areas

* no subtitle handling
* no multiple audio stream handling
* expects stereo audio
* several problems regarding filters
* relatively messy code

I've learned a lot since I first made this repo (be it ffmpeg usage, VP8/VP9/Vorbis/Opus details or Bash scripting) and think it's better to start over than to continue working on already ugly code.  
However there will be another change regarding the rewrite. I'm planning on migrating this script to Python. It certainly is possible to do in Bash, but Python will be easier in the long run and make it available to more people.

Current progress:

Input:
- [x] Accept several input files
- [x] No required directory structure
- [x] Option to trim each input individually
- [x] Option to trim all input with the same start and/or end time

Video:
- [x] Choose bitrate based on file size limit, length, audio bitrate and prior attempts
- [x] Loop through VBR with qmax, VBR without qmax and CBR
- [x] Adjust bitrate i times for each bitrate mode
- [x] Option to change amount of iterations per bitrate mode
- [x] Adjust bitrate i * 2 times to reach undershoot limit
- [ ] Avoid unnecessary encoding attempts while trying to reach undershoot limit
- [ ] Automatic frame rate dropping
- [ ] Custom target bpp value
- [ ] Support for transparency
- [ ] VP9 support (low priority)
- [ ] AV1 support (very low priority)

Audio:
- [x] Choose audio bitrate based on file size limit, length and channel count of all audio streams
- [x] Handle multiple audio streams
- [x] Handle different audio channel configurations
- [x] Option to force stereo audio
- [x] Options to force min/max audio channel bitrate
- [x] Stream copying (if viable)
- [x] Option to force/disable stream copying
- [x] Vorbis and Opus support
- [x] Vorbis as fallback codec, if Opus can't remap channel configuration
- [ ] Extend range of possible audio bitrates (down to narrowband 8Kbps)

Subtitiles:
- [x] Subtitle support
- [x] Option to use MKV container when image-based subtitles are used

Filters:
- [x] Options to pass custom filters
- [x] Option to disable filters during the first pass when using 2-pass encoding
- [x] New approach to user filters (filtered input gets piped to the actual WebM conversion commands)
- [x] Script now knows if audio and/or video filters are being used
- [x] Only audio filters are now possible
- [ ] Automatic downscaling
- [ ] Custom min/max downscaling
- [ ] Automatic colormatrix correction

Misc:
- [x] Custom target file size
- [x] Custom undershoot limit
- [x] Option to choose between single and 2-pass encoding
- [x] Error logs
- [x] Option to force 1 video/audio stream output (discards any other input audio streams)
- [ ] Makeshift multi-threading (low priority)
- [ ] Audio showcase mode (very low priority)
