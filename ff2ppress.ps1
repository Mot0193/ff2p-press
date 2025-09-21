param(
    [Alias("i")]
    $video, 

    [Alias("s")]
    $MiBdesiredsize,

    [Alias("o")]
    $outputfolder, # output folder. Defaults to outputting in the same folder as the input video

    [Alias("cv")]
    $videocodec = "libx265", # other available codecs: hevc_nvenc, libx254, libaom-av1
    [Alias("cvpreset")]
    $videocodecpreset = "medium", # defaults automatically on: hevc_nvenc - p7, libx254 - medium, libaom-av1 - 8 (this is for the "cpu-used" argument)
    [Alias("h")]
    $videoheight = -1,
    [Alias("w")]
    $videowidth = -1,
    [Alias("brlow")]
    $brpercentagelowering = 0, # a percentage of how much the final target video bitrate should be lowered. For example if the final target bitrate would be 1000 kbps but its lowered 5%, the bitrate will be 950kbps instead.

    [Alias("ca")]
    $audiocodec = "libopus", # other available codecs: acc
    $audiobitrate = "128", # Or the input video's bit rate, whichever is lower

    $fancyrename = $true, # pass "0" for false when changing this. Disables codec information in the output file name (e.g resulting videos will only be named "compressed_<video_name>")
    $cleanlogs = $true
)

$MiBstartingsize = (Get-Item -Path $video).Length/1MB
if ($MiBstartingsize -le $MiBdesiredsize){
    Write-Host "Error: target size cant be higher than the video's current size ($MiBstartingsize)"
    exit
}
$duration = [math]::Round([int](ffprobe -v error -select_streams a:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 $video))

[int]$kbit_desiredsize = [int]$MiBdesiredsize * 8388.608
$kbps_startingaudioBitrate = [math]::Round([int](ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 $video) / 1000)

if (($kbps_startingaudioBitrate -le [int]$audiobitrate) -and $kbps_startingaudioBitrate){
    Write-Host "Audio bitrate of the given video is lower than the target bitrate. Using $kbps_startingaudioBitrate`kbps instead of $audiobitrate`kbps"
    $audiobitrate = $kbps_startingaudioBitrate
}

[int]$kbit_audiosize = [int]$audiobitrate * $duration # the aproximate size of the whole audio
if (($kbit_audiosize / $kbit_desiredsize) -gt 0.2){
    Write-Host "Audio size would be over 20% of the target size. Re-calculating audio bitrate so audio will take up 20% of the file..."
    # In normal use cases this will hopefully never happen, but with very long videos that are set to very low target sizes this can become an issue.
    $audiobitrate = 0.2 * $kbit_desiredsize / $duration
    $kbit_audiosize = [int]$audiobitrate * $duration
}


Write-Host "Video duration (sec): $duration"
Write-Host "Video starting size (MiB): $MiBstartingsize"
Write-Host "=== === ==="
Write-Host "Target file size (kbit): $kbit_desiredsize"
Write-Host "Target total audio size (kbit): $kbit_audiosize"
Write-Host "=== === ==="
Write-Host "Initial target video bitrate (kbps): $($kbit_desiredsize / $duration)"
Write-Host "Target audio bitrate (kbps): $audiobitrate"

$videoTargetkbps = ($kbit_desiredsize - $kbit_audiosize) / $duration # the bitrate for the video would be the targeted size - aproximate audio size - 0.5 MiB~ for a little headroom/metadata, all divided by the duration 
if ($brpercentagelowering -gt 0){
    $videoTargetkbps = $videoTargetkbps * (1 - ($brpercentagelowering / 100))
    Write-Host "Bitrate lowering percentage: $brpercentagelowering%"
}
Write-Host "Final target video Bitrate: $videoTargetkbps kbps"
Write-Host "=== === ==="

# settings/arguments for each codec
if ($videocodec -eq "libx265"){ 
    $ffvideoargsP1 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-preset", "$videocodecpreset"
        "-x265-params", "pass=1:log-level=1"
    )
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-preset", "$videocodecpreset"
        "-x265-params", "pass=2:log-level=1"
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
    Write-Host "libaom-av1 Info! On the 1st pass the progress bar/info may appear to be stuck, but the video will still encode. This seems to be just a bug. After the 1st pass is done you may see `"Output file is empty, nothing was encoded`". This shouldnt mean anything, double pass should still work as intended."
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
        "-cpu-used", "$videocodecpreset",
        "-row-mt", "1"
    )
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$videoTargetkbps`k",
        "-pass", "2",
        "-cpu-used", "$videocodecpreset",
        "-row-mt", "1"
    )
} else {
    Write-Host "Error: Unkown/Unavailable video codec. Check the available codecs in readme"
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
    Write-Host "Error: Unkown/Unavailable audio codec. Check the available codecs in readme"
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

if ($cleanlogs -eq 1){
    $ffloglevel = @(
        "-loglevel", "error",
        "-stats"
    )
} else {
    $ffloglevel = @()
}

if ($fancyrename){
    $outputfilename = "compressed_$($MiBdesiredsize)mib_$([IO.Path]::GetFileNameWithoutExtension($video))_$($videocodec)_$($videocodecpreset).mp4"
} else {
    $outputfilename = "compressed_$([IO.Path]::GetFileNameWithoutExtension($video)).mp4"
}

if (!$outputfolder){
    $videoFullPath = Resolve-Path -Path $video
    $finaloutputpath = "$(Split-Path -Path $videoFullPath)\$outputfilename"
} elseif (Test-Path -Path $outputfolder) {
    $finaloutputpath = "$outputfolder\$outputfilename"
} else {
    Write-Host "Error: Output folder is invalid or doesnt exist!"
    exit
}
Write-Host "Output file path: $finaloutputpath"

$starttime = Get-Date

if (-not($videocodec -eq "hevc_nvenc")){
    Write-Host "=== === Start 1st pass === ==="
    # Write-Host "ffmpeg -hide_banner $ffvideoargsP1 $ffloglevel $ffrescaleargs $ffbitratelimitargs $ffvideonullargsP1"
    & ffmpeg -hide_banner @ffvideoargsP1 @ffloglevel @ffrescaleargs @ffbitratelimitargs @ffvideonullargsP1
}

Write-Host "=== === Start final pass === ==="
# Write-Host "ffmpeg -hide_banner $ffvideoargsP2 $ffloglevel $ffrescaleargs $ffbitratelimitargs $ffaudioargs $finaloutputpath"
& ffmpeg -hide_banner @ffvideoargsP2 @ffloglevel @ffrescaleargs @ffbitratelimitargs @ffaudioargs $finaloutputpath

$endtime = Get-Date
$elapsedtime = ([math]::Round(($endtime - $starttime).TotalSeconds, 2))
Write-Host "Encoding took $elapsedtime seconds in total"

Remove-Item ".\x265_2pass.log*" -Force -ErrorAction SilentlyContinue # deletes x265 log files
Remove-Item ".\ffmpeg2pass-0.log*" -Force -ErrorAction SilentlyContinue # deletes other 2pass ffmpeg log files

$MiBresultsize = (Get-Item -Path $finaloutputpath).Length/1MB
if ($MiBresultsize -ge $MiBdesiredsize){
    Write-Host "Warning! Resulting file size ($MiBresultsize MiB) is over the target size."
    Write-Host "Try decreasing the file size target, using -lowbr to lower the bitrate, or decreasing output resolution"
    Write-Host "Size difference (result - target): $($MiBresultsize - $MiBdesiredsize) MiB"
}

Write-Host "=== === === Video Done! === === ==="