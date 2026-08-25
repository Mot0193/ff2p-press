# FF2p-press (FFmpeg 2pass compress)

FF2ppress is a PowerShell script that uses 2-pass encoding via FFmpeg to compress videos to a target size in MiB, useful for uploading or sharing on platforms with file size limits, such as Discord.

FF2ppress's main feature is customizability and control, allowing you to change advanced FFmpeg settings and parameters, such as:

* [Trimming](/docs/Parameters.md#-targetvideotrim-alias--trim) the video;
* Changing the [video encoder](/docs/Parameters.md#-videoencoder-alias--cv) and [preset](/docs/Parameters.md#-videoencoderpreset-alias--cvpreset);
* [Passing parameters](/docs/Parameters.md#-encoderparameters-alias--params) to the encoder;
* Specifying the [audio or video stream](/docs/Parameters.md#-inputaudiostream-alias--audiostream) of a multi-stream input file;
* Being able to pass most [FFmpeg arguments directly](/docs/Parameters.md#passing-other-ffmpeg-arguments), which opens up the majority of FFmpeg’s functionality;

This customizability tries not to sacrifice ease of use: The script comes with hand-picked defaults; It tries to automatically deal with most scenarios and edge cases; And it comes with parameters that simplify some of the more common FFmpeg use cases (such as [downscaling the resolution](/docs/Parameters.md#-targetvideoheight-alias--h---targetvideowidth-alias--w), or trimming the video).

# Installation & Dependencies

## On Windows

On Windows, make sure PowerShell and FFmpeg are installed and updated.
Your FFmpeg version should be above 8.1, and it should contain all the script-compatible video encoders that you wish to use. You can install the "full" FFmpeg release from [gyan.dev](https://www.gyan.dev/ffmpeg/builds/):
```
winget install Microsoft.PowerShell
winget install ffmpeg
```

Download or clone the repository:
```
git clone https://github.com/Mot0193/ff2p-press.git && cd ff2p-press
```

If you get this error when you try to run ff2ppress.ps1: `The file ff2ppress.ps1 is not digitally signed`, open a PowerShell window and run:
```
dir -r C:\path\to\folder\ff2p-press\*.ps1 | Unblock-File
```
You may add ff2ppress.ps1 to your PATH variable if you'd like.
## Via Nix

FF2ppress contains a Nix flake, which makes installation easy on systems that use [Nix](https://nixos.org/learn/).

Install with Nix:
```
nix profile install github:mot0193/ff2p-press
```

# Quick Usage
Here you can find a short list of the most common parameters and use cases. You can find a full list of [Parameters](/docs/Parameters.md) in the [docs folder](/docs/). 

## Common parameters
| Parameter | Description |
|---|---|
|`-i <path_to_file>`| Video file input. This is the only required parameter for the script to function|
|`-s <desired_file_size_in_MiB>`| Target size of the file in mebibytes. The default is 20 MiB, enough for the Discord file size limit|
|`-o <folder_path>`| Output folder for the compressed video. Not setting this will output the video in the same folder as the input video|
|`-cv <encoder>` | The encoder used for compressing the video (e.g. `libx264`). Available encoders are listed in the [Supported Encoders](/docs/Encoders.md) documentation file.|
|`-cvpreset <preset_for_selected_encoder>`| Preset for the selected encoder. Preset naming schemes may be different between encoders, see [Supported Encoders](/docs/Encoders.md) for the preset names for each encoder. |
|`-h <desired_resolution>`<br> or <br>`-w <desired_resolution>`| Rescale resolution. You may only use -h (height) to automatically scale the width to match the aspect ratio or vice versa (e.g. using `-h 1080` on a 2560x1440 video will result into a 1920x1080 video). Scaling down a video can make encoding faster.|

## Examples of Usage
| Example command | Explanation |
|---|---|
|C:\path\to\script\ff2ppress.ps1 -i "C:\Users\Mot\Videos\BLUE PRINCE.mp4" | Compress the input video with the default settings to the default size (20 MiB)|
|.\ff2ppress.ps1 -i "C:\Users\mot\Desktop\Overwatch.mp4" -s 50 -cv libx264 | Compresses the input video to 50 MiB with the selected video encoder|
|ff2ppress -i "C:\Users\mot\Desktop\drive.mp4" -cv libsvtav1 -cvpreset 7  | Change the default video encoder and use a different preset compatible with it|