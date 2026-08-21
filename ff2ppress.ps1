param(
    [Alias("i")]
    $InputVideo, # the path of the video you want to compress
    [Alias("s")]
    [float]$TargetVideoSize_MiB = 20, # set a target size in MiB

    [Alias("o")]
    $outputfolder, # output folder. Defaults to outputting in the same folder as the input video
    $fancyrename = $true, # pass "0" for false when changing. Disables codec information in the output file name (e.g resulting videos will only be named "compressed_<video_name>")

    [Alias("cv")]
    $VideoEncoder = "libx265", # other available codecs: hevc_nvenc, libx264, h264_nvenc, libsvtav1, libaom-av1, libvpx-vp9
    [Alias("cvpreset")]
    $VideoEncoderPreset = "medium", # defaults automatically on: hevc_nvenc - p7, libx264 - medium, h264_nvenc - p7, libsvtav1 - 5, libaom-av1 - 8, libvpx-vp9 - 4
    [Alias("params")] # pass extra, codec-specific arguments to ffmpeg. For example using "-params lp=2" will pass "-<codec>-params lp=2" to ffmpeg. In this case "lp" is used with libsvtav1, so "-svtav1-params lp=2" will get passed to ffmpeg. Multiple parameters can be added if theyre colon separated (e.g enable-variance-boost=1:variance-boost-strength=2:variance-octile=5)
    $encoderParameters,

    [Alias("h")]
    $TargetVideoHeight = -1, # set a video Height or Width (-h / -w) in pixels to rescale the output video. You can just use one of these and the other side will get automatically scaled to keep the same aspect ratio (e.g -h 1080). The default values (-1) do not rescale the video
    [Alias("w")]
    $TargetVideoWidth = -1,
    [Alias("trim")]
    $TargetVideoTrim, # Set the start and end timestamps to trim the video, seperated by "-". The timestamps can have the following formats: Seconds (example: "-trim 5-10"); MM:SS ("-trim 0:15-1:30"); HH:MM:SS ("-trim 1:10:05-2:40:30"); HH:MM:SS.mmm ("-trim 1:10:05.250-2:40:30.750"). You can also pass "end" as the end timestamp, to set it to the end of the video like so: "-trim 5-end", "-trim 0:15-end"
    $ForceVideoEncoding = 1, # when using -trim, there could be a chance that the target video bitrate will end up being higher than the starting video target. This means trimming the video will theoretically be enough to get under the target file size without having to re-encode the video. Setting "-ForceVideoEncoding" to "1" will make ffmpeg re-encode the video in this case, even if the target video bitrate is higher than the input. Setting "-ForceVideoEncoding" to "0" will copy the video and audio codec while still trimming the video, but it may result into a choppy video or the start of the video may be black for a few seconds.
    [Alias("brv")]
    [float]$TargetVideoBitrate_kbps, # can be used instead of -s or -brlow to manually set a bitrate in kbps (e.g -brv 1000)
    [Alias("brlow")]
    $BitratePercentageLow = 0, # a percentage of how much the final target video bitrate should be lowered. For example if the final target bitrate would be 1000 kbps but its lowered 5%, the bitrate will be 950kbps instead. 
    # This can be used without setting a target size (-s) to instead lower the input video's bitrate by the percentage and using that as the target. In practice this is almost the equivalent of lowering the file size by a percentage

    [Alias("audiostream")]
    $InputAudioStream = 0, # if the input video has several video or audio streams, you may choose which ones to use for the output file. You can only choose one audio and one video stream. By default, the script takes the first audio and video stream that is available (indexes start at 0). Example: Input video file has 2 audio tracks/streams, but if you wish to only use the 2nd audio stream for the compressed video, use -audiostream 1
    [Alias("videostream")]
    $InputVideoStream = 0,

    [Alias("ca")]
    $SelectedAudioCodec = "libopus", # other available codecs: aac
    [Alias("bra")]
    [float]$TargetAudioBitrate_kbps = "128", # Or the input video's bit rate, whichever is lower
    $ForceAudioEncoding = $false, # In case the input video audio bitrate is lower than the target, copy the audio instead of transcoding. You may set this to true (1) id you'd like to forcefully re-encode the audio with the smaller bitrate. (e.g If input video's audio is aac at 100kbps and the target is opus at 128kbps, using -ForceAudioTranscoding 1 will encode opus at 100kbps. Setting it to false (the default) will just copy the audio, resulting in aac 100k)
    $PrioritizeAudioBitrate = $false, # In case the resulting audio size would take up more than 20% of the entire target file size, the script automatically recalculates the audio bitrate so the audio would take up 20% of the file. You can force your desired bitrate to be used, and instead the video bitrate will be recalculated to accommodate the inflated audo bitrate. If the audio bitrate would take 100% or more of the target bitrate, the script wont continue.

    [Alias("retry")]
    $RetryEncodingIfTargetNotMet = $true, # enable to make the script automatically retry to encode the video if the resulting file is over the size. It will retry multiple times while lowering the bitrate each time
    [Alias("retrylow")]
    $RetryEncodingPercentageLowAmount = 2, # the percentage of how much the script should lower the bitrate for each try when the video fails to hit the file target

    [Alias("ffmpegargs")]
    $FFmpegUserArguments
)
Set-Location $PSScriptRoot

