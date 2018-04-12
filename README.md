# Restricted-Webm
A bash script to create webms within a certain file size limit (mainly targeted at 4chan).

The main goal is to produce webms that fit within a specified size limit, while producing the maximum possible quality and requiring minimum user input. If you want fast encoding speed, then this script isn't for you.  

```
Usage: convert.sh [-h] [-t] [-a] [-q] [-c { auto | manual | video }] [-n] [-s file_size_limit] [-u undershoot_limit] [-i iterations] [-f filters]
	-h: Show Help. For more detailed infos: Read help.txt.
	-t: Enable trim mode.
	-a: Enable audio encoding.
	-q: Enable HQ (high quality) mode. Doesn't work if you manually use the scale filter.
	-c { auto | manual | video }: Enable audio showcase mode. Supersedes -a, -u and -q flag.
		auto: Use images with matching filename in showcase_pictures.
		manual: Enter path to picture manually for each video.
		video: Apply settings to videos in to_convert.
	-n: Use the newer codecs VP9/Opus instead of VP8/Vorbis.
	-s file_size_limit: Specify the file size limit in MB. Default value is 3.
		4chan limits:
			/gif/ and /wsg/: 4MB - audio allowed - max. 300 seconds
			all other boards: 3MB - no audio allowed - max. 120 seconds
		8chan limits:
			all boards: 8MB - audio allowed
	-u undershoot_limit: Define what percentage of the file size limit must be utilized. Default value: 0.75 (75%).
	-i iterations: Define how many encoding attempts there will be for each bitrate mode. Default value is 3.
	-f filters: Add custom ffmpeg filters. Refer to ffmpeg's documentation for further information

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
