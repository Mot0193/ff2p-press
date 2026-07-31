# ff2p-press
FF2PPress is a PowerShell script that uses ffmpeg 2-pass encoding to compress videos to a given size. It supports several video encoders provided by ffmpeg, as well as the option to pass advanced parameter and options.

## ffmpeg installation
Make sure to install an ffmpeg package that contains all the supported codecs you wish to use. If you're on Windows, you can install the "full" ffmpeg release from [gyan.dev](https://www.gyan.dev/ffmpeg/builds/):

```
winget install ffmpeg
```

## Quick usage parameters:
| Parameter | Description |
|---|---|
|`-i <path_to_file>`| Video file input|
|`-s <desired_file_size_in_MiB>`| Set the target size of the file in mebibytes|
|`-o <folder_path>`| Optionally set the output folder for the compressed video. Not setting this will output the video in the same folder as the input video|
|`-h <desired_resolution>`<br> or <br>`-w <desired_resolution>`| Optionally rescale the video. You may only use -h (height) to automatically scale the width to match the aspect ratio or vice versa. For example, using `-h 1080` on a 2560x1440 video will result into a 1920x1080 video. Scaling down a video can make encoding faster.|

That's it! For advanced encoder settings continue reading and consult the example usages below.

## Examples of parameter usage
See the "param" block inside the ps1 script for all the parameters you can set. All of them have comments explaining what each parameter does.

| Example command | Explanation |
|---|---|
|.\ff2ppress.ps1 -i "C:\Users\mot\Desktop\Overwatch.mp4" -s 30|Compresses the input video to the selected size with the default settings|
|.\ff2ppress.ps1 -i "C:\Users\mot\Desktop\drive.mp4" -s 30 -cvpreset veryslow -cv libx264|Change the default video codec and use a different preset compatible with the codec|
|C:\path\to\script\ff2ppress.ps1  -i "C:\Users\mot\Desktop\VeryGoodVideo.mp4" -s 16 -fancyrename 0|Disable fancy rename. Files will just be named `compressed_<original_video_name>`|

# Supported Codecs
The default video encoder is libx265 (h265) at the "medium" preset, and the audio encoder is libopus (opus) at 128kbps bitrate. I manually picked the default preset for each codec, which i considered to be balanced enough for most users. You can of course change the video codec with `-cv` and the preset with `-cvpreset`, and even modify the default values in the "param" block at the top of the script.

## libx265 (hevc/H265)
H265 is a decent codec overall, but libx265 is pretty slow for what it offers. In most cases i found that using libsvtav1 (AV1) is both faster and yields higher quality. Some devices, such as older smartphones, may struggle to play h265 videos. Some services and programs may not support h265 videos.