$IsFfmpegAvailable = [bool] (Get-Command -ErrorAction Ignore -Type Application ffmpeg)
if (-not $IsFfmpegAvailable){
    Write-Error "ffmpeg is not installed or not in PATH."
    exit
}
else {
    $FfmpegVersionOutput = & ffmpeg -version 2>$null | Select-Object -First 1
    if ($FfmpegVersionOutput -match "ffmpeg version\s(?:n)?(\d+(\.\d+)*)") {
        $FoundFfmpegVersion = [version]$matches[1]
    }
}

$StartingVideoSize_MiB = (Get-Item -LiteralPath $InputVideo).Length / 1MB
if ($StartingVideoSize_MiB -le $TargetVideoSize_MiB -and -not $PSBoundParameters.ContainsKey('TargetVideoBitrate_kbps') -and -not (-not $PSBoundParameters.ContainsKey('TargetVideoSize_MiB') -and $PSBoundParameters.ContainsKey('BitratePercentageLow'))) {
    # quite the handful... if statements like these trip me up a lot
    # check if the input video size is under the target size, but only exit if the target bitrate wasnt manually set, and if brlow was used without setting a target size
    Write-Error "Target size can't be higher than the video's current size ($StartingVideoSize_MiB)"
    exit
}

# Probe duration and calculate the duration of the video
$GetVideoDurationAttempts = 1
while (($StartingVideoDuration_sec -eq "N/A") -or -not($StartingVideoDuration_sec)){
    switch ($GetVideoDurationAttempts) {
        1 {
            [double]$StartingVideoDuration_sec = ffprobe -v error -select_streams v:$InputVideoStream -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 $InputVideo
        }
        2 {
            # some videos dont store the duration on a per video stream basis, so its harder to get the duration of a specific stream
            $StreamTagsJson =  ffprobe -v quiet -select_streams v:$InputVideoStream -print_format json -show_entries stream_tags $InputVideo | ConvertFrom-Json

            $TagDurationFull = $StreamTagsJson.streams[0].tags.PSObject.Properties | Where-Object { $_.Name -like "DURATION*" } | Select-Object -Last 1 # mkv files may store the duration of a stream in a "stream" tag, but the "DURATION" tag name itself may have an suffix added to it (for example "DURATION-eng"), so im trying to account for most cases by doing this
            $TagDuration = $TagDurationFull.Value -replace '(\.\d{7})\d*$', '$1' # [TimeSpan]::Parse can only parse 7 digits for the second fractions. This limits the second fractions to 7 digits. Example duration: 00:23:41.920000000
            try {
                $TagDurationParsed = [TimeSpan]::Parse($TagDuration)
                [double]$StartingVideoDuration_sec = $TagDurationParsed.TotalSeconds
            } catch {
                $StartingVideoDuration_sec = $null
            }
        }
        default {

            if(($InputAudioStream -gt 0) -or ($InputVideoStream -gt 0)){
                Write-Warning "Could not get the exact duration of your specified video stream. The format duration will be used instead, which may or may not result in inaccurate bitrate calculations!"
            }

            [double]$StartingVideoDuration_sec = ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $InputVideo
        }
    }
    $GetVideoDurationAttempts++
}

