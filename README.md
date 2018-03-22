# RestrictedWebm
A simple shell script to create webms within a certain file size limit (mainly targeted at 4chan). The main focus lies on forcing the file size within the specified limit while still achieving the maximum possible quality.

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
	-s file_size_limit: Specifies the file size limit in MB. Default value is 4."
		4chan limits:
			/gif/ and /wsg/: 4MB - audio allowed - max. 300 seconds
			all other boards: 3MB - no audio allowed - max. 120 seconds
		8chan limits:
			all boards: 8MB - audio allowed
```

**Requirements:**  
ffmpeg  
ffprobe
