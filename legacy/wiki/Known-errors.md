This is a list of errors that I know of / expect, but trust the user to avoid. Some of them can also be safely ignored.  

## Audio filters and stream copying:

The script will try to copy the input audio stream if three requirements are met:
* Has the same codec (Vorbis or Opus, based on the -n flag)
* The audio bitrate is less or equal the one being chosen by the script
* Trim mode is inactive

If you want to apply audio filters via the -f flag, while the script tries to copy the input audio stream, then ffmpeg will throw an error (as you can't apply filters without encoding). To avoid this error use the trim mode for such files and simply hit enter, when asked for further input.

## Only audio filters:

Currently you can't pass only audio filters with this script. For example  

`-f volume=0.5`  

will throw an error, because of the automatic downscaling. The final filter string would look like this  

`-filter_complex volume=0.5,scale=-2:480`  

and goes against ffmpeg's filter syntax. Currently you can solve this by scaling manually  

`-f "[0:a]volume=0.5;[0:v]scale=-2:480"`  

or applying an arbitrary video filter  

`-f "[0:a]volume=0.5;[0:v]crop=iw:ih"`  

## VP9 and -tune ssim:

The -tune ssim option leads to better results while using VP8. VP9 doesn't offer this option (despite ffmpeg's internal documentation saying the opposite), so you'll see an error message when using VP9 (*Failed to set VP8E_SET_TUNING codec control: Invalid parameter. Additional information: Option --tune=ssim is not currently supported in VP9.*). This message however can be safely ignored, as ffmpeg ignores the -tune option and continues as usual.

## Pictures with transparency:

VP8 (and perhaps VP9, haven't tested it yet) is unable to handle input images with transparency (e.g. RGBA png files). It seems like there is a bug that prevents those pictures to work with the alternate reference frame. Since I can't think of a way to detect those pictures with ffprobe and the script uses the alternate reference frame for all 2-pass encodes, I'll leave it to the user to make sure, that no input picture has an alpha channel.

**Gifs are the exception for this problem.** The script gives them their own ffmpeg commands.

## Wrong color matrix:

When using input videos with a BT.709 color matrix, converting them to VP8 or SD VP9 webms will lead to the colors being slightly off. The reason is that the encoder switches to the BT.601 color matrix. For VP8 that's always the case as it doesn't support any other color matrix. VP9 uses BT.709 for HD, BT.601 for SD footage (that's pretty much the norm nowadays). I'm currently working on detecting those videos automatically with ffprobe. Until then apply the filter 
```colormatrix=bt709:bt601```
, but be certain that your input really has the BT.709 color matrix. Using this filter for a BT.601 input, will also lead to wrong colors.