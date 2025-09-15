# ff2p-press
A Powershell script for Windows that uses FFMPEG 2-pass encoding to compress videos to a given size.

This script compresses videos with various video codecs and settings, using ffmpeg with double-pass encoding (with some exceptions, such as with libaom-av1)
The default options (when no extra arguments are given other than the input file and file size) are the video codec libx265 with the medium preset, and the audio codec libopus at 128kbps bitrate.
Videos will get output to Desktop with the names starting with "compressed_" and ending with the codec used e.g "_libx265".

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

## libaom-av1 (av1)
This is av1 software encoding. VERY slow, but considered the best. Because of its mind-numbing speed, i consider going under the preset 8 to be brave (this is actually the "cpu-used" argument, not really a "preset").
But, even at the fastest preset (8) with just one pass, it can achieve great results, even better and faster compared to libx265 at the slow preset. This is just from my very limited testing, though.

libaom-av1 supports these "cpu-used" values as "presets": https://ffmpeg.org/ffmpeg-codecs.html#libaom_002dav1 (0, 1, ... 8) 0 being the slowest while 8 the fastest. For reference, the library defaults to 1.

Default preset is "8"

## Audio codecs: libopus (opus) / acc
The default is libopus, but if youre unsatisfied with how it sounds try ACC. From what i read opus does great at medium bitrates (64k, 128, 192k), but at very low bitrates you might want to try ACC. At high bitrates the difference between codecs is very minor, hence why the default codec is libopus.

# Codec compatibility notice

While newer codecs might offer better compression/file size efficiency, they can lack compatibility with devices and services. For example AV1 is known for being hard to playback on some devices (especially mobile devices, and even half-modern computers with no hardware AV1 decoding can struggle), so depending of what you want to do with the video different codecs are best for different use-cases. Heres a rough list of codecs from the most compatible:

Video Codecs:
- H264 (most compatible)
- H265
- AV1

Audio Codecs:
- ACC (most compatible)
- Opus

# Examples of parameter usage
```
-i "C:\Users\mot\Desktop\Overwatch_28.08.2025_21-18-54.mp4" -s 30
-s 50 -i "C:\Users\mot\Desktop\drive.mp4" -cv libaom-av1
-i "C:\Users\mot\Desktop\Overwatch_28.08.2025_21-18-54.mp4" -s 10 -cv hevc_nvenc
```

See the "param" block at the top of the ps1 script for all the parameters you can set. Some have aliases (for example you can use "-video" _or_ just "-i")