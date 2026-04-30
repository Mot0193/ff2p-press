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
    $inputTargetVideoHeight = -1, # set a video Height or Width (-h / -w) in pixels to rescale the output video. You can just use one of these and the other side will get automatically scaled to keep the same aspect ratio (e.g -h 1080). The deafult values (-1) do not rescale the video
    [Alias("w")]
    $inputTargetVideoWidth = -1,
    [Alias("trim")]
    $TargetVideoTrim = -1, # optionally trim the video. This uses ffmpeg's -ss and -to. Timestamps use the format "HH:MM:SS", seperate starting time and end time with "-". Target bitrate will be correctly calculated based on the duration of the trim. Example usage: "-trim 0:0:0-0:5:0" (trim video from the start to the 5th minute); "-trim 0:2:20-0:4:10" (trim video from 2mins 20sec to 4min 10sec). 
    [Alias("brv")] 
    $TargetVideoBitrate_kbps, # can be used instead of -s or -brlow to manually set a bitrate in kbps (e.g -brv 1000)
    [Alias("brlow")]
    $BitratePercentageLow = 0, # a percentage of how much the final target video bitrate should be lowered. For example if the final target bitrate would be 1000 kbps but its lowered 5%, the bitrate will be 950kbps instead. 
    # This can be used without setting a target size (-s) to instead lower the input video's bitrate by the percentage and using that as the target. In practice this is almost the equivalent of lowering the file size by a percentage

    [Alias("ca")]
    $SelectedAudioCodec = "libopus", # other available codecs: aac
    [Alias("bra")]
    $TargetAudioBitrate_kbps = "128", # Or the input video's bit rate, whichever is lower
    $ForceAudioTranscoding = $false, # In case the input video audio bitrate is lower than the target, copy the audio instead of transcoding. You may set this to true (1) id you'd like to forcefully re-encode the audio with the smaller bitrate. (e.g If input video's audio is aac at 100kbps and the target is opus at 128kbps, using -ForceAudioTranscoding 1 will encode opus at 100kbps. Setting it to false (the default) will just copy the audio, resulting in aac 100k)
    $PrioritizeAudioBitrate = $false, # In case the resulting audio size would take up more than 20% of the entire target file size, the script automatically recalculates the audio bitrate so the audio would take up 20% of the file. You can force your desired bitrate to be used, and instead the video bitrate will be recalculated to accomodate the inflated audo bitrate. If the audio bitrate would take 100% or more of the target bitrate, the script wont continue.

    [Alias("params")] # pass extra, codec-specific arguments to ffmpeg. For example using "-params lp=2" will pass "-<codec>-params lp=2" to ffmpeg. In this case "lp" is used with libsvtav1, so "-svtav1-params lp=2" will get passed to ffmpeg. Multiple parameters can be added if theyre colon seperated (e.g enable-variance-boost=1:variance-boost-strength=2:variance-octile=5)
    $encoderParameters,

    $fancyrename = $true, # pass "0" for false when changing. Disables codec information in the output file name (e.g resulting videos will only be named "compressed_<video_name>")
    [Alias("svtav1app")]
    $isSvtav1encappAvailable = $true, # disable to manually force the use of svt-av1. If its left true by default, the script will auto-detect if svtav1encapp is available, and use it instead of ffmpeg's svt-av1 version.
    [Alias("nvenctune")]
    $NvencTuneLevel = "hq", # you may optionally change the -tune paramterer when using nvenc encoders. This was mainly added to test the uhq tuning level only available for hevc_nvenc for certain gpus.
    [Alias("retry")]
    $RetryEncodingIfTargetNotMet = $false, # enable to make the script automatically retry to encode the video if the resulting file is over the size. It will retry multiple times while lowering the bitrate each time
    [Alias("retrylow")]
    $RetryEncodingPercentageLowAmount = 2 # the percentage of how much the script should lower the bitrate for each try when the video fails to hit the file target
)
Set-Location $PSScriptRoot

$StartingVideoSize_MiB = (Get-Item -LiteralPath $video).Length/1MB
if (-not($StartingVideoSize_MiB -eq "0") -and ($StartingVideoSize_MiB -le $TargetVideoSize_MiB)){
    Write-Error "Target size cant be higher than the video's current size ($StartingVideoSize_MiB)"
    exit
}

