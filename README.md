# Restricted-Webm
A shell script to create webms within a certain file size limit (mainly targeted at 4chan).

The main goal is to produce webms that fit within a specified size limit, while producing the maximum possible quality and requiring minimum user input. If you want fast encoding speed, then this script isn't for you.  

**How it works:**  

1. Calculates video bitrate based on the file size limit, (trimmed) input video length and audio bitrate (also based on size limit/length).  
2. Downscales the video to ensure a minimum bits per pixel value (>= 0.04 for normal, >=0.075 for HQ mode) is reached. Stops at 360p (240p with HQ mode), even if bpp value is still too low. Automatic downscaling is disabled if the scale filter is used manually.  
3. Reduces the framerate if the bpp value is still below its threshold at the minimum resolution. Only affects input files with a framerate above 24fps when automatic downscaling is active.
4. Encodes a webm with variable bitrate mode and a minimum crf value. Uses 2-pass encoding if bits per pixel value is high enough (>= 0.075).  
5. Adjusts bitrate if the produced webm is larger than the specified limit or smaller than a certain percentage of the limit (default 75%).
6. Loops through different video encoding settings (variable bitrate without minimum crf -> constant bitrate -> constant bitrate and allows ffmpeg to drop frames) trying both the first calculated and adjusted bitrate.  
7. (Optional, depending on the produced webms) Creates a list of files (too_large.txt and too_small_for_undershoot.txt) that cannot be fit into the file size / undershoot limit, even after going through all available settings

```
Usage: convert.sh [-h] [-t] [-a] [-q] [-n] [-s file_size_limit] [-u undershoot_limit] [-f filters]
	-h: Show Help
	-t: Enable trim mode. Lets you specify which part of the input video(s) to encode
	-a: Enable audio encoding. Bitrate gets chosen automatically.
	-q: Enable HQ (high quality) mode. The script tries to raise the bpp value high enough to use 2-pass encoding. Audio bitrate fixed at 96kbps. Doesn't work if you manually use the scale filter.
	-n: Use the newer codecs VP9/Opus instead of VP8/Vorbis. Will lead to even longer encoding times, but offers a better quality (especially at low bitrates). Also note that 4chan doesn't support VP9/Opus webms.
	-s file_size_limit: Specify the file size limit in MB. Default value is 3.
		4chan limits:
			/gif/ and /wsg/: 4MB - audio allowed - max. 300 seconds
			all other boards: 3MB - no audio allowed - max. 120 seconds
		8chan limits:
			all boards: 8MB - audio allowed
	-u undershoot_limit: Define what percentage of the file size limit must be utilized. Default value: 0.75 (75%). Very high values may lead to worse results (since the script has to fall back on its last video encoding setting)
	-f filters: Add filters that you want to apply (with settings). Be careful to type them as you would normally with ffmpeg. Refer to ffmpeg's documentation for further information

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
├── to_convert/
      │ 
      │ video01
      │ video02
      │ video03
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
- [ ] Set filters for individual videos  

Quality adjustments:  
- [x] Calculate bitrate based on video length  
- [x] Automatic downscaling if quality would be too low otherwise (disabled when using scale manually)
- [x] Use 2-pass encoding automatically  
- [x] Loops through bitrate settings to fit the file size into the specified limit  
- [x] Adjust bitrate if the webm over-/undershoots the specified limit
- [x] Reduce framerate if quality is still to low after downscaling
- [x] HQ (high quality) mode (higher bpp threshold during downscaling)

Audio:  
- [x] Encode with audio (default: off)  
- [x] Adjust audio bitrate automatically (range: 48-128 kbps)
- [ ] Audio showcase mode (static image as video stream with high quality audio encoding)
