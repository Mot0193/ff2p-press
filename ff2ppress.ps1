param(
    [Alias("i")]
    $video, 

    [Alias("s")]
    $TargetVideoSize_MiB, # set a target size in MiB

    [Alias("o")]
    $outputfolder, # output folder. Defaults to outputting in the same folder as the input video

    [Alias("cv")]
    $videocodec = "libx265", # other available codecs: hevc_nvenc, libx264, h264_nvenc, libsvtav1, libaom-av1
    [Alias("cvpreset")]
    $videocodecpreset = "medium", # defaults automatically on: hevc_nvenc - p7, libx264 - medium, h264_nvenc - p7, libsvtav1 - 5, libaom-av1 - 8
    [Alias("h")]
    $videoheight = -1, # set a video Height or Width (-h / -w) in pixels to rescale the output video. You can just use one of these and the other side will get automatically scaled to keep the same aspect ratio (e.g -h 1080). The deafult values (-1) do not rescale the video
    [Alias("w")]
    $videowidth = -1,
    [Alias("brv")] 
    $TargetVideoBitrate_kbps, # can be used instead of -s or -brlow to manually set a bitrate in kbps (e.g -brv 1000)
    [Alias("brlow")]
    $BitratePercentageLow = 0, # a percentage of how much the final target video bitrate should be lowered. For example if the final target bitrate would be 1000 kbps but its lowered 5%, the bitrate will be 950kbps instead. 
    # This can be used without setting a target size (-s) to instead lower the input video's bitrate by the percentage and using that as the target. In practice this is almost the equivalent of lowering the file size by a percentage

    [Alias("ca")]
    $audiocodec = "libopus", # other available codecs: acc
    [Alias("bra")]
    $TargetAudioBitrate_kbps = "128", # Or the input video's bit rate, whichever is lower

    [Alias("args")] # pass extra, codec-specific arguments to ffmpeg. For example using "-args lp=2" will pass "-<codec>-params lp=2" to ffmpeg. In this case "lp" is used with libsvtav1, so "-svtav1-params lp=2" will get passed to ffmpeg. Multiple parameters can be added if theyre colon seperated (e.g lp=2:pin=4)
    $extraarguments,

    $fancyrename = $true, # pass "0" for false when changing. Disables codec information in the output file name (e.g resulting videos will only be named "compressed_<video_name>")
    $cleanlogs = $true, # if disabled (0), this removes the "-loglevel error" and "-stats" arguments from ffmpeg, giving you more information about the video
    [Alias("svtav1app")]
    $isSvtav1encappAvailable = $true # disable to manually force 1-pass mode for svt-av1. If its left true by default, the script will auto-detect if svtav1encapp is available, and enable/disable 2pass for the codec accordingly
)

$StartingVideoSize_MiB = (Get-Item -Path $video).Length/1MB
if (-not($StartingVideoSize_MiB -eq "0") -and ($StartingVideoSize_MiB -le $TargetVideoSize_MiB)){
    Write-Host "Error: target size cant be higher than the video's current size ($StartingVideoSize_MiB)"
    exit
}

# ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1
$VideoDuration_sec = ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $video
$StartingVideoBitrate_kbps = ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 $video
$StartingAudioBitrate_kbps = (ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 $video) / 1000
if (-not $StartingAudioBitrate_kbps){
    Write-Host "Failed to (easily) get the audio bitrate of the video. Letting ffmpeg interpret audio bitrate (may not be accurate)"
    [int]$StartingAudioSize_KiB = (ffmpeg -i $video -map 0:a:0 -c copy -f null NUL 2>&1 | Out-String -Stream | Select-String -Pattern 'audio:(\d+)KiB').Matches[0].Groups[1].Value
    $StartingAudioBitrate_kbps = ($StartingAudioSize_KiB * 8.192) / $VideoDuration_sec
}


if (($StartingAudioBitrate_kbps -le [int]$TargetAudioBitrate_kbps) -and $StartingAudioBitrate_kbps){
    Write-Host "Audio bitrate of the input video is lower than the target bitrate. Using $StartingAudioBitrate_kbps`kbps instead of $TargetAudioBitrate_kbps`kbps"
    $TargetAudioBitrate_kbps = $StartingAudioBitrate_kbps
}