# Probe duration and calculate the duration of the video
# ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1
$StartingVideoDuration_sec = ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $video
if (-not ($TargetVideoTrim -eq -1)){
    $TargetVideoTrimStart, $TargetVideoTrimEnd = $TargetVideoTrim.Split("-")
    [int]$TargetVideoTrimStart_hrs, [int]$TargetVideoTrimStart_min, [int]$TargetVideoTrimStart_sec = $TargetVideoTrimStart.Split(":")
    [int]$TargetVideoTrimEnd_hrs, [int]$TargetVideoTrimEnd_min, [int]$TargetVideoTrimEnd_sec = $TargetVideoTrimEnd.Split(":")
    $TargetVideoDuration_sec = (($TargetVideoTrimEnd_hrs * 3600) + ($TargetVideoTrimEnd_min * 60) + $TargetVideoTrimEnd_sec) - (($TargetVideoTrimStart_hrs * 3600) + ($TargetVideoTrimStart_min * 60) + $TargetVideoTrimStart_sec)
} else {
    $TargetVideoDuration_sec = $StartingVideoDuration_sec
}

# Probe video and audio bitrates
[float]$StartingVideoBitrate_bps = ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 $video
$StartingAudioBitrate_kbps = (ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 $video) / 1000
if (-not $StartingAudioBitrate_kbps){
    Write-Warning "Failed to (easily) get the audio bitrate of the video. Letting ffmpeg interpret audio bitrate (may not be accurate)"
    [int]$StartingAudioSize_KiB = (ffmpeg -i $video -map 0:a:0 -c copy -f null NUL 2>&1 | Out-String -Stream | Select-String -Pattern 'audio:(\d+)KiB').Matches[0].Groups[1].Value
    $StartingAudioBitrate_kbps = ($StartingAudioSize_KiB * 8.192) / $StartingVideoDuration_sec
}
$TargetAudioCodec = $SelectedAudioCodec


if (($StartingAudioBitrate_kbps -le [float]$TargetAudioBitrate_kbps) -and $StartingAudioBitrate_kbps){
    if (-not $ForceAudioTranscoding){
        Write-Warning "Copying audio, wont transcode. The bitrate is already below the target ($StartingAudioBitrate_kbps`kbps < $TargetAudioBitrate_kbps`kbps)."
        $TargetAudioCodec = "copy"
    } else {
        Write-Warning "Audio bitrate of the input video is lower than the target bitrate. Using $StartingAudioBitrate_kbps`kbps instead of $TargetAudioBitrate_kbps`kbps"
    }
    $TargetAudioBitrate_kbps = $StartingAudioBitrate_kbps
}

if ($TargetVideoSize_MiB){
    [float]$TargetVideoSize_kbit = [float]$TargetVideoSize_MiB * 8388.608
    [float]$TargetAudioSize_kbit = [float]$TargetAudioBitrate_kbps * $TargetVideoDuration_sec # the aproximate size of the whole audio
    [float]$TargetVideoBitrate_kbps = ($TargetVideoSize_kbit - $TargetAudioSize_kbit) / $TargetVideoDuration_sec # the bitrate for the video would be the targeted size - aproximate audio size, all divided by the duration 

    if (($TargetAudioSize_kbit / $TargetVideoSize_kbit) -gt 0.2){
        if (-not $PrioritizeAudioBitrate){
            Write-Host "Audio size would be over 20% of the target size. Re-calculating audio bitrate so audio will take up 20% of the file..."
            # In normal use cases this will hopefully never happen, but with very long videos that are set to very low target sizes this can become an issue.
            $TargetAudioCodec = $SelectedAudioCodec # dont forget to also re-select the codec. This gets set once earler in the code, but just in case the input video audio is both below the target (which will set the codec to "copy") AND the audio will trigger this 20% check, we need to set the codec to the selected one once agian
            $TargetAudioBitrate_kbps = 0.2 * $TargetVideoSize_kbit / $TargetVideoDuration_sec
            $TargetAudioSize_kbit = [float]$TargetAudioBitrate_kbps * $TargetVideoDuration_sec
        } else {
           Write-Warning "Audio WILL be over 20% of the target size because you enabled PrioritizeAudioBitrate."
            if (($TargetAudioSize_kbit / $TargetVideoSize_kbit) -gt 1){
                Write-Error "Audio would take up more than the entire video target. Either disable PrioritizeAudioBitrate or lower the audio bitrate!"
                exit
            }
        }
        $TargetVideoBitrate_kbps = ($TargetVideoSize_kbit - $TargetAudioSize_kbit) / $TargetVideoDuration_sec
    }

    if ($BitratePercentageLow -gt 0){
        $TargetVideoBitrate_kbps = $TargetVideoBitrate_kbps * (1 - ($BitratePercentageLow / 100))
    }
} elseif ($BitratePercentageLow -gt 0) {
    Write-Host "Target size was not given, using bitrate lowering percentage on the input video's bitrate ($($StartingVideoBitrate_bps / 1000) kbps) instead"
    $TargetVideoBitrate_kbps = $($StartingVideoBitrate_bps / 1000) * (1 - ($BitratePercentageLow / 100))
} elseif ($TargetVideoBitrate_kbps -le 0){
    Write-Error "Target bitrate is not valid (not set or not > 0)"
}

