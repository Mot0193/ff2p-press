# Script Parameters
Here you can find a list of the parameters and flags you can pass to ff2ppress, explanations on what each of them does, and usage examples.
Some parameters have name aliases. You can either use them by their full name or by the alias. For example, you can use either `-inputvideo` _or_ `-i`.

Most of these parameters have default values. If you’d like, you can change the defaults by editing the `param()` block at the top of `ff2ppress.ps1`.

To enable/disable boolean parameters, you can pass 1 or 0, respectively. For example: `-FancyRename 0` or `-retry 1`

## Basic Parameters
### -InputVideo (Alias: -i)
The path to the video file you want to compress. Out of the box, this is the only required argument for the script to function.

#### Usage:
`-i "C:\Users\Mot\Videos\video.mp4"`\
`-InputVideo video.mp4` (relative paths work as well)

### -TargetVideoSize_MiB (Alias: -s)
Target size of the output video file in MiB (mebibytes).

Default is 20.

#### Usage:
`-s 10`\
`-s 50`\
`-s 6.7` (decimals work as well)\
`-s 12.34`

### -OutputFolder (Alias: -o)
Path of an output folder.

Defaults to the folder where the input video is.

#### Usage:
`-o  C:\Users\Mot\Desktop`\
`-o  .\Desktop\CreativeFolderName` (relative paths work as well)

### -FancyRename (bool)
This controls whether or not output file names contain the target size, video encoder, and encoder preset in their names.

Default is true.

#### Examples:
With fancyrename enabled, output file names may look like this: `compressed_<TargetVideoSize>mib_<OriginalFileName>_<VideoEncoder>_<VideoEncoderPreset>.mp4`\
For example: `compressed_5mib_BLUE PRINCE_libx265_medium.mp4`

Disabling fancyrename makes ff2ppress only add `compressed_` at the start of the original file name, with no extra target size/encoder information.\
For example: `compressed_BLUE PRINCE.mp4`

#### Usage:
`-fancyrename 0` (disable)\
`-fancyrename 1` (enable)

## Video Parameters
### -VideoEncoder (Alias: -cv)
The video encoder used for compressing the input video. Not all FFmpeg encoders are available to use through ff2ppress. Check the available [encoders](Encoders.md).

Default is libx265.

#### Usage:
`-cv libx264`\
`-cv hevc_nvenc`\
`-cv libsvtav1`

### -VideoEncoderPreset (Alias: -cvpreset)
The video preset for the selected encoder. Each encoder may have different preset naming schemes. Check the supported presets for each [encoder](Encoders.md).

Depending on the selected video encoder, the preset defaults to:
- libx265 - medium
- hevc_nvenc - p7
- libx264 - slower
- h264_nvenc - p7
- libsvtav1 - 5
- libaom-av1 - 8
- libvpx-vp9 - 4

If you want to change the default presets for each codec inside the script, search for the `$EncoderPresetInfo` hash table and edit the `Default` values.

#### Usage:
`-cvpreset veryfast` (this is a valid preset for `libx265` and `libx264`)\
`-cvpreset p5` (this is a valid preset for `hevc_nvenc` and `h264_nvenc`)

### -EncoderParameters (Alias: -params)
Colon-separated list of encoder-specific parameters. This uses FFmpeg's `-<encoder>-params` argument, but ff2ppress automatically uses the correct name for the selected encoder.

#### Examples:
Let's say you selected the `libsvtav1` encoder, and you wish to use some of its advanced [parameters](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Parameters.md), such as [Variance Boost](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Appendix-Variance-Boost.md).\
You can use `-params` like so:\
`-params enable-variance-boost=1:variance-boost-strength=4:variance-octile=4`\
This will correctly pass `-svtav1-params enable-variance-boost=1:variance-boost-strength=4:variance-octile=4` to FFmpeg.

#### Usage:
`-params lp=4:lookahead=42:enable-variance-boost=1` (these are parameters for `libsvtav1` as an example)

