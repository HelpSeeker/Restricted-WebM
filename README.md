# RestrictedWebm
A simple shell script to create webms within a certain file size limit (mainly targeted at 4chan).

The main goal is to produce webms that fit within a specified size limit, while producing the maximum possible quality and requiring minimum user input. If you want fast encoding speed, then this script isn't for you.  

**How it works:**  

1. Calculates video bitrate based on the (trimmed) input video length and whether or not audio mode is active.  
2. Downscales the video to ensure a minimum bits per pixel value (>= 0.04) is reached. Stops at 360p, even if bpp < 0.04.
3. Encodes a webm with variable bitrate mode and a minimum crf value. Uses 2-pass encoding if bits per pixel value is high enough (>= 0.075).  
4. IF the file size of the new webm is larger than the specified limit, it tries again with different settings (variable bitrate without minimum crf -> constant bitrate -> constant bitrate and allows ffmpeg to drop frames).  

```
Usage: convert.sh [-h] [-t] [-a] [-s file_size_limit]
	-h: Show help
	-t: Enable trim mode. Lets you specify which part of the input video(s) to encode
	-a: Enables audio encoding
	-s file_size_limit: Specifies the file size limit in MB. Default value is 3.
		4chan limits:
			/gif/ and /wsg/: 4MB - audio allowed - max. 300 seconds
			all other boards: 3MB - no audio allowed - max. 120 seconds
		8chan limits:
			all boards: 8MB - audio allowed
	-f filters: Add filters that you want to apply (with settings). DO NOT USE SCALING AS IT'S APPLIED AUTOMATICALLY RIGHT NOW! Also be careful to type them as you would normally with ffmpeg. Refer to ffmpeg's documentation for further information.

```

**Requirements:**  
ffmpeg  
ffprobe
```
Folder structure:

RestrictedWebm/
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
- [x] Trim each video individually (default: off)  
- [x] Apply filters to all videos  
- [x] Use each video's file name for the title metadata  
- [ ] Set filters for individual videos  
- [ ] Option to switch from VP8/Vorbis to VP9/Opus  

Quality adjustments:  
- [x] Calculate bitrate based on video length  
- [x] Automatic downscaling if quality would be too low otherwise  
- [x] Use 2-pass encoding automatically  
- [x] Loops through bitrate settings until file size fits into the specified limit  
- [ ] Offer HighQuality mode, where low quality output is prevented by demanding additional input from the user

Audio:  
- [x] Encode with audio (default: off)  
- [ ] Adjust audio bitrate based on the video length  
