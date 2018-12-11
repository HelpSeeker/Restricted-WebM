You can easily change the default behaviour of this script to cater to your needs.  
If you open the script with a text editor, you'll see the following section at the beginning.

```
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Default settings
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# These values represent the script's default behaviour
trim_mode=false
audio_mode=false
hq_mode=false
showcase=false
new_codecs=false
parallel_convert=false
parallel_afilter=false
ask_parallel_afilter=true

# These values change the default limits of the script
file_size=3
parallel_process=1
undershoot_limit=0.75
adjust_iterations=3
height_threshold=180
bpp_threshold=0.04
# hq_bpp_threshold is used for both HQ and audio showcase mode
hq_bpp_threshold=0.075
# 96kbps produces decent results for Vorbis, comparable to mp3 at 128kbps
# http://listening-test.coresv.net/results.htm
hq_min_audio=96
```

## Modes

To use a special mode (e.g. HQ mode) or VP9/Opus by default, set the corresponding variable from this list to true.
```
trim_mode=false
audio_mode=false
hq_mode=false
new_codecs=false
```
Note that showcase and parallel_convert aren't on this list.  

If you want to use the audio showcase mode by default, you also need to add a default showcase_mode (auto, manual or video).  
For example:
```
showcase=true
showcase_mode="auto"
```
To stop using the audio showcase mode by default, be sure to also remove the default showcase_mode. Otherwise it will break the script.


If you want to use the fast encoding mode by default, you also need to adjust parallel_process further down. Ideally use the number of cores your CPU has.
```
parallel_convert=true
[...]
parallel_process=6
```
Only if both variables have a custom value will the fast encoding mode be used. Otherwise the script will revert to its normal behaviour.

## Audio filter prompt

The audio filter prompt only appears under specific circumstances (see [the fast encoding mode wiki page](https://github.com/HelpSeeker/Restricted-Webm/wiki/Fast-encoding-mode#time-based-filters) for more infos).  
If this prompt annoys you, take a look at these two variables
```
parallel_afilter=false
ask_parallel_afilter=true
```
**parallel_afilter** sets the default behaviour of the script during fast encoding mode.
  
_true_ ... The script will apply audio filters, if there are any present.  
_false_ ... The script won't apply audio filters.  

**ask_parallel_afilter** controls whether or not the prompt appears.  

_true_ ... The prompt will appear. parallel_afilter's default doesn't matter as it gets overwritten.  
_false_ ... No prompt will appear. The script will fall back on parallel_afilter's default value.  

## Limits/thresholds

The following list holds all limits or thresholds used throughout the script. If you haven't done so, take a look at the [Options in more detail](https://github.com/HelpSeeker/Restricted-Webm/wiki/Options-in-more-detail) page. Afterwards all these variables should be self explanatory.
```
file_size=3
parallel_process=1
undershoot_limit=0.75
adjust_iterations=3
height_threshold=180
bpp_threshold=0.04
# hq_bpp_threshold is used for both HQ and audio showcase mode
hq_bpp_threshold=0.075
# 96kbps produces decent results for Vorbis, comparable to mp3 at 128kbps
# http://listening-test.coresv.net/results.htm
hq_min_audio=96
```