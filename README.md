# Restricted-Webm
A shell script to create webms within a certain file size limit (mainly targeted at 4chan).

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
│     │ file03.tiff
│     │ ...
│
├── to_convert/
      │ 
      │ file01
      │ file02
      │ file03
      │ ...

```

**Functions (existing and planned ones):**

General:  
- [x] Convert all videos from the to_convert folder into webms  
- [x] Specify which file size limit to adhere to (default: 3MB)
- [x] Specify which percentage of the file size limit must be utilized
- [x] Option to use VP9/Opus instead of VP8/Vorbis  
- [x] Trim each video individually (default: off)  
- [x] Apply filters to all videos  
- [x] Use each video's file name for the title metadata  
- [x] List input files that cannot be forced into the specified size / undershoot limit
- [ ] Accept gif input and loop it to an audio file

Quality adjustments:  
- [x] Calculate bitrate based on video length  
- [x] Automatic downscaling if quality would be too low otherwise (disabled when using scale manually)
- [x] Use 2-pass encoding automatically  
- [x] Loop through bitrate settings to fit the file size into the specified limit  
- [x] Adjust bitrate if the webm over-/undershoots the specified limit  
- [x] Define how many encoding attempts are made for each bitrate mode  
- [x] Reduce frame rate if quality is still to low after downscaling
- [x] HQ (high quality) mode (higher bpp threshold during downscaling)

Audio:  
- [x] Encode with audio (default: off)  
- [x] Adjust audio bitrate automatically (range: 48-128 kbps)
- [x] Audio showcase mode (static image as video stream with high quality audio encoding)
- [ ] Copy the original audio stream if the codec is compatible and has the same or a smaller bitrate