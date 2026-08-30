Here you'll find a list of FFmpeg encoders that FF2ppress supports, as well as the presets you can set for each encoder. Some encoders may come with extra ffmpeg parameters that the script sets automatically, they are listed here too.

The default video encoder is `libx265` with the `medium` preset, and the default audio encoder is `libopus` at `128`k bitrate. See the relevant [Parameters](Parameters.md) for changing encoders, presets, and the audio bitrate.

Encoders and video formats are complicated, there's no easy answers for questions such as "Whats the best encoder". That question depends on your use case, your hardware, and your own subjective judgment when it comes to quality and encode times. I recommend trying out different encoders and their presets to come up with your own conclusion. 

# Software Video Encoders
Software encoders use the CPU for encoding, which makes them slower than hardware encoders, but they have a lot more room for quality, tweaking settings, and dont require dedicated hardware (such as a GPU with hardware encoding). They are also better suited for targeting specific file sizes, which is the primary goal of this script.

## libx265
Encodes videos in the H.265 (or HEVC) format.

Valid presets: `ultrafast`, `superfast`, `veryfast`, `faster`, `fast`, `medium`, `slow`, `slower`, `veryslow`, `placebo`.
Default preset (if no preset is specified): `medium`

## libx264
Encodes videos in the H.264 (or AVC) format.

Valid presets: `ultrafast`, `superfast`, `veryfast`, `faster`, `fast`, `medium`, `slow`, `slower`, `veryslow`, `placebo`.
Default preset (if no preset is specified): `slower`

## libsvtav1
Encodes videos in the AV1 format.

Valid presets: `13` through `0`, where 0 is the slowest and 13 is the fastest
Default preset (if no preset is specified): `5`
Extra FFmpeg parameters: `-svtav1-params lookahead=42`

## libaom-av1
Encodes videos in the AV1 format.

Valid presets: `8` through `0`, where 0 is the slowest and 8 is the fastest
Default preset (if no preset is specified): `8`
Extra FFmpeg parameters: `-row-mt 1`

> [!NOTE]
> Libaom-av1 doesn't actually have "presets", instead it uses a "cpu-used" parameter. For the purposes of this script "cpu-used" can be considered a preset, so you can use FF2ppress's -cvpreset parameter with the mentioned valid presets.

## libvpx-vp9
Encodes videos in the VP9 format.

Valid presets: `8` through `-8`, where -8 is the slowest and 4 is the fastest*
Default preset (if no preset is specified): `4`
Extra FFmpeg parameters: `-row-mt 1`

> [!IMPORTANT]
> *With 2-pass enabled, libvpx-vp9 is actually slower on presets 5 and above, so it's not recommended to use them.

> [!NOTE]
> Libvpx-vp9 doesn't actually have "presets", instead it uses a "cpu-used" parameter. For the purposes of this script "cpu-used" can be considered a preset, so you can use FF2ppress's -cvpreset parameter with the mentioned valid presets.

# Hardware Video Encoders

## NVENC
NVENC is the hardware encoder some Nvidia GPUs have. [Depending on your GPU](https://developer.nvidia.com/video-encode-decode-support-matrix), FF2ppress supports the following encoders:
- `h264_nvenc`
- `hevc_nvenc`
- `av1_nvenc`

These apply to all NVENC encoders:
Valid presets: `p7` through `p1`, where p7 is the slowest and p1 is the fastest
Default preset (if no preset is specified): `p7`
Extra FFmpeg parameters: `-rc cbr` `-multipass fullres`

> [!NOTE]
> NVENC lacks a true 2-pass mode, so FF2ppress will do only 1 pass. NVENC also has a hard time hitting the file target with VBR (variable bitrate), so CBR (constant bitrate) is used instead.

# Audio Encoders
Available audio encoders are:
- `libopus`
- `aac`

The default target audio bitrate is `128` (kbps) or the input video's audio bitrate, if it's lower.