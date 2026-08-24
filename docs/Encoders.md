# Supported Video Encoders

The default video encoder is libx265 at the “medium” preset, and the audio encoder is libopus at 128kbps bitrate. I manually picked the default preset for each encoder, which i considered to be balanced enough for most users.

## libx265 (hevc/H265)

H265 is a decent codec overall, but libx265 is pretty slow for what it offers. In most cases, I found that using libsvtav1 is both faster and yields higher quality. Some devices, such as older smartphones, may struggle to play h265 videos. Some services and programs may not support h265 videos.

libx265 supports these presets: (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo)

The default preset for this script is “medium”

## hevc_nvenc (hevc/H265 hardware accelerated for Nvidia GPUs)

In general, hardware-accelerated encoders can provide worse quality than their software (CPU) versions (in this case, compared to libx265), but they are A LOT faster even at the highest quality/preset settings.

hevc_nvenc’s main presets are: p1, p2, p3, … p7. Higher values provide higher quality. To see all presets, run “ffmpeg -h encoder=hevc_nvenc”

The default preset for this script is “p7”

> [!NOTE]
> NVENC handles 2-pass encoding differently from software encoders. It performs both passes in a single run, so ff2ppress will go straight to the “final pass” instead of showing a separate first pass.
> Unlike the software presets which use VBR (variable bitrate), NVENC is set to use CBR (constant bitrate) instead, since it often has a hard time hitting video target with VBR.

## libx264 (avc/H264)

H264 is the least efficient out of these options when it comes to quality, but it has the benefit of encoding pretty fast (though still slower than hardware encoders). It's the most compatible with devices and services, which means it's the best option if you want to guarantee that the video can be played with no issues.

From my testing, libx264 seems to overshoot the file size quite often. If you’d like you can use -retry 1 to enable automatic re-encoding if the video fails to reach the target size; -brlow <value>  to automatically lower the target bitrate by a percentage; or pick a lower target size.

libx264 supports the same presets as libx265: (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo)

The default preset for this script is “slower”

## h264_nvenc (H264 hardware accelerated for Nvidia GPUs)

libx264 is pretty fast already on the CPU, but for the sake of having the option, the script supports h264_nvenc too. Once again, hardware-accelerated encoders are very fast even at their highest settings, but they have a lower quality ceiling compared to their cpu versions (in this case libx264).

h264_nvenc supports the same main presets as hevc_nvenc: p1, p2, p3, … p7. Higher values provide higher quality.

The default preset for this script is “p7”

CBR (Constant bitrate) is also enabled.

## libsvtav1 (av1)

> [!WARNING]
> Make sure your ffmpeg version is at least 8.1 in order to properly use svtav1 in 2-pass mode!

AV1 is considered one of the best codecs in terms of efficiency. Compared to AOM-AV1, SVT-AV1 is the faster av1 encoder, being able to scale better across cpu cores, comes with lots of presets and many other fancy features, and in general it’s the recommended av1 encoder to use. If you wish to use some of its features, such as Variance Boost, you can use FF2press’s -params argument to pass encoder-specific arguments to ffmpeg.

SVT-AV1 has matured a lot, and from my experience it's pretty fast for the quality it can achieve. In some cases, since AV1 is royalty-free, it can have better service support compared to h265. But some devices, especially smartphones, can struggle to play AV1 videos as they may be lacking hardware AV1 decoders.

libsvtav1 supports these presets: 0, 1, … 13, with 0 being the slowest and 13 the fastest.

The default preset for this script is “5”

## libaom-av1 (av1)

AOM-AV1 is the reference implementation of AV1, which means it prioritizes quality and is extremely slow. libaom-av1 does not have “presets” but it does have the “cpu-used” parameter, which, for the purposes of this script it can be considered a “preset” setting.

libaom-av1 supports these “cpu-used” values as “presets”: (0, 1, 2, … 8), 0 being the slowest while 8 is the fastest.

The default preset for this script is “8”

## libvpx-vp9 (vp9)

VP9 is known for being “YouTube’s codec”, as it was originally developed by Google and it’s the go-to codec that YouTube uses. It’s meant to be slightly worse than h265 in terms of efficiency, but at a much higher decoding (playback) speed. Unfortunately, this comes at the cost of a fairly slow encoding speed, as libvpx-vp9 is the reference implementation of vp9.
Like libaom-av1, the encoder doesn’t have “presets”, instead is uses a “cpu-used” parameter, which, for the purposes of this script it can be considered as a “preset” setting.

> [!IMPORTANT]
> You should probably never use a preset of 5 and above, as the 1st pass will be significantly slower. From my testing preset 4 is the fastest, and it’s the default for this script.

libvpx-vp9 supports these “cpu-used” values as “presets”: (-8, -7, … 7, 8), with -8 being the slowest while 4 being the fastest. Values of 5 and above are actually slower on the 1st pass, making them not worth it.

# Supported Audio Encoders: libopus / aac

The default audio encoder is libopus at 128k bitrate, or the input video’s audio bitrate if it's lower. From what I read, Opus does great at medium bitrates (64k, 128k, 192k), but at very low bitrates you might want to try AAC. At high bitrates, the difference between codecs is minor.

By default, the script will skip encoding the audio if the bitrate is already below the target, and it will just copy the audio from the input video to the output video. In this case, you may use -ForceAudioEncoding 1 to forcefully re-encode the audio to your selected codec, but it will still use the input video’s audio bitrate if it’s lower than the target audio bitrate.