if ($TargetVideoSize_MiB){ # TODO Rename EVERYTHING what the fuck are these variable names
    [float]$TargetVideoSize_kbit = [float]$TargetVideoSize_MiB * 8388.608
    [float]$TargetAudioSize_kbit = [float]$TargetAudioBitrate_kbps * $VideoDuration_sec # the aproximate size of the whole audio
    [float]$TargetVideoBitrate_kbps = ($TargetVideoSize_kbit - $TargetAudioSize_kbit) / $VideoDuration_sec # the bitrate for the video would be the targeted size - aproximate audio size, all divided by the duration 

    if (($TargetAudioSize_kbit / $TargetVideoSize_kbit) -gt 0.2){
        Write-Host "Audio size would be over 20% of the target size. Re-calculating audio bitrate so audio will take up 20% of the file..."
        # In normal use cases this will hopefully never happen, but with very long videos that are set to very low target sizes this can become an issue.
        $TargetAudioBitrate_kbps = 0.2 * $TargetVideoSize_kbit / $VideoDuration_sec
        $TargetAudioSize_kbit = [float]$TargetAudioBitrate_kbps * $VideoDuration_sec
    }

    $TargetVideoBitrate_kbps = ($TargetVideoSize_kbit - $TargetAudioSize_kbit) / $VideoDuration_sec # the bitrate for the video would be the targeted size - aproximate audio size, all divided by the duration

    if ($BitratePercentageLow -gt 0){
        $TargetVideoBitrate_kbps = $TargetVideoBitrate_kbps * (1 - ($BitratePercentageLow / 100))
    }
} elseif ($BitratePercentageLow -gt 0) {
    $StartingVideoBitrate_bps = (ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 $video) / 1000
    Write-Host "Target size was not given, using bitrate lowering percentage on the input video's bitrate ($StartingVideoBitrate_bps kbps) instead"
    $TargetVideoBitrate_kbps = $StartingVideoBitrate_bps * (1 - ($BitratePercentageLow / 100))
} elseif ($TargetVideoBitrate_kbps -le 0){
    Write-Host "Error: Target bitrate is not valid (not set or not > 0)"
}

Write-Host "=== === ==="
Write-Host ("Starting Video Duration / Size / Bitrate    : {0:F2} sec / {1:F2} MiB / {2:F2} kbps" -f [float]$VideoDuration_sec, $StartingVideoSize_MiB, $([float]$StartingVideoBitrate_kbps * 0.0009765625))
Write-Host ("Starting Audio Bitrate                      : {0:F2} kbps" -f $StartingAudioBitrate_kbps)
if ($BitratePercentageLow -gt 0) { 
Write-Host ("Target Video Size / Bitrate / Low%          : {0} MiB / {1:F2} kbps / {2}%" -f $TargetVideoSize_MiB, $TargetVideoBitrate_kbps, $BitratePercentageLow)}
else {
Write-Host ("Target Video Size / Bitrate                 : {0} MiB / {1:F2} kbps" -f $TargetVideoSize_MiB, $TargetVideoBitrate_kbps)
}
Write-Host ("Target Audio Bitrate                        : {0:F2} kbps" -f $TargetAudioBitrate_kbps)
Write-Host "=== === ==="

