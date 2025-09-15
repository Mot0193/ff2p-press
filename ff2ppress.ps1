# This script compresses videos with various video codecs and settings, using ffmpeg with double-pass encoding (with some exceptions, such as with libaom-av1)
# The default options (when no extra arguments are given other than the input file and file size) are the video codec libx265 with the medium preset, and the audio codec libopus at 128kbps bitrate.
# Videos will get output to Desktop with the names starting with "compressed_" and ending with the codec used e.g "_libx265".

# Codec option/usage tips

# --- libx265 (hevc/H265) ---
# This is the default. H265 is a good codec overall, with quality slightly worse than AV1. Double passing with a preset over medium might not be worth it, considering libaom-av1 could get higher quality in less time with its slowest preset.
# libx265 supports these presets: https://x265.readthedocs.io/en/master/presets.html (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo)
# Default preset is "medium"

# --- hevc_nvenc (hevc/H265 hardware accelerated for Nvidia GPUs) ---
# In general all hardware accelerated codecs provide worse quality than their software (cpu) versions (in this case compared to libx265). But they are A LOT faster even at the highest quality/preset settings, but even at their highest presets they cant usually beat a good softare encoder. 
# For this reason i wouldnt go below the max preset for nvenc, and some options are complately hardcoded with the use of a high quality preset in mind (for example enabling double pass with the full resolution. Normally lower presets might disable this)
# hevc_nvenc supports some weird presents, but the main ones are: p1, p2, p3, ... p7. higher values provide higher quality. To see all presets run "ffmpeg -h encoder=hevc_nvenc"
# Default preset is "p7"
# CBR (Constant bitrate) is also enabled for this codec, as i found better results with more stable file sizes.

# --- libaom-av1 (av1) ----
# This is av1 software encoding. VERY slow, but considered the best. Because of its mind-numbing speed, i consider going under the preset 8 to be brave (this is actually the "cpu-used" argument, not really a "preset"). Double pass is also disabled.
# But, even at the fastest preset (8) with just one pass, it can achieve great results, even better and faster compared to libx265 at the slow preset. This is just from my very limited testing, though.
# libaom-av1 supports these "cpu-used" values as "presets": https://ffmpeg.org/ffmpeg-codecs.html#libaom_002dav1 (0, 1, ... 8) 0 being the slowest while 8 the fastest. For reference, the library defaults to 1.
# Default preset is "8"

# --- Examples of parameter usage ---
# -i "C:\Users\mot\Desktop\Overwatch_28.08.2025_21-18-54.mp4" -s 30
# -s 50 -i "C:\Users\mot\Desktop\drive.mp4" -cv libaom-av1
# -i "C:\Users\mot\Desktop\Overwatch_28.08.2025_21-18-54.mp4" -s 10 -cv hevc_nvenc 

param(
    [Alias("i")]
    $video, 

    [Alias("s")]
    $MiBdesiredsize, 

    [Alias("cv")]
    $videocodec = "libx265", # other available codecs: hevc_nvenc, libaom-av1
    $videocodecpreset = "medium", # defaults automatically on: hevc_nvenc - p7, libaom-av1 - 8 (this is for the "cpu-used" argument)

    [Alias("ca")]
    $audiocodec = "libopus", # other available codecs: acc
    $audiobitrate = "128"
)
$kbit_desiredsize = $MiBdesiredsize * 8388.608

$player = New-Object -ComObject WMPlayer.OCX
$duration = [math]::Round($player.newMedia($video).duration)

Write-Host "Video duration (sec): $duration"
$kbit_audiosize = [int]$audiobitrate * $duration # the aproximate size of the whole audio
$videoTargetkbps = ($kbit_desiredsize - $kbit_audiosize - 5871) / $duration # the bitrate for the video would be the targeted size - aproximate audio size -0.7 MiB~ for a little headroom/metadata, divided by the duration
Write-Host "Traget Bitrate: $videoTargetkbps kbps"

# settings/arguments for each codec
if ($videocodec -eq "libx265"){ 
    $ffvideoargsP1 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-preset", "$videocodecpreset"
        "-x265-params", "pass=1",
        "-an",
        "-f", "null", "NUL"
    )
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-preset", "$videocodecpreset"
        "-x265-params", "pass=2"
    )
} elseif ($videocodec -eq "hevc_nvenc"){
    if (-not ($videocodecpreset -in "p1","p2","p3","p4","p5","p6","p7")){
        Write-Host "Preset `"$videocodecpreset`" does not match for an nvenc preset, defaulting to preset `"p7`" for nvenc (this is the highest preset)"
        $videocodecpreset = "p7"
    }
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-preset", "$videocodecpreset",
        "-rc", "cbr",
        "-tune", "hq",
        "-multipass", "fullres"
    )
} elseif ($videocodec -eq "libaom-av1"){
    Write-Host "Warning! Codec libaom-av1 runs very slow, even with the highest speed `"preset`", for this reason this codec doesnt do multiple passes, though it outputs pretty good videos with just one pass."
    if (-not ($videocodecpreset -in "0","1","2","3","4","5","6","7","8")){
        Write-Host "Preset `"$videocodecpreset`" does not match for an libaom-av1 `"cpu-used`" value, defaulting to cpu-used `"8`" for libaom-av1 (fastest setting)"
        $videocodecpreset = "8"
    }
    if ($videocodecpreset -in "0","1","2","3"){
        Write-Host "!!! WARNING !!! - Low libaom-av1 presets/`"cpu-used`" values makes the codec run EXTREMELY slow. Consider increasing this."
        Start-Sleep -Seconds 5
    }

    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-cpu-used", "$videocodecpreset"
    )
} else {
    Write-Host "Unkown/Unavailable video codec. Check the available codecs in the script's code comments"
    exit
}

if ($audiocodec -in "libopus", "acc"){
    $ffaudioargs = @(
        "-c:a", $audiocodec,
        "-b:a", "$audiobitrate`k"
    )
} else {
    Write-Host "Unkown/Unavailable audio codec. Check the available codecs in the script's code comments"
    exit
}

if ($videocodec -in "libx265"){
    Write-Host "ffmpeg $($ffvideoargsP1 -join ' ')"
    & ffmpeg @ffvideoargsP1
}

Write-Host "ffmpeg $($ffvideoargsP2 + $ffaudioargs -join ' ') $env:USERPROFILE\Desktop\compressed_$([IO.Path]::GetFileNameWithoutExtension($video))_$($videocodec).mp4"
& ffmpeg @ffvideoargsP2 @ffaudioargs "$env:USERPROFILE\Desktop\compressed_$([IO.Path]::GetFileNameWithoutExtension($video))_$($videocodec).mp4"