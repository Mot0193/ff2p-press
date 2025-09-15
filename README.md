# ff2p-press
A Powershell script for Windows that uses FFMPEG 2-pass encoding to compress videos to a given size.

This script compresses videos with various video codecs and settings, using ffmpeg with double-pass encoding.
The default options (when no extra arguments are given other than the input file and file size) are the video codec libx265 with the medium preset, and the audio codec libopus at 128kbps bitrate or the video's audio bitrate if its lower than the set bitrate.
Videos will get output to Desktop with the names starting with "compressed_" and ending with the codec used (e.g "_libx265") and preset used (e.g _medium). 

## Quick usage parameters:
`-i <path_to_file>` video file input

`-s <desired_file_size_in_MiB>` set the target size of the file in mebibytes

`-h or -w <desired_resolution>` rescale the output video. EITHER of these are optional, not setting both will not rescale the video, not setting ONE will make the other side automatically scale to keep the aspect ratio of the video (e.g if your input video is 2650 wide x 1440 tall, you can just use -h 1080p to automatically make the resolution 1920x1080, or vice versa). Setting BOTH to values that wont match the original aspect ratio will result in "streched" or "squished" videos (e.g nothing is stopping you from doing -h 500 -w 500 for a 16:9 video), so just set either the width or the height (probably height). Scaling down a video is a good way of increasing the bitrate per frame, especially when the video isnt really meant to be viewed at its original resolution (for example sharing a 1400p video might be wasteful if most people are going to view it on a 720p/1080p display). 

Thats it! For advanced codec settings continue reading and consult the example usages below.

# Codec options/usage tips

## libx265 (hevc/H265)
This is the default. H265 is a good codec overall, with quality slightly worse than AV1. Presets over medium give diminishing returns for videos that require less compression, though it might make a bigger difference on larger videos that need to get compressed more. But at some point using libaom-av1 with it's fastest preset might be better than a very slow libx265 preset.

libx265 supports these presets: https://x265.readthedocs.io/en/master/presets.html (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo)

Default preset is "medium"

## hevc_nvenc (hevc/H265 hardware accelerated for Nvidia GPUs)
In general all hardware accelerated codecs provide worse quality than their software (cpu) versions (in this case compared to libx265). But they are A LOT faster even at the highest quality/preset settings, but even at their highest presets they cant usually beat a good softare encoder.
For this reason i wouldnt go below the max preset for nvenc, and some options are complately hardcoded with the use of a high quality preset in mind (for example enabling double pass with the full resolution. Normally lower presets might disable this)

hevc_nvenc supports some weird presents, but the main ones are: p1, p2, p3, ... p7. higher values provide higher quality. To see all presets run "ffmpeg -h encoder=hevc_nvenc"

Default preset is "p7"

CBR (Constant bitrate) is also enabled for this codec, as i found better results with more stable file sizes.

## libx264 (avc/H264)
H264 is the least efficient when it comes for quality/file size out of these options, but it has the benifit of encoding decently fast (though still slower than hevc_nvenc), and its the most compatible with devices and services, which means its the best option if you want to guarantee that the video can be played with no issues, for example if you want to share the video. Though in my opinion this should start to get replaced by the better h265, since even the "veryslow" preset on h264 is way worse than the "veryfast" preset for h265. H264 also has a distinct pixelated look thats very noticable and recognizable at lower bitrates.

libx264 supports the same presets as libx265: https://trac.ffmpeg.org/wiki/Encode/H.264#a2.Chooseapresetandtune (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo)

Default preset is "medium"

## libaom-av1 (av1)
This is av1 software encoding. VERY slow, but considered the best. Because of its mind-numbing speed, i consider going under the preset 8 to be brave (this is actually the "cpu-used" argument, not really a "preset").
But, even at the fastest preset (8) with just one pass, it can achieve great results, even better and faster compared to libx265 at the slow preset. This is just from my very limited testing, though.

libaom-av1 supports these "cpu-used" values as "presets": https://ffmpeg.org/ffmpeg-codecs.html#libaom_002dav1 (0, 1, 2, ... 8), 0 being the slowest while 8 the fastest. For reference, the library defaults to 1.

Default preset is "8"

## Audio codecs: libopus (opus) / acc
The default is libopus, but if youre unsatisfied with how it sounds try ACC. From what i read opus does great at medium bitrates (64k, 128, 192k), but at very low bitrates you might want to try ACC. At high bitrates the difference between codecs is very minor, hence why the default codec is libopus.

# Codec compatibility notice

While newer codecs might offer better compression/file size efficiency, they can lack compatibility with devices and services. For example AV1 is known for being hard to playback on some devices (especially mobile devices, and even decently-modern computers with no hardware AV1 decoding can struggle), so depending of what you want to do with the video different codecs are best for different use-cases. Heres a rough list of codecs from the most compatible to least compatible:

Video Codecs:
- H264 (most compatible)
- H265
- AV1

Audio Codecs:
- ACC (most compatible)
- Opus

# Examples of parameter usage
```
-i "C:\Users\mot\Desktop\Overwatch_28.08.2025_21-18-54.mp4" -s 30   (compresses input video to the selected size with the default codecs and presets)
-s 50 -i "C:\Users\mot\Desktop\drive.mp4" -cv libaom-av1    (change the default video codec)
-i "C:\Users\mot\Desktop\Overwatch_28.08.2025_21-18-54.mp4" -s 10 -cv hevc_nvenc
-i "C:\Users\mot\Desktop\drive.mp4" -s 30 -cvpreset veryslow -cv libx264    (change the default video codec and use a different preset compatible with the codec)
-i  "C:\Users\mot\Desktop\drive.mp4" -s 50 -h 1080 -cv hevc_nvenc   (change codec, rescale the video to 1080p. Here since width isnt set it will get automatically set to match the aspect ratio of the video)
```

See the "param" block at the top of the ps1 script for all the parameters you can set. Some have aliases (for example you can use "-video" _or_ just "-i")