# settings/arguments for each codec
if ($videocodec -eq "libx265"){ 
    $ffvideoargsP1 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$TargetVideoBitrate_kbps`k",
        "-preset", "$videocodecpreset"
        "-x265-params", "pass=1:log-level=1"
    )
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$TargetVideoBitrate_kbps`k",
        "-preset", "$videocodecpreset"
        "-x265-params", "pass=2:log-level=1"
    )
} elseif ($videocodec -eq "libx264"){
    $ffvideoargsP1 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$TargetVideoBitrate_kbps`k",
        "-preset", "$videocodecpreset"
        "-pass", "1"
    )
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$TargetVideoBitrate_kbps`k",
        "-preset", "$videocodecpreset"
        "-pass", "2"
    )
} elseif ($videocodec -eq "hevc_nvenc"){
    if (-not ($videocodecpreset -in "p1","p2","p3","p4","p5","p6","p7")){
        Write-Host "Preset `"$videocodecpreset`" does not match for a nvenc preset, defaulting to preset `"p7`" for nvenc (this is the highest preset)"
        $videocodecpreset = "p7"
    }
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$TargetVideoBitrate_kbps`k",
        "-preset", "$videocodecpreset",
        "-rc", "cbr",
        "-tune", "hq",
        "-multipass", "fullres"
    )
} elseif ($videocodec -eq "h264_nvenc"){
    if (-not ($videocodecpreset -in "p1","p2","p3","p4","p5","p6","p7")){
        Write-Host "Preset `"$videocodecpreset`" does not match for a nvenc preset, defaulting to preset `"p7`" for nvenc (this is the highest preset)"
        $videocodecpreset = "p7"
    }
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$TargetVideoBitrate_kbps`k",
        "-preset", "$videocodecpreset",
        "-rc", "cbr",
        "-tune", "hq",
        "-multipass", "fullres"
    )
} elseif ($videocodec -eq "libaom-av1"){
    Write-Host "libaom-av1 Info! On the 1st pass the progress bar/info may appear to be stuck, but the pass will still complete. Have patiance"
    if ($videocodecpreset -notin (0..8)){
        Write-Host "Preset `"$videocodecpreset`" does not match for a libaom-av1 `"cpu-used`" value, defaulting to cpu-used `"8`" for libaom-av1 (fastest setting)"
        $videocodecpreset = "8"
    }

    $ffvideoargsP1 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$TargetVideoBitrate_kbps`k",
        "-pass", "1",
        "-cpu-used", "$videocodecpreset",
        "-row-mt", "1"
    )
    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$TargetVideoBitrate_kbps`k",
        "-pass", "2",
        "-cpu-used", "$videocodecpreset",
        "-row-mt", "1"
    )
} elseif ($videocodec -eq "libsvtav1"){
    Write-Host "!!! WARNING !!! SVT-AV1 does not support 2-pass mode with ffmpeg. If you have SvtAv1EncApp added to path, the script will attempt to use it in conjunction with ffmpeg to handle 2-pass encoding. If it cant find SvtAv1EncApp, the script will just do 1-pass, which may overshoot the file target size or provide worse video quality"
    
    if ($isSvtav1encappAvailable -eq $true ) { $isSvtav1encappAvailable = [bool](Get-Command -ErrorAction Ignore -Type Application SvtAv1EncApp) }
    if ($isSvtav1encappAvailable -eq $false) { Write-Host "Warning: SvtAv1EncApp not found/disabled. Using SVT-AV1 in 1-pass mode" }

    if ($videocodecpreset -notin (-1..13)){
        Write-Host "Preset `"$videocodecpreset`" does not match for a libsvtav1 preset. Defaulting to prest `"5`""
        $videocodecpreset = "5"
    }

    $ffvideoargsP1 = @(
        "-i", $video,
        "-an", 
        "-f", "rawvideo",
        "-"
    )

    $StartingVideoHeight = ffprobe -v error -select_streams v:0 -show_entries stream=coded_height -of default=noprint_wrappers=1:nokey=1 $video
    $StartingVideoWidth = ffprobe -v error -select_streams v:0 -show_entries stream=coded_width -of default=noprint_wrappers=1:nokey=1 $video
    $StartingVideoPixFmt = ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 $video
    if ($StartingVideoPixFmt -eq "yuv420p10le"){
        $TargetVideoBitDepth = 10
    } else { $TargetVideoBitDepth = 8 }

    $svtencappVideoargsP1 = @(
        "-i", "stdin",
        "-w", $StartingVideoWidth,
        "-h", $StartingVideoHeight,
        "--rc", "1",
        "--tbr", $TargetVideoBitrate_kbps,
        "--preset", $videocodecpreset,
        "--input-depth", $TargetVideoBitDepth,
        "--stats", "SvtAv1EncApp_2pass.log"
    )

    if ($extraarguments){
        $Parameters = $extraarguments -split ':' |
        ForEach-Object {
            $name, $value = $_ -split '=', 2
            "--$name", $value
        }
    }

    $ffvideoargsP2 = @(
        "-i", $video,
        "-c:v", $videocodec,
        "-b:v", "$TargetVideoBitrate_kbps`k",
        "-preset", "$videocodecpreset"
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
        "-b:a", "$TargetAudioBitrate_kbps`k"
    )
} else {
    Write-Host "Error: Unkown/Unavailable audio codec. Check the available codecs in readme"
    exit
}

if (($videoheight -ne -1) -or ($videowidth -ne -1)){
    Write-Host "Rescaling the video to $videowidth`:$videoheight (width:height)"
    $ffrescaleargs = @(
        "-vf", "scale=$([int]$videowidth)`:$([int]$videoheight)",
        "-sws_flags", "lanczos" # enable lanczos downscale filter for high quality scaling
    )
} else {
    $ffrescaleargs = @()
}

if (($extraarguments)){
    if($videocodec -eq "libaom-av1"){
        $codecparam = "aom" # why did they do this, it should have been aom-av1-params just like svtav1-params
    } else {
        $codecparam = $videocodec.Substring(3) # literally just cut the first 3 letters of the codec, since its gonna be "lib". NVENC does not have a -params option, but that should be obvious to the knowledgeable user so i wont bother checking for it
    }

    $ffextraargs = @(
        "-$codecparam-params", "$extraarguments"
    )
} else {
    $ffextraargs = @()
}