if ($PSBoundParameters.ContainsKey("TargetVideoTrim")) {
    function ConvertTo-Seconds {
        # probably a cursed place to put a function definition
        # whatever, go my clod! im lazy
        param([Parameter(Mandatory)][string]$Timestamp)

        if ($Timestamp -eq "end"){
            return $StartingVideoDuration_sec
        }

        $TimestampParts = $Timestamp.Split(":")
        
        # you can tell the type of timestamp format that was used from the number of parts it has
        switch ($TimestampParts.Count) {
            1 { # e.g "90"
                return [double]$TimestampParts[0]
            }
            2 { # e.g "1:30" 
                return ([double]$TimestampParts[0] * 60) + [double]$TimestampParts[1]
            }
            3 { # e.g "0:01:30" or "0:01:30.500". The decimal point number should be miliseconds not fractions.
                return ([double]$TimestampParts[0] * 3600) + ([double]$TimestampParts[1] * 60) + [double]$TimestampParts[2]
            }
            default {
                throw "Invalid timestamp format: $Timestamp"
            }
        }
    }

    $TargetVideoTrimStart, $TargetVideoTrimEnd = $TargetVideoTrim.Split("-")

    [double]$TargetVideoDuration_sec = (ConvertTo-Seconds $TargetVideoTrimEnd) - (ConvertTo-Seconds $TargetVideoTrimStart)
}
else {
    $TargetVideoDuration_sec = $StartingVideoDuration_sec
}

# Probe audio bitrate
$GetAudioBitrateAttempts = 1
while (($StartingAudioBitrate_kbps -eq "N/A") -or -not($StartingAudioBitrate_kbps)){
    switch ($GetAudioBitrateAttempts) {
        1 {
            $StartingAudioBitrate_kbps = (ffprobe -v error -select_streams a:$InputAudioStream -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 $InputVideo) / 1000
        }
        default {
            [float]$StartingAudioSize_KiB = (ffmpeg -i $InputVideo -map 0:a:$InputAudioStream -c copy -f null NUL 2>&1 | Out-String -Stream | Select-String -Pattern 'audio:(\d+)KiB').Matches[0].Groups[1].Value
            $StartingAudioBitrate_kbps = ($StartingAudioSize_KiB * 8.192) / $StartingVideoDuration_sec
        }
    }
    $GetAudioBitrateAttempts++
}

# Probe video bitrate
$GetVideoBitrateAttempts = 1
while (($StartingVideoBitrate_kbps -eq "N/A") -or -not($StartingVideoBitrate_kbps)){
    switch ($GetVideoBitrateAttempts) {
        1 {
            $StartingVideoBitrate_kbps = (ffprobe -v error -select_streams v:$InputVideoStream -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 $InputVideo) / 1000
        }
        default {
            [float]$StartingVideoSize_KiB = (ffmpeg -i $InputVideo -map 0:v:$InputVideoStream -c copy -f null NUL 2>&1 | Out-String -Stream | Select-String -Pattern 'video:(\d+)KiB').Matches[0].Groups[1].Value
            $StartingVideoBitrate_kbps = ($StartingVideoSize_KiB * 8.192) / $StartingVideoDuration_sec
        }
    }
    $GetVideoBitrateAttempts++
}

