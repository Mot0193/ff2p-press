# FF2p-press (FFmpeg 2pass compress)

FF2ppress is a PowerShell script that uses 2-pass encoding via FFmpeg to compress videos to a target size in MiB, useful for uploading or sharing on platforms with file size limits, such as Discord.

FF2ppress is highly customizable, allowing you to change advanced FFmpeg settings and parameters, such as:

* Changing the [video encoder](/docs/Parameters.md#-videoencoder-alias--cv) and [preset](/docs/Parameters.md#-videoencoderpreset-alias--cvpreset);
* [Passing parameters](/docs/Parameters.md#-encoderparameters-alias--params) to the video encoder;
* Specifying the [audio or video stream](/docs/Parameters.md#-inputaudiostream-alias--audiostream) of a multi-stream input file;
* Being able to pass most [FFmpeg arguments directly](/docs/Parameters.md#passing-other-ffmpeg-arguments), which opens up the majority of FFmpeg’s functionality;

This customizability tries not to sacrifice usability, and the script can be as simple or as complicated as you want it to be. It's easy to start using it, as all you need is [input video parameter](/docs/Parameters.md#-inputvideo-alias--i), and the default encoders targeting 20 MiB file sizes should be satisfactory for most users out of the box. See [examples](#examples-of-usage) below!

# Installation & Dependencies

## On Windows

On Windows, make sure PowerShell and FFmpeg (with FFprobe) are installed and updated to their **latest version** (at least PowerShell 7 and FFmpeg 8.1). FFmpeg must be compiled with all the script-compatible [encoders](/docs/Encoders.md) you wish to use. You may install the "full" FFmpeg release from [gyan.dev](https://www.gyan.dev/ffmpeg/builds/), and it should be fine:
```
winget install Microsoft.PowerShell
winget install ffmpeg
```

Download or clone the repository:
```
git clone https://github.com/Mot0193/ff2p-press.git && cd ff2p-press
```

If you get this error when you try to run ff2ppress.ps1: `The file ff2ppress.ps1 is not digitally signed`, open a PowerShell window and run:
```pwsh
dir -r C:\path\to\folder\ff2p-press\*.ps1 | Unblock-File
```
You may add ff2ppress.ps1 to your PATH variable if you'd like.

## Via Nix

FF2ppress contains a Nix flake, which makes installation easy on systems that use [Nix](https://nixos.org/learn/).

Run or install with Nix:
```bash
# requires extra-experimental-settings "nix-command flakes" to be configured

nix run github:mot0193/ff2p-press -- -i {file}  # run ff2p-press
nix shell github:mot0193/ff2p-press             # open a shell with ff2p-press inside

# install ff2p-press imperatively (not recommended)
nix profile install github:mot0193/ff2p-press
```

# Quick Usage
Here you can find a short list of the most common parameters. You can find a full list of [Parameters](/docs/Parameters.md) in the [docs folder](/docs/).

## Common parameters
| Parameter | Description | Default Value | 
|---|---|---|
|`-i`| Input video file path. This is the only required parameter for the script to function | N/A |
|`-s`| Target size of the file in mebibytes (MiB). | `20` |
|`-o` | Output folder path for the compressed video. | same folder as the input video's |
|`-cv` | The video encoder used for compression (e.g. `libx264`, `libsvtav1`). Available encoders are listed in the [Encoders.md](/docs/Encoders.md) documentation file. | `libx265` |
|`-cvpreset`| Preset for the selected video encoder. Preset naming schemes may be different between encoders, see [Encoders.md](/docs/Encoders.md). | `medium` for `libx265` (depends on encoder) |
|`-ca`| The audio encoder used for compression (either `aac` or `libopus`).| `libopus` |
|`-bra` | The target audio bitrate in kbps. The input file's audio bitrate will instead be used if it's lower than the target bitrate, and by default, the input file's audio will be copied to the output file without re-encoding. | `128` |

## Examples of Usage
| Example command | Explanation |
|---|---|
|C:\path\to\script\ff2ppress.ps1 -i "C:\Users\Mot\Videos\BLUE PRINCE.mp4" | Compress the input video with the default settings to the default size (20 MiB)|
|.\ff2ppress.ps1 -i "C:\Users\mot\Desktop\Overwatch.mp4" -s 50 -cv libx264 | Compresses the input video to 50 MiB with the selected video encoder|
|ff2ppress -i "C:\Users\mot\Desktop\drive.mp4" -cv libsvtav1 -cvpreset 7  | Change the default video encoder and use a different preset compatible with it|