if ($TargetVideoBitrate_kbps -ge $($StartingVideoBitrate_bps / 1000)){
    Write-Warning("Target video bitrate is higher than the starting bitrate. You probably used -trim, and in this case you can just trim the video with ffmpeg without re-encoding and the file will be below the target size. The script will NOT handle this, and it will re-encode the video with the higher target bitrate")
}

$EncodingAttempts = 0
$EncodeTotalStartTime = Get-Date

while(1){ # --- Start of encoding retry loop ---
Write-Host "=== [FF2PPRESS Video Info] ==="
Write-Host ("Starting Video Duration / Size / Bitrate : {0:F2} sec / {1:F2} MiB / {2:F2} kbps" -f [float]$StartingVideoDuration_sec, $StartingVideoSize_MiB, $([float]$StartingVideoBitrate_bps / 1000))
Write-Host ("Starting Audio Bitrate                   : {0:F2} kbps" -f $StartingAudioBitrate_kbps)
Write-Host ("Target Video Duration / Size / Bitrate   : {0:F2} sec / {1:F2} MiB / {2:F2} kbps" -f [float]$TargetVideoDuration_sec, $TargetVideoSize_MiB, $TargetVideoBitrate_kbps)
Write-Host ("Target Audio Bitrate                     : {0:F2} kbps" -f $TargetAudioBitrate_kbps)
Write-Host "=== [FF2PPRESS Video Info] ==="

# video resolution calculation (mostly only needed for svtav1encapp, but this needs to be here so we can print the resolution for the user)
$StartingVideoHeight = ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 $video
$StartingVideoWidth = ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 $video
$TargetVideoHeight = $inputTargetVideoHeight
$TargetVideoWidth  = $inputTargetVideoWidth
if ($TargetVideoHeight -eq -1){$TargetVideoHeight = $StartingVideoHeight}
if ($TargetVideoWidth -eq -1){$TargetVideoWidth = $StartingVideoWidth}

if ($inputTargetVideoHeight -ne -1 -and $inputTargetVideoWidth -eq -1){
    $TargetVideoWidth = $StartingVideoWidth / ($StartingVideoHeight / $inputTargetVideoHeight)
} elseif ($inputTargetVideoWidth -ne -1 -and $inputTargetVideoHeight -eq -1){
    $TargetVideoHeight = $StartingVideoHeight / ($StartingVideoWidth / $inputTargetVideoWidth)
}

# Cerain codecs may need extra arguments to work properly or to use extra features. They are set here:
#if ($videocodec -in "libx265", "libx254"){$FFmpegExtraVideoArgs = @()} else # I dont really need this

if ($videocodec -in "hevc_nvenc", "h264_nvenc"){
    if (-not ($videocodecpreset -in "p1","p2","p3","p4","p5","p6","p7")){
        Write-Host "Preset `"$videocodecpreset`" does not match for a nvenc preset, defaulting to preset `"p7`" for nvenc (this is the highest preset)"
        $videocodecpreset = "p7"
    }
    if ($NvencTuneLevel -eq "uhq"){
        if ($videocodec -eq "h264_nvenc") {
            Write-Warning "UHQ (ultra high quality) tuning for h264_nvenc is unavailable. Using HQ tuning instead."
            $NvencTuneLevel = "hq"
        } else {
            Write-Warning "Using UHQ (ultra high quality) tuning for hevc_nvenc. The encoding time will be slower!"
        }
    }
    $FFmpegExtraVideoArgs = @(
        "-rc", "cbr",
        "-tune", "$NvencTuneLevel",
        "-multipass", "fullres"
    )
} elseif ($videocodec -eq "libaom-av1"){
    Write-Host "libaom-av1 Info! On the 1st pass the progress bar/info may appear to be stuck, but the pass will still complete. Have patiance"
    if ($videocodecpreset -notin (0..8)){
        Write-Host "Preset `"$videocodecpreset`" does not match for a libaom-av1 `"cpu-used`" value, defaulting to cpu-used `"8`" for libaom-av1 (fastest setting)"
        $videocodecpreset = "8"
    }

    $FFmpegExtraVideoArgs = @(
        "-cpu-used", "$videocodecpreset",
        "-row-mt", "1"
    )
} elseif ($videocodec -eq "libsvtav1"){
    if ($videocodecpreset -notin (-1..13)){
        Write-Host "Preset `"$videocodecpreset`" does not match for a libsvtav1 preset. Defaulting to prest `"5`""
        $videocodecpreset = "5"
    }

    if ($isSvtav1encappAvailable -eq $true){
        $isSvtav1encappAvailable = [bool](Get-Command -ErrorAction Ignore -Type Application SvtAv1EncApp)
    }

    if ($isSvtav1encappAvailable -eq $false){
        Write-Warning "FFmpeg versions below 8.1 DO NOT have support for 2-pass mode with SVT-AV1. If you use a version below 8.1, the video will just encode twice with 1 pass, wasting your time. Make sure youre on the latest FFmpeg version or use SvtAv1EncApp as the readme mentions."
    } else {
        Write-Warning "SvtAv1EncApp was found! Consider updating FFmpeg to version 8.1 so you can use 2-pass encoding via FFmpeg instead if you haven't already. FFmpeg's svt-av1 version in 2-pass mode may be faster than using SvtAv1EncApp via this script."
        $StartingVideoPixFmt = ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 $video
        $StartingVideoFPS = ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 $video
        $StartingVideoFrameNumerator, $StartingVideoFrameDenominator = $StartingVideoFPS.Split("/")
        
        if ($StartingVideoPixFmt -eq "yuv420p10le"){
            $TargetVideoBitDepth = 10
        } else { $TargetVideoBitDepth = 8 }

        $svtav1appVideoargs = @(
            "-i", "stdin",
            "-w", $TargetVideoWidth,
            "-h", $TargetVideoHeight,
            "--rc", "1",
            "--tbr", $TargetVideoBitrate_kbps,
            "--preset", $videocodecpreset,
            "--input-depth", $TargetVideoBitDepth,
            "--fps-num", $StartingVideoFrameNumerator,
            "--fps-denom", $StartingVideoFrameDenominator,
            "--stats", "SvtAv1EncApp_2pass.log",
            "--lookahead", "42" # Force lookahead to 42, as the svtav1 warning tells you to. No clue if this automatically gets set, or what the benifit is, but im setting it anyways. "Svt[warn]: For CRF or 2PASS RC mode, the maximum needed Lookahead distance is 42. Force the look_ahead_distance to be 42"
        )

        if ($encoderParameters){
            $svtav1appParameters = $encoderParameters -split ':' |
            ForEach-Object {
                $name, $value = $_ -split '=', 2
                "--$name", $value
            }
        }
    }
} else {
    Write-Error "Unkown/Unavailable video codec. Check the available codecs in readme"
    exit
}

# FFmpeg "Base" Video arguments. Common arguments which can/should be set for any codec via ffmpeg
$FFmpegBaseVideoArgs = @(
    "-i", $video,
    "-c:v", $videocodec,
    "-b:v", "$TargetVideoBitrate_kbps`k",
    "-preset", "$videocodecpreset"
)

$FFmpegNullP1 = @(
    "NUL"    
)

if ($TargetAudioCodec -in "libopus", "aac", "copy"){
    $FFmpegAudioArgs = @(
        "-c:a", $TargetAudioCodec,
        "-b:a", "$TargetAudioBitrate_kbps`k"
    )
} else {
    Write-Error "Unkown/Unavailable audio codec. Check the available codecs in readme"
    exit
}

if (($inputTargetVideoHeight -ne -1) -or ($inputTargetVideoWidth -ne -1)){
    Write-Host "Rescaling the video to $TargetVideoWidth`:$TargetVideoHeight (width:height)"
    $FFmpegVideoRescaleArgs = @(
        "-vf", "scale=$([int]$inputTargetVideoWidth)`:$([int]$inputTargetVideoHeight)",
        "-sws_flags", "lanczos" # enable lanczos downscale filter for high quality scaling
    )
} else {
    $FFmpegVideoRescaleArgs = @()
}

if (-not ($TargetVideoTrim -eq -1)){
    $FFmpegTrimArgs = @(
        "-ss", $TargetVideoTrimStart,
        "-to", $TargetVideoTrimEnd
    )
} else {
    $FFmpegTrimArgs = @()
}

if (($encoderParameters)){
    if($videocodec -eq "libaom-av1"){
        $codecparam = "aom" # why did they do this, it should have been aom-av1-params just like svtav1-params
    } else {
        $codecparam = $videocodec.Substring(3) # literally just cut the first 3 letters of the codec, since its gonna be "lib". NVENC does not have a -params option, but that should be obvious to the knowledgeable user so i wont bother checking for it
    }

    $FFmpegCodecParams = @(
        "-$codecparam-params", "$encoderParameters"
    )
} else {
    $FFmpegCodecParams = @()
}

if ($fancyrename){ # I just realized im converting all files to MP4, regardless of their original file extension. Meh whatever mp4 is good enough
    if ($TargetVideoSize_MiB){ $outputfilename = "compressed_$($TargetVideoSize_MiB)mib_$([IO.Path]::GetFileNameWithoutExtension($video))_$($videocodec)_$($videocodecpreset).mp4" }
    else { $outputfilename = "compressed_$([IO.Path]::GetFileNameWithoutExtension($video))_$($videocodec)_$($videocodecpreset).mp4" }
} else {
    $outputfilename = "compressed_$([IO.Path]::GetFileNameWithoutExtension($video)).mp4"
}

if (!$outputfolder){
    $videoFullPath = Resolve-Path -LiteralPath $video
    $FinalOutputFile = "$(Split-Path -LiteralPath $videoFullPath)\$outputfilename"
    $svtav1appOutputTempPath = "$(Split-Path -LiteralPath $videoFullPath)\SvtAv1EncApp_Temp_$([IO.Path]::GetFileNameWithoutExtension($video)).mp4"
} elseif (Test-Path -LiteralPath $outputfolder) {
    $FinalOutputFile = "$outputfolder\$outputfilename"
    $svtav1appOutputTempPath = "$outputfolder\SvtAv1EncApp_Temp_$([IO.Path]::GetFileNameWithoutExtension($video)).mp4"
} else {
    Write-Error "Output folder is invalid or doesnt exist! Path: $outputfolder" 
    exit
}
Write-Host "Output file path: $FinalOutputFile"

# --- Start Encoding ---
$EncodeAttemptStartTime = Get-Date
$EncodingAttempts++

if (($videocodec -eq "libsvtav1") -and ($isSvtav1encappAvailable -eq $true)){
    Write-Host "=== === Start 1st pass === ==="
    ffmpeg -hide_banner -loglevel error -i $video -an -f rawvideo @FFmpegVideoRescaleArgs @FFmpegTrimArgs - | SvtAv1EncApp --progress 0 --pass 1 @svtav1appVideoargs @svtav1appParameters

    Write-Host "=== === Start final pass === ==="
    ffmpeg -hide_banner -loglevel error -i $video -an -f rawvideo @FFmpegVideoRescaleArgs @FFmpegTrimArgs - | SvtAv1EncApp --progress 0 --pass 2 @svtav1appVideoargs @svtav1appParameters -b $svtav1appOutputTempPath

    Write-Host "=== Encoding Audio ==="
    ffmpeg -hide_banner -loglevel error -y -i $svtav1appOutputTempPath -i $video -map 0:v? -map 1:a? @FFmpegTrimArgs -c:v copy @FFmpegAudioArgs $FinalOutputFile # seperately encode the audio by mapping the audio from the original video and the video from the newly compressed file

    Remove-Item -LiteralPath $svtav1appOutputTempPath -Force -ErrorAction SilentlyContinue
} else {
    if (-not($videocodec -in "hevc_nvenc", "h264_nvenc")){
        Write-Host "=== === Start 1st pass === ==="
        ffmpeg -hide_banner -loglevel error -stats @FFmpegBaseVideoArgs @FFmpegExtraVideoArgs -pass 1 @FFmpegCodecParams @FFmpegVideoRescaleArgs @FFmpegTrimArgs -an -f null @FFmpegNullP1

        Write-Host "=== === Start final pass === ==="
        ffmpeg -hide_banner -loglevel error -stats @FFmpegBaseVideoArgs @FFmpegExtraVideoArgs -pass 2 @FFmpegCodecParams @FFmpegVideoRescaleArgs @FFmpegTrimArgs @FFmpegAudioArgs $FinalOutputFile
    } else {
        # i still need to seperate the ffmpeg command when using nvenc, since i cant pass "-pass 2" at all
        Write-Host "=== === Start final pass === ==="
        ffmpeg -hide_banner -loglevel error -stats @FFmpegBaseVideoArgs @FFmpegExtraVideoArgs @FFmpegCodecParams @FFmpegVideoRescaleArgs @FFmpegTrimArgs @FFmpegAudioArgs $FinalOutputFile
    }
}

$MiBresultsize = (Get-Item -LiteralPath $FinalOutputFile).Length/1MB
if ($TargetVideoSize_MiB -and ($MiBresultsize -ge $TargetVideoSize_MiB)){
    if ($RetryEncodingIfTargetNotMet){
        Write-Warning "Resulting file size ($MiBresultsize MiB) is over the target size. Retrying to encode with $RetryEncodingPercentageLowAmount% lower video bitrate..."
        $CurrentRetryEncodingPercentageLowAmount = $CurrentRetryEncodingPercentageLowAmount + $RetryEncodingPercentageLowAmount
        Remove-Item -LiteralPath $FinalOutputFile -Force -ErrorAction SilentlyContinue
        
        $EndTime = Get-Date
        $ElapsedAttemptTime = ([math]::Round(($EndTime - $EncodeAttemptStartTime).TotalSeconds, 2))
        Write-Host "Attempt $EncodingAttempts took $ElapsedAttemptTime seconds ($($ElapsedAttemptTime / 60) minutes)"
        $TargetVideoBitrate_kbps = $TargetVideoBitrate_kbps * (1 - ($CurrentRetryEncodingPercentageLowAmount / 100))
        Write-Host "=== === === Attempt $($EncodingAttempts+1) === === ==="
    } else {
        Write-Warning "Resulting file size ($MiBresultsize MiB) is over the target size. Automatic encode retrying is disabled! Use -retry 1 if you want to enable it"
        break
    }
} else {
    break
}

} # --- End of encoding retry loop ---
Remove-Item ".\x265_2pass.log*" -Force -ErrorAction SilentlyContinue # deletes x265 log files
Remove-Item ".\ffmpeg2pass-0.log*" -Force -ErrorAction SilentlyContinue # deletes other 2pass ffmpeg log files
Remove-Item ".\SvtAv1EncApp_2pass.log*" -Force -ErrorAction SilentlyContinue


$EndTime = Get-Date
if($EncodingAttempts -gt 1) { Write-Host "Attempt $EncodingAttempts took $ElapsedAttemptTime seconds ($($ElapsedAttemptTime / 60) minutes)" }
$ElapsedAttemptTime = ([math]::Round(($EndTime - $EncodeTotalStartTime).TotalSeconds, 2))
Write-Host "Encoding took $ElapsedAttemptTime seconds in total ($($ElapsedAttemptTime / 60) minutes)"

Write-Host "=== === === Video Done! === === ==="