$TargetAudioCodec = $SelectedAudioCodec
if (($StartingAudioBitrate_kbps -le $TargetAudioBitrate_kbps) -and $StartingAudioBitrate_kbps) {
    if (-not $ForceAudioEncoding) {
        Write-Warning "Copying audio, wont transcode. The bitrate is already below the target ($StartingAudioBitrate_kbps`kbps < $TargetAudioBitrate_kbps`kbps)."
        $TargetAudioCodec = "copy"
    }
    else {
        Write-Warning "Audio bitrate of the input video is lower than the target bitrate. Using $StartingAudioBitrate_kbps`kbps instead of $TargetAudioBitrate_kbps`kbps"
    }
    $TargetAudioBitrate_kbps = $StartingAudioBitrate_kbps
}

if (-not($TargetVideoBitrate_kbps)){
    if (-not $PSBoundParameters.ContainsKey('TargetVideoSize_MiB') -and $PSBoundParameters.ContainsKey('BitratePercentageLow')){
        Write-Host "Target size was not given, using bitrate lowering percentage on the input video's bitrate instead"
        $TargetVideoBitrate_kbps = $StartingVideoBitrate_kbps * (1 - ($BitratePercentageLow / 100))
    }
    else {
        [float]$TargetVideoSize_kbit = $TargetVideoSize_MiB * 8388.608
        [float]$TargetAudioSize_kbit = $TargetAudioBitrate_kbps * $TargetVideoDuration_sec # the approximate size of the whole audio
        $TargetVideoBitrate_kbps = ($TargetVideoSize_kbit - $TargetAudioSize_kbit) / $TargetVideoDuration_sec # the bitrate for the video would be the targeted size - approximate audio size, all divided by the duration 

        if (($TargetAudioSize_kbit / $TargetVideoSize_kbit) -gt 0.2) {
            if (-not $PrioritizeAudioBitrate) {
                Write-Host "Audio size would be over 20% of the target size. Re-calculating audio bitrate so audio will take up 20% of the file..."
                # In normal use cases this will hopefully never happen, but with very long videos that are set to very low target sizes this can become an issue.
                $TargetAudioCodec = $SelectedAudioCodec # dont forget to also re-select the codec. This gets set once earlier in the code, but just in case the input video audio is both below the target (which will set the codec to "copy") AND the audio will trigger this 20% check, we need to set the codec to the selected one once again
                $TargetAudioBitrate_kbps = 0.2 * $TargetVideoSize_kbit / $TargetVideoDuration_sec
                $TargetAudioSize_kbit = $TargetAudioBitrate_kbps * $TargetVideoDuration_sec
            }
            else {
                Write-Warning "Audio WILL be over 20% of the target size because you enabled PrioritizeAudioBitrate."
                if (($TargetAudioSize_kbit / $TargetVideoSize_kbit) -gt 1) {
                    Write-Error "Audio would take up more than the entire video target. Either disable PrioritizeAudioBitrate or lower the audio bitrate!"
                    exit
                }
            }
            $TargetVideoBitrate_kbps = ($TargetVideoSize_kbit - $TargetAudioSize_kbit) / $TargetVideoDuration_sec # recalculate the video bitrate to accommodate the new audio bitrate
        }

        if ($BitratePercentageLow -gt 0) {
            $TargetVideoBitrate_kbps = $TargetVideoBitrate_kbps * (1 - ($BitratePercentageLow / 100))
        }
    }
}

if ($TargetVideoBitrate_kbps -le 0) {
    Write-Error "Target bitrate is not valid (not set or not > 0)"
    exit
}

if ($FFmpegUserArguments){
    $FFmpegUserArguments = $FFmpegUserArguments -split ' '
    # clod pointed out this will not work if some ffmpeg arguments contain quoted text, such as when using drawtext like so: "-vf drawtext=text='hello testing':fontsize=24:x=10:y=10", but then it proceeded to give me regex that doesnt work, and i couldnt bother to figure it out myself, so sorry to anyone who wants to draw text on their videos i guess. (Unsure if this issue comes up in other commands as well)
}

$EncodingAttempts = 0
$EncodeTotalStartTime = Get-Date