if ($cleanlogs -eq 1){
    $ffloglevel = @(
        "-loglevel", "error",
        "-stats"
    )
} else {
    $ffloglevel = @()
}

if ($fancyrename){ # I just realized im converting all files to MP4, regardless of their original file extension. Meh whatever mp4 is good enough
    if ($TargetVideoSize_MiB){ $outputfilename = "compressed_$($TargetVideoSize_MiB)mib_$([IO.Path]::GetFileNameWithoutExtension($video))_$($videocodec)_$($videocodecpreset).mp4" }
    else { $outputfilename = "compressed_$([IO.Path]::GetFileNameWithoutExtension($video))_$($videocodec)_$($videocodecpreset).mp4" }
} else {
    $outputfilename = "compressed_$([IO.Path]::GetFileNameWithoutExtension($video)).mp4"
}

if (!$outputfolder){
    $videoFullPath = Resolve-Path -Path $video
    $finaloutputpath = "$(Split-Path -Path $videoFullPath)\$outputfilename"
    $svtav1OutputTempPath = "$(Split-Path -Path $videoFullPath)\SvtAv1EncApp_Temp_$([IO.Path]::GetFileNameWithoutExtension($video)).mp4"
} elseif (Test-Path -Path $outputfolder) {
    $finaloutputpath = "$outputfolder\$outputfilename"
    $svtav1OutputTempPath = "$outputfolder\SvtAv1EncApp_Temp_$([IO.Path]::GetFileNameWithoutExtension($video)).mp4"
} else {
    Write-Host "Error: Output folder is invalid or doesnt exist!" 
    exit
}
Write-Host "Output file path: $finaloutputpath"

# --- Start Encoding ---
$starttime = Get-Date

if (($videocodec -eq "libsvtav1") -and ($isSvtav1encappAvailable -eq $true)){
    Write-Host "=== === Start 1st pass === ==="
    ffmpeg -hide_banner @ffloglevel @ffvideoargsP1 | SvtAv1EncApp --progress 0 --pass 1 @svtencappVideoargsP1 @Parameters
    Write-Host "=== === Start final pass === ==="
    ffmpeg -hide_banner @ffloglevel @ffvideoargsP1 | SvtAv1EncApp --progress 0 --pass 2 @svtencappVideoargsP1 @Parameters -b $svtav1OutputTempPath
    Write-Host "=== Encoding Audio ==="
    ffmpeg -hide_banner @ffloglevel -y -i $svtav1OutputTempPath -i $video -map 0:v? -map 1:a? -c:v copy @ffaudioargs $finaloutputpath # seperately encode the audio by mapping the audio from the original video and the video from the newly compressed file
    Remove-Item $svtav1OutputTempPath -Force -ErrorAction SilentlyContinue
} else {
    if (-not($videocodec -in "hevc_nvenc", "h264_nvenc", "libsvtav1")){
        Write-Host "=== === Start 1st pass === ==="
        & ffmpeg -hide_banner @ffvideoargsP1 @ffloglevel @ffrescaleargs @ffextraargs @ffvideonullargsP1
    }

    Write-Host "=== === Start final pass === ==="
    & ffmpeg -hide_banner @ffvideoargsP2 @ffloglevel @ffrescaleargs @ffextraargs @ffaudioargs $finaloutputpath
}


$endtime = Get-Date
$elapsedtime = ([math]::Round(($endtime - $starttime).TotalSeconds, 2))
Write-Host "Encoding took $elapsedtime seconds in total ($($elapsedtime / 60) minutes)"

Remove-Item ".\x265_2pass.log*" -Force -ErrorAction SilentlyContinue # deletes x265 log files
Remove-Item ".\ffmpeg2pass-0.log*" -Force -ErrorAction SilentlyContinue # deletes other 2pass ffmpeg log files
Remove-Item ".\SvtAv1EncApp_2pass.log*" -Force -ErrorAction SilentlyContinue 

$MiBresultsize = (Get-Item -Path $finaloutputpath).Length/1MB
if ($TargetVideoSize_MiB -and ($MiBresultsize -ge $TargetVideoSize_MiB)){
    Write-Host "Warning! Resulting file size ($MiBresultsize MiB) is over the target size."
    Write-Host "Try decreasing the file size target, using -lowbr to lower the bitrate, or decreasing output resolution"
    Write-Host "Size difference (result - target): $($MiBresultsize - $TargetVideoSize_MiB) MiB"
    Write-Host "Recommended size to retry with (target - Size difference): $($TargetVideoSize_MiB - ($MiBresultsize - $TargetVideoSize_MiB)) MiB"
}

Write-Host "=== === === Video Done! === === ==="