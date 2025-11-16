# ff2p-press
A Powershell script for Windows that uses ffmpeg 2-pass encoding to compress videos to a given size.

By default the video codec gets set to libx265 at the medium preset, and the libopus audio codec at 128k bitrate or the input video's audio bitrate, whichevers lower.
Videos will get output to the same folder as the input video by default, with this naming scheme: `compressed_<targeted_size>mib_<original_video_name>_<codec_used>_<preset_used>`

## ffmpeg instalation
Make sure to install an ffmpeg package that contains all the codecs this script supports. For example if youre installing ffmpeg from [gyan.dev](https://www.gyan.dev/ffmpeg/builds/), you should install the "full" release:
```
winget install ffmpeg
```

## Quick usage parameters:
`-i <path_to_file>` Video file input

`-s <desired_file_size_in_MiB>` Set the target size of the file in mebibytes

`-o <folder_path>` Optionally set the output folder for the compressed video. Not setting this will set the output folder to the same as the input video

`-h or -w <desired_resolution>` Optionally rescale the output video. Scaling down a video is a good way of increasing the bitrate per frame, especially when the video isnt really meant to be viewed at its original resolution (for example sharing a 1440p video might be wasteful if most people are going to view it on a 720p/1080p display). EITHER of these are optional, not setting both wont rescale the video, not setting ONE will make the other side automatically scale to keep the aspect ratio of the video (e.g if your input video is 2650 wide x 1440 tall, you can just use -h 1080p to automatically make the resolution 1920x1080, or vice versa). Setting BOTH to values that wont match the original aspect ratio will result in videos with "streched" or "squished" pixels (e.g nothing is stopping you from doing -h 500 -w 500 for a 16:9 video), so just set either the width or the height (probably height).  

Thats it! For advanced codec settings continue reading and consult the example usages below.

## Examples of parameter usage
See the "param" block inside the ps1 script for all the parameters you can set. Some have aliases (for example you can use "-video" _or_ just "-i"). All of them have comments explaining what each parameter does.

```
-i "C:\Users\mot\Desktop\Overwatch_28.08.2025_21-18-54.mp4" -s 30    (compresses input video to the selected size with the default codecs and presets)
-i "C:\Users\mot\Desktop\drive.mp4" -s 50 -cv libaom-av1    (change the default video codec to libaom-av1)
-i "C:\Users\mot\Desktop\drive.mp4" -s 30 -cvpreset veryslow -cv libx264    (change the default video codec and use a different preset compatible with the codec)
-i  "C:\Users\mot\Desktop\drive.mp4" -s 50 -h 1080 -cv hevc_nvenc    (change codec, rescale the video to 1080p. Here since only the height is set, the width will automatically adjust to match the aspect ratio of the video)
-i "C:\Users\mot\Desktop\Test\NieR_Automata_2025.08.21_-_20.07.22.02.DVR.mp4" -s 25 -o "C:\Users\mot\Desktop"    (change the output directory)
-i "C:\Users\mot\Desktop\Overwatch_28.08.2025_21-18-54.mp4" -s 16.4 -fancyrename 0    (disable fancy rename. Files will just be named `compressed_<original_video_name>`)
-i "C:\Users\mot\Desktop\Desktop_2025.07.19_-_20.17.50.03.DVR.mp4" -s 10 -cv libsvtav1 -brlow 3   (change preset, lower the final target bitrate by 3%)
```

# Codec options/usage tips

## libx265 (hevc/H265)
This is the default. H265 is a good codec overall. Presets over medium give diminishing returns for videos that require less compression, though it might make a bigger difference on larger videos that need to get compressed more. But at some point using libaom-av1 with it's fastest preset might be better than a very slow libx265 preset.

libx265 supports these [presets](https://x265.readthedocs.io/en/master/presets.html): (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo)

Default preset is "medium"

## hevc_nvenc (hevc/H265 hardware accelerated for Nvidia GPUs)
In general all hardware accelerated codecs provide worse quality than their software (cpu) versions (in this case compared to libx265). But they are A LOT faster even at the highest quality/preset settings, though even at their highest presets they cant usually beat a good softare encoder.
For this reason i wouldnt go below the max preset for nvenc, and some options are complately hardcoded with the use of a high quality preset in mind (for example enabling double pass with the full resolution. Normally lower presets might disable this)

hevc_nvenc supports some weird presents, but the main ones are: p1, p2, p3, ... p7. higher values provide higher quality. To see all presets run "ffmpeg -h encoder=hevc_nvenc"

Default preset (for this script) is "p7"

CBR (Constant bitrate) is also enabled for this codec, as i found better results with more stable file sizes.

## libx264 (avc/H264)
H264 is the least efficient when it comes for quality/file size out of these options, but it has the benifit of encoding decently fast (though still slower than hevc_nvenc), and its the most compatible with devices and services, which means its the best option if you want to guarantee that the video can be played with no issues, for example if you want to share the video. Though in my opinion this should start to get replaced by the better h265, since even the "veryslow" preset on h264 is way worse than the "veryfast" preset for h265. H264 also has a distinct pixelated look thats very noticable and recognizable at lower bitrates.

libx264 supports the same [presets](https://trac.ffmpeg.org/wiki/Encode/H.264#a2.Chooseapresetandtune) as libx265: (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo)

Default preset is "medium"

## libaom-av1 (av1)
This is av1 software encoding. VERY slow, but considered the best. Because of its mind-numbing speed, i consider going under the preset 8 to be brave (this is actually the "cpu-used" argument, not really a "preset").
But even at the fastest preset (8) it can achieve great results, sometimes even better and faster compared to libx265 at the very slow preset. This is just from my very limited testing, though.

libaom-av1 supports these "[cpu-used](https://ffmpeg.org/ffmpeg-codecs.html#libaom_002dav1)" values as "presets": (0, 1, 2, ... 8), 0 being the slowest while 8 the fastest. For reference, the library defaults to 1.

Default preset (for this script) is "8"

Row multi-threading (-row-mt) is also enabled.

## libsvtav1 (av1)
Different flavour of av1 software encoding. This has a couple of differences compared to libaom-av1, such as being able to scale better across many cpu cores, and having a couple performance improvements at the cost of lower efficiency/quality. If youre unsatisfied with the speed of libaom-av1 try using this and test out different presets. From my testing the preset 7 is slightly faster than libx265's medium preset, but i personally still think libx265 looks better. I also noticed it tends to overshoot the target size, so you may want to use -brlow 3 for example to lower the target bitrate by 3% or something.

libsvtav1 supports these [presets](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Parameters.md#options): 0, 1, ... 13, 0 being the slowest and 13 the fastest. 

Default preset (for this script) is "7"

## Audio codecs: libopus (opus) / acc
The default is libopus with 128k bitrate (or the input video's, if its lower). If youre unsatisfied with how it sounds try ACC. From what i read opus does great at medium bitrates (64k, 128, 192k), but at very low bitrates you might want to try ACC. At high bitrates the difference between codecs is very minor.

# Codec compatibility notice

While newer codecs might offer better compression/file size efficiency, they can lack compatibility with devices and services. For example AV1 is known for being hard to playback on some devices (especially mobile devices, and even decently-modern computers can struggle), so depending of what you want to do with the video different codecs are best for different use-cases. In general, H265 and Opus should play fine on most, relatively modern devices. If youre sharing the video and people are complaining they cant play it, use H264 and ACC. AV1 is great, but id personally use it only for archival purposes.