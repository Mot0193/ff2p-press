# ff2p-press
A PowerShell script for Windows that uses ffmpeg 2-pass encoding to compress videos to a given size.

Supports several video encoders and advanced settings. By default, the video codec gets set to libx265 at the medium preset, and the libopus audio codec at 128k bitrate or the input video's audio bitrate, whichever is lower.
Videos will get output to the same folder as the input video by default, with this naming scheme: `compressed_<targeted_size>mib_<original_video_name>_<codec_used>_<preset_used>`

## ffmpeg installation
Make sure to install an ffmpeg package that contains all the codecs this script supports. For example SVT-AV1* is only in the "full" release of ffmpeg installed from [gyan.dev](https://www.gyan.dev/ffmpeg/builds/):
```
winget install ffmpeg
```
*Though if youre using SvtAv1EncApp ffmpeg might not need support for SVT-AV1 directly, read more about libsvtav1 2-pass encoding below.

## Quick usage parameters:
`-i <path_to_file>` Video file input

`-s <desired_file_size_in_MiB>` Set the target size of the file in mebibytes

`-o <folder_path>` Optionally set the output folder for the compressed video. Not setting this will set the output folder to the same as the input video

`-h or -w <desired_resolution>` Optionally rescale the video. You may only use -h (height) to automatically scale the width to match the aspect ratio or vice versa. For example, by using `-h 1080` on a 2560x1440 video, the output resolution will be 1920x1080.

That's it! For advanced codec settings continue reading and consult the example usages below.

## Examples of parameter usage
See the "param" block inside the ps1 script for all the parameters you can set. Some have aliases (for example, you can use "-video" _or_ just "-i"). All of them have comments explaining what each parameter does.

```
-i "C:\Users\mot\Desktop\Overwatch_28.08.2025_21-18-54.mp4" -s 30    (compresses input video to the selected size with the default codecs and presets)
-i "C:\Users\mot\Desktop\drive.mp4" -s 50 -cv libaom-av1    (change the default video codec to libaom-av1)
-i "C:\Users\mot\Desktop\drive.mp4" -s 30 -cvpreset veryslow -cv libx264    (change the default video codec and use a different preset compatible with the codec)
-i "C:\Users\mot\Desktop\drive.mp4" -s 50 -h 1080 -cv hevc_nvenc    (change codec, rescale the video to 1080p. Here, since only the height is set, the width will automatically adjust to match the aspect ratio of the video)
-i "C:\Users\mot\Desktop\Test\NieR_Automata_2025.08.21_-_20.07.22.02.DVR.mp4" -s 25 -o "C:\Users\mot\Desktop"    (change the output directory)
-i "C:\Users\mot\Desktop\Overwatch_28.08.2025_21-18-54.mp4" -s 16.4 -fancyrename 0    (disable fancy rename. Files will just be named `compressed_<original_video_name>`)
-i "C:\Users\mot\Desktop\Desktop_2025.07.19_-_20.17.50.03.DVR.mp4" -s 10 -cv libsvtav1 -brlow 3   (change preset, lower the final target bitrate by 3%)
```

# Codec options/usage tips

## libx265 (hevc/H265)
This is the default. H265 is a good codec overall. Presets over medium give diminishing returns for videos that require less compression, though it might make a bigger difference on larger videos that need to get compressed more.

libx265 supports these [presets](https://x265.readthedocs.io/en/master/presets.html): (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo)

The default preset is "medium"

## hevc_nvenc (hevc/H265 hardware accelerated for Nvidia GPUs)
In general, hardware-accelerated codecs may provide worse quality than their software (cpu) versions (in this case, compared to libx265), but they are A LOT faster, even at the highest quality/preset settings, though they can't usually beat a good software encoder in terms of quality.
For this reason, I wouldn't go below the max preset for nvenc, and some options are completely hardcoded with the use of a high quality preset in mind (such as enabling double pass with the full resolution. Normally, lower presets might disable this)
Note: Nvenc handles 2-pass encoding differently from software encoders. It performs both passes in a single run, so ff2ppress will go straight to the "final pass" instead of showing a separate first pass.

hevc_nvenc supports some weird presents, but the main ones are: p1, p2, p3, ... p7. Higher values provide higher quality. To see all presets run "ffmpeg -h encoder=hevc_nvenc"

Default preset (for this script) is "p7"

CBR (Constant bitrate) is also enabled for this codec, as I found better results with more stable file sizes.

## libx264 (avc/H264)
H264 is the least efficient when it comes for quality/file size out of these options, but it has the benifit of encoding decently fast (though still slower than hevc_nvenc), and its the most compatible with devices and services, which means its the best option if you want to guarantee that the video can be played with no issues, for example if you want to share the video. Though in my opinion, this should start to get replaced by the better h265. H264 also has a distinct pixelated look that's very noticeable and recognizable at lower bitrates.

libx264 supports the same [presets](https://trac.ffmpeg.org/wiki/Encode/H.264#a2.Chooseapresetandtune) as libx265: (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo)

The default preset is "medium"

## h264_nvenc (H264 hardware hardware-accelerated for Nvidia GPUs)
libx264 is pretty fast already on the cpu, but for the sake of having the option the script supports h264_nvenc too. Once again, hardware-accelerated encoders are very fast even at their highest settings, but the quality is lacking compared to their cpu versions (in this case libx264).

h264_nvenc supports the same main presets as hevc_nvenc: p1, p2, p3, ... p7. Higher values provide higher quality.

Default preset (for this script) is "p7"

CBR (Constant bitrate) is also enabled.

## libsvtav1 (av1)
IMPORTANT NOTE! ffmpeg does NOT support svt-av1 multi-pass mode. The script can still use 2pass encoding with svt-av1 by using SvtAv1EncApp in conjunction with ffmpeg, but that requires SvtAv1EncApp.exe to be added to path. You may [compile SvtAv1EncApp yourself](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Build-Guide.md) or download it from somewhere else, for example from [here](https://jeremylee.sh/bins/). If SvtAv1EncApp.exe is not found, then the script will fallback to using ffmpeg normally and encode the video with only 1 pass.

AV1 is considered one of the best codecs in terms of efficiency. Compared to AOM-AV1, SVT-AV1 is the faster av1 encoder, being able to scale better across cpu cores, comes with lots of presets, and many other fancy features that the original AOM-AV1 lacks. If you wish to use some of its features, such as [Variance Boost](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Appendix-Variance-Boost.md), you can use ff2ppress's -params argument to pass codec-specific arguments to ffmpeg. (Read the param block comment in the ps1 script for more info)

libsvtav1 supports these [presets](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Parameters.md#options): 0, 1, ... 13, 0 being the slowest and 13 the fastest.
You may be interested in reading Trix's [article(s)](https://wiki.x266.mov/blog/svt-av1-fourth-deep-dive-p1#presets-analysis-tldr) about SVT-AV1's presets and their efficiency. 

Default preset (for this script) is "5"

## libaom-av1 (av1)
AOM-AV1 is the reference implementation of AV1, which means it prioritizes quality and is extremely slow, though some say it's more efficient than SVT-AV1 by its nature. libaom-av1 does not have "presets" but it does have the "cpu-used" argument, which, for the purposes of this script it can be considered as a "preset" setting. Even at the fastest value (8) it can achieve impressive results.

libaom-av1 supports these "[cpu-used](https://ffmpeg.org/ffmpeg-codecs.html#libaom_002dav1)" values as "presets": (0, 1, 2, ... 8), 0 being the slowest while 8 the fastest. For reference, the library defaults to 1.

Default preset (for this script) is "8"

Row multi-threading (-row-mt) is also enabled.

## Audio codecs: libopus (opus) / aac
The default is libopus with 128k bitrate (or the input video's, if it's lower). If you're unsatisfied with how it sounds, try AAC. From what I read, opus does great at medium bitrates (64k, 128, 192k), but at very low bitrates you might want to try AAC. At high bitrates the difference between codecs is very minor.

# Codec compatibility notice

While newer codecs might offer better compression/file size efficiency, they can lack compatibility with devices and services. For example, WhatsApp only supports h264 and AAC out of these codecs, and AV1 can be hard to play on some devices, so depending on what you want to do with the video different codecs are best for different use-cases. In general, H265 and Opus should play fine on most, relatively modern devices. If you're sharing the video and people are complaining they can't play it, use H264 and AAC. AV1 is great, but it works best for archival purposes.