### -TargetVideoHeight (Alias: -h) & -TargetVideoWidth (Alias: -w)
Set a video height or width in pixels to rescale the video. You can use either `-h` or `-w`, and the unset value will scale correctly to keep the aspect ratio of the video.
Make sure the selected value won't result in a fractional resolution on the other side. If you’d like, you can use a [calculator](https://calculateaspectratio.com/).

The default values (-1) do not rescale the video.

#### Examples:
Scaling down a video can make encoding faster, of course at the cost of overall video quality. You'd generally only set the height `-h` to rescale videos. For example, if you have a 2560x1440 video, using `-h 1080` will scale the video down to 1920x1080.

#### Usage:
`-h 1080`\
`-h 720`\
`-w 1920`\
`-h 1080 -w 1920` (you can set both values, but its uneccesay)\
`-h 736 -w 201` (nothing is stopping you from picking incorrect resolutions for the aspect ratio, but it will result in a funky looking video)

### -TargetVideoTrim (Alias: -trim)
Set a start and end timestamp seperated by "-" like so: `-trim <start_timestam>-<end_timestamp>`, to keep that section of the video while the rest will be trimmed out.

Timestamps can have the following formats: 
- Seconds 
- MM:SS
- HH:MM:SS
- HH:MM:SS.mmm

The end timestamp can be set to `end` to set it to the duration of the input video; in other words, the end of the video.