libx265 supports these [presets](https://x265.readthedocs.io/en/master/presets.html): (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo)

The default preset is "medium"

## hevc_nvenc (hevc/H265 hardware accelerated for Nvidia GPUs)
In general, hardware-accelerated codecs may provide worse quality than their software (cpu) versions (in this case, compared to libx265), but they are A LOT faster even at the highest quality/preset settings.
For this reason, I wouldn't go below the max preset for nvenc encoders, and some options are completely hardcoded with the use of a high quality preset in mind (such as enabling double pass with the full resolution. Normally, lower presets might disable this)

> [!NOTE]
> Nvenc handles 2-pass encoding differently from software encoders. It performs both passes in a single run, so ff2ppress will go straight to the "final pass" instead of showing a separate first pass.

hevc_nvenc supports some weird presents, but the main ones are: p1, p2, p3, ... p7. Higher values provide higher quality. To see all presets run "ffmpeg -h encoder=hevc_nvenc"

Default preset (for this script) is "p7"

> [!NOTE]
> Unlike the software presets which use VBR (variable bitrate), nvenc is set to use CBR (constant bitrate) instead, since it often has a hard time hitting video target with VBR. If i had to guess why that is, its probably because nvenc doesnt do a "true" 2-pass even with 2-pass enabled. 

## libx264 (avc/H264)
H264 is the least efficient out of these options when it comes to quality, but it has the benefit of encoding pretty fast (though still slower than hardware encoders). Its the most compatible with devices and services, which means its the best option if you want to guarantee that the video can be played with no issues. 

From my testing libx264 seems to overshoot the file size quite often. If you'd like you can use `-retry 1` to enable automatic re-encoding if the video fails to reach the target size; `-brlow <value> ` to automatically lower the target bitrate by a percentage; or pick a lower target size.

libx264 supports the same [presets](https://trac.ffmpeg.org/wiki/Encode/H.264#a2.Chooseapresetandtune) as libx265: (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo)

The default preset is "medium"

## h264_nvenc (H264 hardware accelerated for Nvidia GPUs)
libx264 is pretty fast already on the cpu, but for the sake of having the option the script supports h264_nvenc too. Once again, hardware-accelerated encoders are very fast even at their highest settings, but they have a lower quality ceiling compared to their cpu versions (in this case libx264).

h264_nvenc supports the same main presets as hevc_nvenc: p1, p2, p3, ... p7. Higher values provide higher quality.

Default preset (for this script) is "p7"

CBR (Constant bitrate) is also enabled.

## libsvtav1 (av1)

> [!WARNING]
> Make sure your ffmpeg version is at least 8.1 in order to properly use svtav1 in 2-pass mode!

<details>
<summary>More info about svtav1 and 2-pass encoding with ffmpeg</summary>

Up until recently, ffmpeg did NOT support svt-av1 multi-pass mode. FF2PPress can use 2pass encoding with svt-av1 by using SvtAv1EncApp in conjunction with ffmpeg (ffmpeg piping the video to svtav1encapp), but that requires SvtAv1EncApp.exe to be added to path, or in the same directory as the script. You may [compile SvtAv1EncApp yourself](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Build-Guide.md) or download it from somewhere else, for example from [here](https://jeremylee.sh/bins/) (compiling yourself is best as you can guarantee you're getting the latest version).

As of ffmpeg version 8.1 proper [2-pass support for svt-av1](https://code.ffmpeg.org/FFmpeg/FFmpeg/pulls/21239) got added to ffmpeg. Ff2ppress assumes you are using the latest version of ffmpeg, so when using libsvtav1 it will try to 2-pass the video. On older versions of ffmpeg this would have just resulted in the video getting 1-pass encoded twice, wasting your precious time for no real benefit.
</details>

AV1 is considered one of the best codecs in terms of efficiency. Compared to AOM-AV1, SVT-AV1 is the faster av1 encoder, being able to scale better across cpu cores, comes with lots of presets and many other fancy features, and in general it's the recommended av1 encoder to use. If you wish to use some of its features, such as [Variance Boost](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Appendix-Variance-Boost.md), you can use ff2ppress's -params argument to pass codec-specific arguments to ffmpeg. (Read the param block comment in the ps1 script for more info)

SVT-AV1 has matured a lot, and from my experience its pretty fast for the quality it can achieve. In some cases since AV1 is royalty-free, it can have better service support compared to h265. But some devices, especially smartphones, can struggle to play AV1 videos as they may be lacking hardware AV1 decoders.

libsvtav1 supports these [presets](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Parameters.md#options): 0, 1, ... 13, 0 being the slowest and 13 the fastest.

Default preset (for this script) is "5"

## libaom-av1 (av1)
AOM-AV1 is the reference implementation of AV1, which means it prioritizes quality and is extremely slow, though some say it's more efficient than SVT-AV1 by its nature. libaom-av1 does not have "presets" but it does have the "cpu-used" parameter, which, for the purposes of this script it can be considered as a "preset" setting.

libaom-av1 supports these "[cpu-used](https://ffmpeg.org/ffmpeg-codecs.html#libaom_002dav1)" values as "presets": (0, 1, 2, ... 8), 0 being the slowest while 8 the fastest. For reference, the library defaults to 1.

Default preset (for this script) is "8"

## libvpx-vp9 (vp9)
libvpx-vp9 is the reference implementation of vp9. Vp9 is known for being "YouTube's codec", as it was originally developed by Google. It's meant to be slightly worse than h265 in terms of efficiency, but at a much higher decoding (playback) speed. Unfortunately this comes at the cost of a fairly slow encoding speed, since libvpx-vp9 is the reference implementation after all.
Like libaom-av1, the encoder doesn't have "presets", instead is uses a "cpu-used" parameter, which, for the purposes of this script it can be considered as a "preset" setting.

> [!IMPORTANT]
> You should probably never use a preset of 5 and above, as the 1st pass will be significantly slower. From my testing preset 4 is the fastest, and it's the default for this script.

libvpx-vp9 supports these "[cpu-used](https://ffmpeg.org/ffmpeg-codecs.html#Options-38)" values as "presets": (-8, -7, ... 7, 8), -8 being the slowest while 4 being the fastest. Values of 5 and above are actually slower on the 1st pass, making them not worth it.

## Audio codecs: libopus (opus) / aac
The default is libopus at 128k bitrate (if the input video's bitrate isn't lower). From what I read, opus does great at medium bitrates (64k, 128k, 192k), but at _very_ low bitrates you might want to try AAC. At high bitrates the difference between codecs is minor. By default, the script will skip encoding the audio if the bitrate is already below the target, and it will just copy the audio from the input video to the output video. In this case you may use `-ForceAudioTranscoding 1` to forcefully re-encode the audio to your selected codec, but it will still use the input video's audio bitrate if it's lower than the target audio bitrate.