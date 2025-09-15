param(
    [Alias("i")]
    $video, 

    [Alias("s")]
    $MiBdesiredsize, 

    [Alias("cv")]
    $videocodec = "libx265", # other available codecs: hevc_nvenc, libaom-av1
    [Alias("cvpreset")]
    $videocodecpreset = "medium", # defaults automatically on: hevc_nvenc - p7, libaom-av1 - 8 (this is for the "cpu-used" argument)
    [Alias("h")]
    $videoheight = -1,
    [Alias("w")]
    $videowidth = -1,

    [Alias("ca")]
    $audiocodec = "libopus", # other available codecs: acc
    $audiobitrate = "128" # Or the input video's bit rate, whichever is lower
)

$MiBstartingsize = (Get-Item -Path $video).Length/1MB
if ($MiBstartingsize -le $MiBdesiredsize){
    Write-Host "Sorry, target size cant be higher than the video's current size"
    exit
}
$kbit_desiredsize = $MiBdesiredsize * 8388.608
$kbps_startingaudioBitrate = [math]::Round([int](ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 $video) / 1000)

if ($kbps_startingaudioBitrate -le [int]$audiobitrate){
    Write-Host "Audio bitrate of the given video is lower than the target bitrate. Using $kbps_startingaudioBitrate`kbps instead of $audiobitrate`kbps"
    $audiobitrate = $kbps_startingaudioBitrate
}

$player = New-Object -ComObject WMPlayer.OCX
$duration = [math]::Round($player.newMedia($video).duration)

Write-Host "Video duration (sec): $duration"
Write-Host "Video starting size (MiB): $MiBstartingsize"
Write-Host "Initial target bitrate (kib): $($kbit_desiredsize / $duration)"

$kbit_audiosize = [int]$audiobitrate * $duration # the aproximate size of the whole audio
$videoTargetkbps = ($kbit_desiredsize - $kbit_audiosize - 4194) / $duration # the bitrate for the video would be the targeted size - aproximate audio size - 0.5 MiB~ for a little headroom/metadata - lowfilesizeratioovershootprevention, all divided by the duration 
Write-Host "Final Target Bitrate: $videoTargetkbps kbps"

# settings/arguments for each codec
if ($videocodec -eq "libx265"){ 
    $ffvideoargsP1 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-preset", "$videocodecpreset"
        "-x265-params", "pass=1"
    )
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-preset", "$videocodecpreset"
        "-x265-params", "pass=2:log-level=1" #set log level to 1 so it doesnt show the same info as the 1st pass
    )
} elseif ($videocodec -eq "hevc_nvenc"){
    if (-not ($videocodecpreset -in "p1","p2","p3","p4","p5","p6","p7")){
        Write-Host "Preset `"$videocodecpreset`" does not match for a nvenc preset, defaulting to preset `"p7`" for nvenc (this is the highest preset)"
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
} elseif ($videocodec -eq "libx264"){
    $ffvideoargsP1 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-preset", "$videocodecpreset"
        "-pass", "1"
    )
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-preset", "$videocodecpreset"
        "-pass", "2"
    )
} elseif ($videocodec -eq "libaom-av1"){
    Write-Host "libaom-av1 Info! This codec runs very slow, even with the highest speed/`"preset`". Have patience if you want to see results"
    Write-Host "libaom-av1 Info! On the 1st pass the progress bar/info may appear to be stuck, but its not. This could be just a bug. After the 1st pass is done you may see `"Output file is empty, nothing was encoded`". This shouldnt mean anything, double pass should still work as intended."
    if (-not ($videocodecpreset -in "0","1","2","3","4","5","6","7","8")){
        Write-Host "Preset `"$videocodecpreset`" does not match for a libaom-av1 `"cpu-used`" value, defaulting to cpu-used `"8`" for libaom-av1 (fastest setting)"
        $videocodecpreset = "8"
    }
    if ($videocodecpreset -in "0","1","2","3"){
        Write-Host "!!! WARNING !!! - Low libaom-av1 presets/`"cpu-used`" values makes the codec run EXTREMELY slow. Consider increasing this."
        Start-Sleep -Seconds 5
    }

    $ffvideoargsP1 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-pass", "1",
        "-cpu-used", "$videocodecpreset"
    )
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-pass", "2",
        "-cpu-used", "$videocodecpreset"
    )
} else {
    Write-Host "Unkown/Unavailable video codec. Check the available codecs in readme"
    exit
}
$ffvideonullargsP1 = @(
    "-an",
    "-f", "null", "NUL"    
)

if ($audiocodec -in "libopus", "acc"){
    $ffaudioargs = @(
        "-c:a", $audiocodec,
        "-b:a", "$audiobitrate`k"
    )
} else {
    Write-Host "Unkown/Unavailable audio codec. Check the available codecs in readme"
    exit
}

if (($videoheight -ne -1) -or ($videowidth -ne -1)){
    Write-Host "Rescaling the video to $videowidth`:$videoheight (width:height)"
    $ffrescaleargs = @(
        "-vf", "scale=$([int]$videowidth)`:$([int]$videoheight)"
    )
} else {
    $ffrescaleargs = @()
}

$starttime = Get-Date

if (-not($videocodec -eq "hevc_nvenc")){
    Write-Host "=== Start 1st pass ==="
    & ffmpeg -hide_banner @ffvideoargsP1 @ffrescaleargs @ffvideonullargsP1
}

Write-Host "=== Start final pass ==="
& ffmpeg -hide_banner @ffvideoargsP2 @ffrescaleargs @ffaudioargs "$env:USERPROFILE\Desktop\compressed_$([IO.Path]::GetFileNameWithoutExtension($video))_$($videocodec)_$($videocodecpreset).mp4"

$endtime = Get-Date
$elapsedtime = ([math]::Round(($endtime - $starttime).TotalSeconds, 2))
Write-Host "Encoding took $elapsedtime seconds in total"


Remove-Item ".\x265_2pass.log*" -Force -ErrorAction SilentlyContinue # deletes x265 log files
Remove-Item ".\ffmpeg2pass-0.log*" -Force -ErrorAction SilentlyContinue # deletes other 2pass ffmpeg log files