The video bitrate will be calculated correctly to account for the changed video duration. In some cases, the target bitrate will end up being higher than the input video bitrate. See: [ForceVideoEncoding](Parameters.md#-forcevideoencoding-bool) parameter.

#### Usage:
`-trim 0-10` (keep the first 10 seconds of the video, cut out the rest)\
`-trim 5-1:0` (keep the video from the 5th second to the 1st minute, cut out the rest) (you can combine timestamps with no issue)\
`-trim 10-end` (cut the first 10 seconds of the video)\
`-trim 0:1:30.5-end` (cut out the first 1 minute, 30 seconds and 0.5 seconds)

### -ForceVideoEncoding (bool)
When using [-trim](Parameters.md#-targetvideotrim-alias--trim), there could be a chance that the target video bitrate will end up being higher than the starting video target. This means trimming the video will theoretically be enough to get under the target file size without having to re-encode the video.

Enabling `ForceVideoEncoding` will always re-encode the video, even if the target video bitrate is higher than the input. Encoding may be slow, but will result in a video with no issues.

Disabling `ForceVideoEncoding` will attempt to copy the video and audio codec while just trimming the video. This approach may result in a choppy video, or the start of the video may be black for a few seconds.

Just trimming the video may not always result in a met target size, but if you have [RetryEncodingIfTargetNotMet](Parameters.md#-retryencodingiftargetnotmet-alias--retry-bool) enabled, the script will fall back to normal re-encoding to try to get the video below the target size.

Default is true.

#### Usage:
`-forcevideoencoding 0` (disable; in case the target video bitrate ends up being higher than the input, like stated above, the script will attempt to just trim the video without re-encoding)

### -TargetVideoBitrate_kbps (Alias: -brv)
Set a target video bitrate in kbps manually instead of letting ff2ppress calculate a video bitrate. Setting this makes the script ignore the [target size](Parameters.md#-targetvideosize_mib-alias--s) and will instead compress the input video with your desired bitrate.

#### Usage:
`-brv 1000` (this will forcefully set the video bitrate to 1000 kbps)

### -BitratePercentageLow (Alias: -brlow)
A percentage of how much the final target video bitrate should be lowered. This can be used without explicitly setting a [target size](Parameters.md#-targetvideosize_mib-alias--s) to instead lower the input video's bitrate by the percentage.

Default is 0.

#### Examples:
Sometimes the output video size overshoots the target size, and the script will have to [retry](Parameters.md#-retryencodingiftargetnotmet-alias--retry-bool) with a lower video bitrate. If you want to make sure the video will get below the target size in one attempt, you may use `-brlow 5` to lower the target bitrate by 5%.

If you dont have a specific target size requirement for a video, you may use `-brlow` **without** setting [-s](Parameters.md#-targetvideosize_mib-alias--s) to lower the input video's size by a rough percentage\*. For example `-brlow 50` will lower the input video's bitrate by 50% and use that as the target bitrate.
\*Of course `-brlow` only affects the video bitrate, so the [audio bitrate](Parameters.md#-targetaudiobitrate_kbps-alias--bra) won't be accounted for.

#### Usage:
`-s 20 -brlow 3` (target size MUST be set in order to allow the script to calculate a video bitrate for the target size, and brlow to lower it by 3%)\
`-brlow 3` (NOT setting a target size will only lower the input video's bitrate by 3%)\
`-brlow 60` (since a target size was not set, lower the input video's bitrate by 60%)

## Audio Parameters
### -SelectedAudioEncoder (Alias: -ca)
The audio encoder used for compressing the input video's audio. Not all FFmpeg encoders are available to use through ff2ppress. Check the available [encoders](Encoders.md).

Default is libopus.

Keep in mind that if [ForceAudioEncoding](Parameters.md#-forceaudioencoding-bool) is disabled, and if the input video's audio bitrate is below the [target audio bitrate](Parameters.md#-targetaudiobitrate_kbps-alias--bra), the script will skip re-encoding the audio, and it will just copy the audio stream from the input video to the output video.

#### Usage:
`-ca aac`\
`-ca libopus`

### -TargetAudioBitrate_kbps (Alias: -bra)
The target audio bitrate in kbps. 
If the input video's audio bitrate is lower than the target audio bitrate, ff2ppress will use the lower audio bitrate. In this case, if [ForceAudioEncoding](Parameters.md#-forceaudioencoding-bool) is disabled, the script will skip re-encoding the audio and it will just copy the audio stream from the input video to the output video.

Default is 128.

#### Usage:
`-bra 96`\
`-bra 192`

### -ForceAudioEncoding (bool)
Enables forcing re-encoding the audio with the [selected encoder](Parameters.md#-selectedaudioencoder-alias--ca), even if the input video's audio bitrate is lower than the target audio bitrate.

Default is false.

#### Usage:
`-ForceAudioEncoding 1`

### -PrioritizeAudioBitrate (bool)
Enable to NOT recalculate the audio bitrate if the audio would end up taking more than 20% of the output video file.

Enabling this does NOT prevent the script from picking the input video's audio bitrate if it's lower than the target bitrate.

Default is false.

#### Example:
After the video bitrate has been calculated, the script checks if the audio would take up more than 20% of the output video file. If it would, the script automatically recalculates the audio bitrate so it takes at most 20% of the file. This prevents the audio bitrate from leaving proportionally less bitrate for the video stream, or worse, the audio bitrate taking up more than 100% of the file. This specific issue tends to happen with long videos set to very small target sizes.

Use PrioritizeAudioBitrate if you wish to make the script use your selected audio bitrate instead of letting the script lower the bitrate to 20% of the file. The script will still check if the audio would take 100% or more of the file target size.

#### Usage:
`-PrioritizeAudioBitrate 1` (if the edge case mentioned above gets triggered, audio will not be recalculated to fit 20% of the file)

## Other Parameters
### -InputAudioStream (Alias: -audiostream)
Choose the audio stream of a multi-stream video file.

Default is 0 (the first available audio stream).

#### Example:
If the input video has multiple audio streams, ff2ppress can only keep one of them. Stream indexes start at 0, so if you want to keep the 2nd audio stream, you can use `-audiostream 1`.

#### Usage:
`-audiostream 1`\
`-audiostream 3`

### -InputVideoStream (Alias: -videostream)
Choose the video stream of a multi-stream video file.

Default is 0 (the first available audio stream).

#### Example:
If the input video has multiple video streams ff2ppress can only keep one of them. Stream indexes start at 0, so if you want to keep the 2nd video stream, you can use `-videostream 1`.

#### Usage:
`-videostream 6`\
`-videostream 7`(WHY would you have a file with this many video streams?? ONE stream is enough already)

### -RetryEncodingIfTargetNotMet (Alias: -retry) (bool)
Automatically retry to encode the video if it fails to get down to the target size.

The [-retrylow](Parameters.md#-retryencodingpercentagelowamount-alias--retrylow-bool) parameter determines how or by how much the bitrate should be lowered on each attempt.\

Default is true.

#### Usage:
`-retry 0` (disable automatic retry if the video goes over the target size)

### -RetryEncodingPercentageLowAmount (Alias: -retrylow) (bool)
When [retrying](Parameters.md#-retryencodingiftargetnotmet-alias--retry-bool) to re-encode the video, lower the target audio bitrate by this percentage amount.\
If this value is set to a negative number (e.g -1), the percentage will be selected dynamically based on how much the resulting video overshot the target size.

Default is -1. (dynamic mode enabled)

#### Example:
If the video fails to get down to size after the first encoding attempt, the script will keep retrying while lowering the video bitrate by 2% (the default value for this parameter) each attempt until the video meets the target size.

#### Usage:
`-retrylow 5` (each subsequent retry lowers the bitrate by 5%)
`-retrylow -1` (enable dynamic mode)

## Debug Mode (see the ffmpeg argument list before compressing)

You can use PowerShell's `-debug` argument when running ff2ppress to see the full ffmpeg argument lists before running ffmpeg.

## Passing Other FFmpeg Arguments

FF2ppress allows the use of most FFmpeg arguments/flags by simply adding them to the script just like you would to FFmpeg. ANY additional parameters which are passed to this script that PowerShell does not recognize will be instead redirected to FFmpeg itself.

This feature is useful if you wish to achieve something that this script's own parameters does not handle, and you know theres a native FFmpeg parameter can do it.

### Examples:

To add metadata to the output video, use ffmpeg's -metadata parameter directly to ff2ppress: 
```
ff2ppress.ps1 -i video.mp4 -cv libx264 -s 20 -brlow 5 -metadata comment="yay metadata" -metadata title="the sickest title"
```

### Caveats and Limitations:

- If you need to chain several options with a comma, for example when you're specifying multiple video filters with -vf (or -filter:v), you may need to put the entire comma-separated options in quotes like so:

```
ff2ppress.ps1 -i video.mp4 -filter:v "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"
```
- Your arguments will be placed right BEFORE the output file argument inside the ffmpeg argument lists.

- Your arguments WILL be used for both passes.

- Your arguments will NOT be used for the "[just trimming](Parameters.md#-forcevideoencoding-bool)" argument list.

- FF2ppress's own [-h & -w](Parameters.md#-targetvideoheight-alias--h---targetvideowidth-alias--w) parameters use ffmpeg's video filter parameter under the hood. You can add your own video filters just fine, and the script will merge these filters for you, though the rescale args will be placed first in the filter list (for example: `-vf scale=-1:720,your=filter,example=filter`). If this somehow messes with your super-secret and super-specific use case, you can of course not use ff2ppress's rescale parameters and instead add them via `-vf`.

- You cannot pass an ffmpeg argument that starts with the same letter(s) as any script parameter mentioned in this document. PowerShell will try to match that parameter to a script parameter, but will fail. 
I haven't found an ffmpeg parameter that will both technically work but can't be passed because of this quirk, but for example, trying to use ffmpeg's `-f` parameter will gets you the error: `... parameter name 'f' is ambiguous. Possible matches include: -fancyrename -ForceVideoEncoding -ForceAudioEncoding.`