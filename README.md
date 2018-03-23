# RestrictedWebm
A simple shell script to create webms within a certain file size limit (mainly targeted at 4chan).

The main goal is to produce webms that fit within a specified file limit, while producing the maximum possible quality and requiring minimum user input. If you want fast encoding speed, then this script isn't for you.

```
Usage: sh convert.sh [-h] [-t] [-a] [-p] [-m { variable | constant | low-variable }] [-s file_size_limit]
	-h: Show help
	-t: Enable trim mode. Lets you specify which part of the input video(s) to encode
	-a: Enables audio encoding
	-p: Enables VP8's two pass encoding. Only recommended for high bitrates (e.i. short webms)
	-m { variable | constant | low-variable }: Specifies which bitrate mode VP8 should use
		variable (default): Usually provides the best quality/size ratio. Works with target/minimum crf and bitrate value.
		constant: Easiest way to reach a certain file size. Specifies an average target bitrate.
		low-variable: Same as the "variable" mode, but doesn't apply a minimum crf value. Only use for long webms, if "variable" produces far too large files.
	-s file_size_limit: Specifies the file size limit in MB. Default value is 3.
		4chan limits:
			/gif/ and /wsg/: 4MB - audio allowed - max. 300 seconds
			all other boards: 3MB - no audio allowed - max. 120 seconds
		8chan limits:
			all boards: 8MB - audio allowed
	-f filters: Add filters that you want to apply (with settings). Be careful to type them as you would normally with ffmpeg. Refer to ffmpeg's documentation for further information.

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
- [ ] Set filters for individual videos
- [x] Use each video's file name for the title metadata  
- [ ] Option to switch from VP8/Vorbis to VP9/Opus  

Quality adjustments:  
- [x] Use 2-pass encoding (default: off)  
- [x] Choose which bitrate mode to use (default: VBR)  
- [x] Calculate bitrate based on video length  
- [ ] Loops through several settings (bitrate modes, skip_threshold, ...) until the file size fits in the specified limit  
- [ ] Automatic downscaling if quality would be too low otherwise  

Audio:  
- [x] Encode with audio (default: off)  
- [ ] Adjust audio bitrate based on the video length  