while (1) {
    # --- Start of encoding retry loop ---
    Write-Host "[FF2PPRESS Video Info]"
    Write-Host ("Starting Video Duration / Size / Bitrate : {0:F2} sec / {1:F2} MiB / {2:F2} kbps" -f $StartingVideoDuration_sec, $StartingVideoSize_MiB, $StartingVideoBitrate_kbps)
    Write-Host ("Starting Audio Bitrate                   : {0:F2} kbps" -f $StartingAudioBitrate_kbps)
    Write-Host ("Target Video Duration / Size / Bitrate   : {0:F2} sec / {1:F2} MiB / {2:F2} kbps" -f $TargetVideoDuration_sec, $TargetVideoSize_MiB, $TargetVideoBitrate_kbps)
    Write-Host ("Target Audio Bitrate                     : {0:F2} kbps" -f $TargetAudioBitrate_kbps)
    Write-Host "[FF2PPRESS Video Info]"

    if (($TargetVideoBitrate_kbps -ge $StartingVideoBitrate_kbps) -and ($EncodingAttempts -lt 1) -and ($ForceVideoEncoding -eq 0)) { 
        $JustTrimmingEnabled = $true 
    } else { $JustTrimmingEnabled = $false }

    if ($JustTrimmingEnabled) {
        Write-Warning("Target video bitrate is higher than the starting bitrate. You probably used -trim, so in this case the video will just be trimmed without re-encoding")
        Write-Warning("For certain videos this approach may result in a `"choppy`" video. As an alternative you may choose to forcefully re-encode the video, even if the video bitrate is higher, by using -ForceVideoEncoding 1")
        $fancyrename = $false # disable this so files dont have unnecessary codec information in their names
    }
    else { # when just trimming, skip unnecessary setting some options
        if ($TargetVideoBitrate_kbps -ge $StartingVideoBitrate_kbps -and $EncodingAttempts -lt 1) {
            Write-Warning("Target video bitrate is higher than the starting bitrate. You probably used -trim, but in this case the video will be encoded with the higher bitrate. If you'd like, you can try using -ForceVideoEncoding 0 to only trim the video without re-encoding, but this may result in a choppy video.")
        }

        # Check for the codec and a correct preset. Certain codecs may also need extra arguments to work properly or to use extra features, those are set here too.
        if ($VideoEncoder -in "libx265", "libx264") {
            if (-not ($VideoEncoderPreset -in "ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow", "placebo")) {
                if ($PSBoundParameters.ContainsKey('VideoEncoderPreset')){
                    Write-Host "Preset `"$VideoEncoderPreset`" is not a valid preset for $VideoEncoder, defaulting to preset `"medium`""
                }
                $VideoEncoderPreset = "medium"
            }
            $FFmpegExtraVideoArgs = @()
        }
        elseif ($VideoEncoder -in "hevc_nvenc", "h264_nvenc") {
            if (-not ($VideoEncoderPreset -in "p1", "p2", "p3", "p4", "p5", "p6", "p7")) {
                if ($PSBoundParameters.ContainsKey('VideoEncoderPreset')){
                    Write-Host "Preset `"$VideoEncoderPreset`" is not a valid preset for $VideoEncoder, defaulting to preset `"p7`""
                }
                $VideoEncoderPreset = "p7"
            }

            $FFmpegExtraVideoArgs = @(
                "-rc", "cbr",
                "-multipass", "fullres"
            )
        }
        elseif ($VideoEncoder -eq "libaom-av1") {
            Write-Host "When using $VideoEncoder the progress bar/info may appear to be stuck on the 1st pass, but the pass will still complete."
            if ($VideoEncoderPreset -notin (0..8)) {
                if ($PSBoundParameters.ContainsKey('VideoEncoderPreset')){
                    Write-Host "Preset `"$VideoEncoderPreset`" is not a valid preset for $VideoEncoder, defaulting to preset `"8`""
                }
                $VideoEncoderPreset = "8"
            }

            $FFmpegExtraVideoArgs = @(
                "-cpu-used", "$VideoEncoderPreset",
                "-row-mt", "1"
            )
        }
        elseif ($VideoEncoder -eq "libsvtav1") {
            if ($VideoEncoderPreset -notin (-1..13)) {
                if ($PSBoundParameters.ContainsKey('VideoEncoderPreset')){
                    Write-Host "Preset `"$VideoEncoderPreset`" is not a valid preset for $VideoEncoder, defaulting to preset `"5`""
                }
                $VideoEncoderPreset = "5"
            }

            if ($FoundFfmpegVersion -lt [version]"8.1"){
                Write-Warning "FFmpeg versions below 8.1 DO NOT have support for 2-pass mode with SVT-AV1. Make sure youre on the latest FFmpeg version."
            }
        }
        elseif ($VideoEncoder -eq "libvpx-vp9") {
            Write-Host "When using $VideoEncoder the progress bar/info may appear to be stuck on the 1st pass, but the pass will still complete."
            if ($VideoEncoderPreset -notin (-8..8)) {
                if ($PSBoundParameters.ContainsKey('VideoEncoderPreset')){
                    Write-Host "Preset `"$VideoEncoderPreset`" is not a valid preset for $VideoEncoder, defaulting to preset `"4`""
                }
                $VideoEncoderPreset = "4"
            }
            if ($VideoEncoderPreset -in (5..8)) {
                Write-Warning "Using a preset (`"cpu-used`") of 5 and above for $VideoEncoder makes the 1st pass significantly slower. Preset 4 is the fastest in most, if not all cases!"
            }

            $FFmpegExtraVideoArgs = @(
                "-cpu-used", "$VideoEncoderPreset",
                "-row-mt", "1"
            )
        }
        elseif (-not ($VideoEncoder -eq "copy")) {
            Write-Error "Unknown/Unavailable video codec. Check the available codecs in readme"
            exit
        }

        # FFmpeg "Base" Video arguments. Common arguments which can/should be set for any codec
        $FFmpegBaseVideoArgs = @(
            "-i", $InputVideo,
            "-c:v", $VideoEncoder,
            "-b:v", "$TargetVideoBitrate_kbps`k",
            "-preset", "$VideoEncoderPreset"
        )

        if ($TargetAudioCodec -in "libopus", "aac", "copy") {
            $FFmpegAudioArgs = @(
                "-c:a", $TargetAudioCodec,
                "-b:a", "$TargetAudioBitrate_kbps`k"
            )
        }
        else {
            Write-Error "Unknown/Unavailable audio codec. Check the available codecs in readme"
            exit
        }

        if (($TargetVideoWidth -ne -1) -or ($TargetVideoHeight -ne -1)) {
            Write-Host "Rescaling the video to $TargetVideoWidth`:$TargetVideoHeight (width:height)"
            $FFmpegVideoRescaleArgs = @(
                "-vf", "scale=$TargetVideoWidth`:$TargetVideoHeight",
                "-sws_flags", "lanczos" # enable lanczos downscale filter for high quality scaling
            )
        }
        else {
            $FFmpegVideoRescaleArgs = @()
        }

        if (($encoderParameters)) {
            if ($VideoEncoder -eq "libaom-av1") {
                $codecparam = "aom" # why did they do this, it should have been aom-av1-params just like svtav1-params
            }
            else {
                $codecparam = $VideoEncoder.Substring(3) # literally just cut the first 3 letters of the codec, since its gonna be "lib". NVENC does not have a -params option, but that should be obvious to the knowledgeable user so i wont bother checking for it. Same for libvpx-vp9 (?)
            }

            $FFmpegCodecParams = @(
                "-$codecparam-params", "$encoderParameters"
            )
        }
        else {
            $FFmpegCodecParams = @()
        }
    } # end of skip when just trimming

    if (($InputAudioStream -gt 0) -or ($InputVideoStream -gt 0)) {
        $FFmpegMapVideoArgs = @(
            "-map", "0:v:$InputVideoStream"
        )
        $FFmpegMapAudioArgs = @(
            "-map", "0:a:$InputAudioStream"
        )
    }
    else {
        $FFmpegMapVideoArgs = @()
        $FFmpegMapAudioArgs = @()
    }

    if ($PSBoundParameters.ContainsKey("TargetVideoTrim")) {
        if ($TargetVideoTrimEnd -eq "end"){
            $FFmpegTrimArgs = @(
                "-ss", $TargetVideoTrimStart
            )
        }
        else {
            $FFmpegTrimArgs = @(
                "-ss", $TargetVideoTrimStart,
                "-to", $TargetVideoTrimEnd
            )
        }
    }
    else {
        $FFmpegTrimArgs = @()
    }

    if ($fancyrename) {
        # I just realized im converting all files to MP4, regardless of their original file extension. Meh whatever mp4 is good enough
        if ($PSBoundParameters.ContainsKey('TargetVideoSize_MiB')) { $outputfilename = "compressed_$($TargetVideoSize_MiB)mib_$([IO.Path]::GetFileNameWithoutExtension($InputVideo))_$($VideoEncoder)_$($VideoEncoderPreset).mp4" }
        else { $outputfilename = "compressed_$([IO.Path]::GetFileNameWithoutExtension($InputVideo))_$($VideoEncoder)_$($VideoEncoderPreset).mp4" }
    }
    else {
        $outputfilename = "compressed_$([IO.Path]::GetFileNameWithoutExtension($InputVideo)).mp4"
    }

    if (!$outputfolder) {
        $InputVideoFullPath = Resolve-Path -LiteralPath $InputVideo
        $FinalOutputFile = Join-Path $(Split-Path -LiteralPath $InputVideoFullPath) $outputfilename
    }
    elseif (Test-Path -LiteralPath $outputfolder) {
        $FinalOutputFile = Join-Path $outputfolder $outputfilename
    }
    else {
        Write-Error "Output folder is invalid or doesnt exist! Path: $outputfolder" 
        exit
    }
    Write-Host "Output file path: $FinalOutputFile"

    # --- Start Encoding ---
    $EncodeAttemptStartTime = Get-Date

    if ($JustTrimmingEnabled) {
        Write-Host "Just trimming the video..."
        ffmpeg -hide_banner -loglevel error -i $InputVideo @FFmpegMapVideoArgs @FFmpegMapAudioArgs @FFmpegTrimArgs -c:v copy -c:a copy $FinalOutputFile
    }
    else {
        if (-not($VideoEncoder -in "hevc_nvenc", "h264_nvenc")) {
            Write-Host "Start 1st pass..."
            Write-Host "ffmpeg -hide_banner -loglevel error -stats $FFmpegBaseVideoArgs $FFmpegExtraVideoArgs $FFmpegUserArguments $FFmpegMapVideoArgs -pass 1 $FFmpegCodecParams $FFmpegVideoRescaleArgs $FFmpegTrimArgs -an -f null NUL"
            pause
            ffmpeg -hide_banner -loglevel error -stats @FFmpegBaseVideoArgs @FFmpegExtraVideoArgs @FFmpegUserArguments @FFmpegMapVideoArgs -pass 1 @FFmpegCodecParams @FFmpegVideoRescaleArgs @FFmpegTrimArgs -an -f null NUL

            Write-Host "Start final pass..."
            # Write-Host "ffmpeg -hide_banner -loglevel error -stats $FFmpegBaseVideoArgs $FFmpegExtraVideoArgs $FFmpegUserArguments $FFmpegMapVideoArgs $FFmpegMapAudioArgs -pass 2 $FFmpegCodecParams $FFmpegVideoRescaleArgs $FFmpegTrimArgs $FFmpegAudioArgs $FinalOutputFile"
            ffmpeg -hide_banner -loglevel error -stats @FFmpegBaseVideoArgs @FFmpegExtraVideoArgs @FFmpegUserArguments @FFmpegMapVideoArgs @FFmpegMapAudioArgs -pass 2 @FFmpegCodecParams @FFmpegVideoRescaleArgs @FFmpegTrimArgs @FFmpegAudioArgs $FinalOutputFile
        }
        else {
            # i still need to separate the ffmpeg command when using nvenc, since i cant pass "-pass 2" without having done pass 1 first.
            Write-Host "Start final pass..."
            Write-Host "ffmpeg -hide_banner -loglevel error -stats $FFmpegBaseVideoArgs $FFmpegExtraVideoArgs $FFmpegUserArguments $FFmpegMapVideoArgs $FFmpegMapAudioArgs $FFmpegCodecParams $FFmpegVideoRescaleArgs $FFmpegTrimArgs $FFmpegAudioArgs $FinalOutputFile"
            pause
            ffmpeg -hide_banner -loglevel error -stats @FFmpegBaseVideoArgs @FFmpegExtraVideoArgs @FFmpegUserArguments @FFmpegMapVideoArgs @FFmpegMapAudioArgs @FFmpegCodecParams @FFmpegVideoRescaleArgs @FFmpegTrimArgs @FFmpegAudioArgs $FinalOutputFile
        }
    }     

    $EncodingAttempts++

    $MiBresultsize = (Get-Item -LiteralPath $FinalOutputFile).Length / 1MB
    if (($MiBresultsize -ge $TargetVideoSize_MiB) -and -not $PSBoundParameters.ContainsKey('TargetVideoBitrate_kbps') -and -not (-not $PSBoundParameters.ContainsKey('TargetVideoSize_MiB') -and $PSBoundParameters.ContainsKey('BitratePercentageLow'))) {
        if ($RetryEncodingIfTargetNotMet) {
            if ($JustTrimmingEnabled){
                Write-Warning "Resulting file size ($MiBresultsize MiB) is over the target size"
                Write-Warning("Just trimming the video failed to get it down to size. Falling back to re-encoding.")
                
                $fancyrename = ($PSBoundParameters['fancyrename'] -eq $false) ? $PSBoundParameters['fancyrename'] : $true # if fancyrename was bound and set to false, keep it that way. if it wasnt bound or its true enable it since it was disabled automatically
            } 
            else {
                Write-Warning "Resulting file size ($MiBresultsize MiB) is over the target size. Retrying to encode with $RetryEncodingPercentageLowAmount% lower video bitrate..."
                $CurrentRetryEncodingPercentageLowAmount = $CurrentRetryEncodingPercentageLowAmount + $RetryEncodingPercentageLowAmount
            }
            Write-Warning "You can disable automaic retry with -retry 0"

            Remove-Item -LiteralPath $FinalOutputFile -Force -ErrorAction SilentlyContinue
        
            $EndTime = Get-Date
            $ElapsedAttemptTime = ([math]::Round(($EndTime - $EncodeAttemptStartTime).TotalSeconds, 2))
            Write-Host "Attempt $EncodingAttempts took $ElapsedAttemptTime seconds ($($ElapsedAttemptTime / 60) minutes)"
            $TargetVideoBitrate_kbps = $TargetVideoBitrate_kbps * (1 - ($CurrentRetryEncodingPercentageLowAmount / 100))
            Write-Host "=== === Attempt $($EncodingAttempts+1) === ==="
        }
        else {
            Write-Warning "Resulting file size ($MiBresultsize MiB) is over the target size. Automatic encoding retry is disabled! Use -retry 1 if you want to enable it"
            break
        }
    }
    else {
        break
    }

} # --- End of encoding retry loop ---

Remove-Item ".\x265_2pass.log*" -Force -ErrorAction SilentlyContinue # delete 2pass log files
Remove-Item ".\ffmpeg2pass-0.log*" -Force -ErrorAction SilentlyContinue


$EndTime = Get-Date
if ($EncodingAttempts -gt 1) { Write-Host "Attempt $EncodingAttempts took $ElapsedAttemptTime seconds ($($ElapsedAttemptTime / 60) minutes)" }
$ElapsedAttemptTime = ([math]::Round(($EndTime - $EncodeTotalStartTime).TotalSeconds, 2))
Write-Host "Encoding took $ElapsedAttemptTime seconds in total ($($ElapsedAttemptTime / 60) minutes)"

Write-Host "=== === === Video Done! === === ==="