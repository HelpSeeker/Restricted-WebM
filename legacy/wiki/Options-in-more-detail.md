## Trim mode:
Lets you define which part of the input video to use. Input is required for each individual file, so if you want to convert a folder full of videos in one go, trim them beforehand. The start and end time must be specified in seconds (also works with fractions of a second). Start defaults to 0 seconds and end to the complete length of the video, if the input line is left empty.

## Audio mode:
Adds an audio stream to the output webm. The audio bitrate gets chosen automatically based on video length and file size limit.
* Standard mode: 48 - 192 kbps
* HQ mode: 96 - 192 kbps
* Audio showcase mode: 96 - 192 kbps (also higher bitrates get chosen sooner)  

The script will also attempt to copy the input audio stream, if
* it has the same codec (Vorbis or Opus, based on the -n flag).  
* the audio bitrate of the input is less or equal the one chosen by the script.  
* the trim mode isn't being used.  

Audio mode is off by default, but gets used automatically during the audio showcase mode. So there's no need for the -a flag, if you already have to -c flag set.

## HQ (high quality) mode:
This mode does three things to ensure a higher quality output.
* Further downscaling compared to normal mode
* 2-pass encoding
* Minimum audio bitrate of 96kbps 

It should be mentioned, that HQ mode (despite its name) doesn't always produce superior results compared to the normal mode. Mainly if the video bitrate is less than 200Kbps. The reason for that is VP8's 2-pass encoding.

VP8's 2-pass encoding delivers better results at high bitrates, but at the lower end of the spectrum it becomes a wildcard. Consistency is the keyword. Single pass tends to produce a much more consistent visual quality throughout the whole video. 2-pass on the contrary will make some frames look much better and others a lot worse. This shift of quality between scenes is jarring and will make the video look worse as a result. 

VP9 doesn't suffer the same problem and should always be used in combination with HQ mode.

**To summarize:** In general HQ mode will produce better looking webms with a smaller resolution. If the video bitrate is less than 200Kbps and you use VP8, it's usually better to stick with single pass or do both and compare the results.

## Newer codecs:
VP9/Opus are the successors of VP8/Vorbis and produce better results, especially at low bitrates. If a website allows webms with those codecs and you don't mind (much) longer encoding times, then go for them.  

Please note, that VP9 should only be used in combination with HQ mode. Single pass VP9 is in my opinion broken and has the potential to produce worse results than VP8.
  
## Fast encoding mode:  

See the [fast encoding mode wiki page](https://github.com/HelpSeeker/Restricted-Webm/wiki/Fast-encoding-mode).

## File size limit:
Not much to say here. While I had 4chan's limits in mind while writing this script, it works with any file size limit.

## Audio showcase mode:
Produces webm files with a frame rate of 1fps and with a static image as video stream. This leads to an incredible small video stream size, so that we can put more emphasis on the audio bitrate (ranges from 96kbps to 192kbps in this mode). The three flavours of this mode define how to locate the necessary input images.
* auto: The script assumes that there is a picture (with matching filename) for every input file in to_convert, located in showcase_pictures. The extension doesn't matter. You can use any image that your version of ffmpeg is able to handle. This is the best option if you want to convert many files in one go.
* manual: The script asks you for the location of each input picture. This doesn't require attention when it comes to additional folder structure, but prevents continuous encoding.
* video: Instead of looping an input picture, the script applies the usual showcase settings to the input videos in to_convert. Use this if you already have a video with a static image as video stream (e.g. from YouTube). Any other video content will become a slide show and is likely to exceed the specified file size limit.

## Filters:
Here you can enter your usual ffmpeg filters. This string will be used directly in the ffmpeg command, so it'll throw an error if you make any mistakes in it. Note that using the scale filter will disable automatic downscaling, so if you want to force the input resolution or have a min. resolution higher than 180p, use the scale filter manually.

Normally it doesn't matter in which sequence the individual filters are lined up, but that changes if:

- audio and video filters will be applied at the same time  

AND
  
- automatic downscaling shall be used  

In such a case **audio filters must come before video filters**. For example:

``` -f "[0:a]afade=t=out:st=60:d=5;[0:v]fade=t=out:st=60:d=5" ```

These filters will fade out the video and audio after 60 seconds, over the course of 5 seconds. It's also important to use quotes, as audio and video filters need to be separated by ; . 

## Undershoot limit:
The initial video bitrate calculation is no exact science and the final output size heavily depends on what footage the video is showing. The undershoot limit prevents the script from stopping / going on to the next file, when it doesn't utilize a certain percentage of the given file size limit (default 75%). Can range from 0 (completely disabled) to 1 (has to be exactly the file size limit). Personally I use 0.9 most of the time, which works fine. I wouldn't go higher than 0.95 though, as it only leads to a lot more encoding attempts for a minimal gain.

## Iterations:
The script cycles through 3 bitrate modes and during each bitrate mode it adjusts the bitrate several times. With the -i flag you can specify how many encoding attempts there will be for each bitrate mode (default: 3). Additionally the script will make i*2 attempts (so by default 6) once it got a webm within the file size limit, but not above the undershoot limit.

## Height threshold:

To prevent those famous "webms for ants" there's a minimum height threshold (by default it's 180 pixels). This threshold provides a limit to how much the script is able to downscale the output webm. If the input video height is less than the threshold, then the output will have the input's height.
This option overrides the default threshold and provides an easy way to define a minimum height for the output webm.

## Bpp threshold:

The bpp (bits per pixel) value is a quality control factor and mainly used to determine how much to downscale the output. Basically: Higher bpp threshold -> smaller output resolution -> higher perceived quality. By default the normal mode uses a bpp threshold of 0.04, while HQ and audio showcase mode aim at 0.075.  
Setting a custom bpp threshold lets you further improve the quality of your webm at the cost of resolution. Note that values between 0.1 and 0.2 should already provide very high quality output.

## HQ min. audio bitrate:

HQ mode is supposed to produce higher quality webms. This holds true for both video and audio. During HQ mode there's higher minimum audio bitrate. By default it's 96Kbps, which is a decent bitrate for Vorbis (comparable to MP3@128Kbps; see [Results of the public multiformat listening test - July 2014](http://listening-test.coresv.net/results.htm)).   
This minimum audio bitrate can become troublesome for very long webms with a relatively small file size limit (e.g. 4MB for a 4 minute long video) or if you don't want to waste the bitrate on human speech. With this option you can reduce the minimum audio bitrate (or increase it for whatever reason) for HQ mode. Setting it to anything between 0 and 48 will produce the same results audio-wise as the normal mode.