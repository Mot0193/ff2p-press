param(
    [Alias("i")]
    $InputVideo,
    [Alias("s")]
    [float]$TargetVideoSize_MiB = 20,

    [Alias("o")]
    $OutputFolder,
    $FancyRename = $true,

    [Alias("cv")]
    $VideoEncoder = "libx265",
    [Alias("cvpreset")]
    $VideoEncoderPreset,
    [Alias("params")]
    $EncoderParameters,

    [Alias("h")]
    $TargetVideoHeight = -1,
    [Alias("w")]
    $TargetVideoWidth = -1,
    [Alias("trim")]
    $TargetVideoTrim,
    $ForceVideoEncoding = 1,
    [Alias("brv")]
    [float]$TargetVideoBitrate_kbps,
    [Alias("brlow")]
    $BitratePercentageLow = 0,

    [Alias("audiostream")]
    $InputAudioStream = 0,
    [Alias("videostream")]
    $InputVideoStream = 0,

    [Alias("ca")]
    $SelectedAudioEncoder = "libopus",
    [Alias("bra")]
    [float]$TargetAudioBitrate_kbps = "128",
    $ForceAudioEncoding = $false,
    $PrioritizeAudioBitrate = $false,

    [Alias("retry")]
    $RetryEncodingIfTargetNotMet = $true,
    [Alias("retrylow")]
    $RetryEncodingPercentageLowAmount = -1, # negative values enables dynamic mode

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$RemainingFFmpegUserArguments
)
$InformationPreference = "Continue" # The defaults for printing Information and Debug messages are "SilentlyContinue". You can comment/uncomment these lines to enable/disable printing these messages. Or if one of them is uncommented you can use the respective -Debug or -InformationAction parameters to change their defaults
#$DebugPreference = "Continue"

. "$PSScriptRoot/sources/ff2ppress-core.ps1"

$FFmpegArg_JustTrimming = [System.Collections.Generic.List[string]]::new()
$FFmpegArg_Pass1 = [System.Collections.Generic.List[string]]::new()
$FFmpegArg_Pass2 = [System.Collections.Generic.List[string]]::new()

$PassLogDir = Join-Path ([System.IO.Path]::GetTempPath()) "ff2ppress-$PID"
New-Item -ItemType Directory -Force -Path $PassLogDir | Out-Null
$PassLogPrefix = Join-Path $PassLogDir "pass"
$NullDevice = if ($IsWindows) { "NUL" } else { "/dev/null" }

$IsFfmpegAvailable = [bool] (Get-Command -ErrorAction Ignore -Type Application ffmpeg)
if (-not $IsFfmpegAvailable){
    Write-Error "ffmpeg is not installed or not in PATH."
    exit 1
}

try {
    $StartingVideoSize_MiB = (Get-Item -LiteralPath $InputVideo -ErrorAction Stop).Length / 1MB
}
catch {
    Write-Error "An input video file was not specified or does not exist."
    exit 1
}

if ($StartingVideoSize_MiB -le $TargetVideoSize_MiB -and -not $PSBoundParameters.ContainsKey('TargetVideoBitrate_kbps') -and -not (-not $PSBoundParameters.ContainsKey('TargetVideoSize_MiB') -and $PSBoundParameters.ContainsKey('BitratePercentageLow'))) {
    # check if the input video size is under the target size, but only exit if the target bitrate wasnt manually set, and if brlow was used without setting a target size
    Write-Error "Target size can't be higher than the video's current size ($StartingVideoSize_MiB)."
    exit 1
}

# Probe duration
$GetVideoDurationAttempts = 0
while ($null -eq $StartingVideoDuration_sec){
    $GetVideoDurationAttempts++
    switch ($GetVideoDurationAttempts) {
        1 {
            try { [double]$StartingVideoDuration_sec = ffprobe -v error -select_streams v:$InputVideoStream -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 $InputVideo }
            catch { $StartingVideoDuration_sec = $null }
        }
        2 {
            # some videos dont store the duration on a per video stream basis, so its harder to get the duration of a specific stream
            $StreamTagsJson =  ffprobe -v quiet -select_streams v:$InputVideoStream -print_format json -show_entries stream_tags $InputVideo | ConvertFrom-Json

            $TagDurationFull = $StreamTagsJson.streams[0].tags.PSObject.Properties | Where-Object { $_.Name -like "DURATION*" } | Select-Object -Last 1 # mkv files may store the duration of a stream in a "stream" tag, but the "DURATION" tag name itself may have an suffix added to it (for example "DURATION-eng"), so im trying to account for most cases by doing this
            $TagDuration = $TagDurationFull.Value -replace '(\.\d{7})\d*$', '$1' # [TimeSpan]::Parse can only parse 7 digits for the second fractions. This limits the second fractions to 7 digits. Example duration: 00:23:41.920000000
            try {
                $TagDurationParsed = [TimeSpan]::Parse($TagDuration)
                [double]$StartingVideoDuration_sec = $TagDurationParsed.TotalSeconds
            } 
            catch { $StartingVideoDuration_sec = $null }
        }
        3 {
            Write-Warning "Attempting to use the `"format`" video duration, which may or may not result in inaccurate bitrate calculations for the selected video stream"
            try { [double]$StartingVideoDuration_sec = ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $InputVideo }
            catch { $StartingVideoDuration_sec = $null }
        }
        default {
            Write-Error "Could not get the duration of the input video."
            exit 1
        }
    }
}
Write-Debug "Got the video stream duration in $GetVideoDurationAttempts attempt(s)."

# Calculate the duration of the video
if ($PSBoundParameters.ContainsKey("TargetVideoTrim")) {
    $TargetVideoTrimStart, $TargetVideoTrimEnd = $TargetVideoTrim.Split("-")
    [double]$TargetVideoDuration_sec = (ConvertTo-Seconds $TargetVideoTrimEnd) - (ConvertTo-Seconds $TargetVideoTrimStart)
}
else {
    $TargetVideoDuration_sec = $StartingVideoDuration_sec
}

# Probe audio bitrate
$AudioStreamsExist = [bool](ffprobe -v error -select_streams a -show_entries stream=index -of csv $InputVideo)
if ($AudioStreamsExist){
    $StartingAudioBitrate_kbps = Get-AudioBitrate $InputVideo $InputAudioStream $StartingVideoDuration_sec $NullDevice
    if (-not $StartingAudioBitrate_kbps){
        Write-Warning "Could not get the audio bitrate of the input video."
    }
}
else {
    $StartingAudioBitrate_kbps = 0
}

# Probe video bitrate
$VideoStreamsExist = [bool](ffprobe -v error -select_streams v -show_entries stream=index -of csv $InputVideo)
if ($VideoStreamsExist){
    $StartingVideoBitrate_kbps = Get-VideoBitrate $InputVideo $InputVideoStream $StartingVideoDuration_sec $NullDevice
    if (-not $StartingVideoBitrate_kbps){
        Write-Warning "Could not get the video bitrate of the input video."
    }
} 
else {
    Write-Error "Input file has no video streams!"
    exit 1
}

$TargetAudioEncoder = $SelectedAudioEncoder
if ($StartingAudioBitrate_kbps -le $TargetAudioBitrate_kbps) {
    if (-not ($StartingAudioBitrate_kbps -eq 0)){
        if (-not $ForceAudioEncoding) {
            Write-Warning "The input audio bitrate is already below the target ($StartingAudioBitrate_kbps`kbps < $TargetAudioBitrate_kbps`kbps). Copying audio, wont transcode."
            $TargetAudioEncoder = "copy"
        }
        else {
            Write-Warning "Audio bitrate of the input video is lower than the target bitrate. Using $StartingAudioBitrate_kbps`kbps instead of $TargetAudioBitrate_kbps`kbps"
        } 
    }

    $TargetAudioBitrate_kbps = $StartingAudioBitrate_kbps
}

if (-not($TargetVideoBitrate_kbps)){
    if (-not $PSBoundParameters.ContainsKey('TargetVideoSize_MiB') -and $PSBoundParameters.ContainsKey('BitratePercentageLow')){
        if ($StartingVideoBitrate_kbps){
            Write-Host "Target size was not given, using BitratePercentageLow on the input video's bitrate instead"
            $TargetVideoBitrate_kbps = $StartingVideoBitrate_kbps * (1 - ($BitratePercentageLow / 100))
        } 
        else {
            Write-Error "Cannot use BitratePercentageLow if the starting video bitrate is unknown."
            exit 1
        }
    }
    else {
        [float]$TargetVideoSize_kbit = $TargetVideoSize_MiB * 8388.608
        [float]$TargetAudioSize_kbit = $TargetAudioBitrate_kbps * $TargetVideoDuration_sec # the approximate size of the whole audio
        $TargetVideoBitrate_kbps = ($TargetVideoSize_kbit - $TargetAudioSize_kbit) / $TargetVideoDuration_sec # the bitrate for the video would be the targeted size - approximate audio size, all divided by the duration 

        if (($TargetAudioSize_kbit / $TargetVideoSize_kbit) -gt 0.2) {
            if (-not $PrioritizeAudioBitrate) {
                Write-Warning "Audio size would be over 20% of the target size. Re-calculating audio bitrate so audio will take up 20% of the file..."
                # In normal use cases this will hopefully never happen, but with very long videos that are set to very low target sizes this can become an issue.
                $TargetAudioEncoder = $SelectedAudioEncoder # dont forget to also re-select the codec. This gets set once earlier in the code, but just in case the input video audio is both below the target (which will set the codec to "copy") AND the audio will trigger this 20% check, we need to set the codec to the selected one once again
                $TargetAudioBitrate_kbps = 0.2 * $TargetVideoSize_kbit / $TargetVideoDuration_sec
                $TargetAudioSize_kbit = $TargetAudioBitrate_kbps * $TargetVideoDuration_sec
            }
            else {
                Write-Warning "Audio will be over 20% of the target size because you enabled PrioritizeAudioBitrate."
                if (($TargetAudioSize_kbit / $TargetVideoSize_kbit) -gt 1) {
                    Write-Error "Audio would take up more than the entire video target. Either disable PrioritizeAudioBitrate or lower the audio bitrate!"
                    exit 1
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
    Write-Error "Target bitrate is not not set or not higher than 0."
    exit 1
}

Write-Information "[FF2PPRESS Video Info]"
Write-Information ("Starting Video Duration / Size / Bitrate : {0:F2} sec / {1:F2} MiB / {2:F2} kbps" -f $StartingVideoDuration_sec, $StartingVideoSize_MiB, $StartingVideoBitrate_kbps)
Write-Information ("Starting Audio Bitrate                   : {0:F2} kbps" -f $StartingAudioBitrate_kbps)

$EncodingAttempts = 0
$EncodeTotalStartTime = Get-Date
# Start of encoding retry loop
while (1){
    if ($EncodingAttempts -gt 0) {Write-Information "[FF2PPRESS Video Info]"}
    Write-Information ("Target Video Duration / Size / Bitrate   : {0:F2} sec / {1:F2} MiB / {2:F2} kbps" -f $TargetVideoDuration_sec, $TargetVideoSize_MiB, $TargetVideoBitrate_kbps)
    Write-Information ("Target Audio Bitrate                     : {0:F2} kbps" -f $TargetAudioBitrate_kbps)
    Write-Information "[FF2PPRESS Video Info]"

    $FFmpegArg_JustTrimming.AddRange([string[]]@("-hide_banner", "-loglevel", "error", "-i", $InputVideo))
    $FFmpegArg_Pass1.AddRange([string[]]@("-hide_banner", "-loglevel", "error", "-stats", "-i", $InputVideo))
    $FFmpegArg_Pass2.AddRange([string[]]@("-hide_banner", "-loglevel", "error", "-stats", "-i", $InputVideo))

    $EncoderPresetInfo = @{
        "libx265"    = @{ Valid = "ultrafast","superfast","veryfast","faster","fast","medium","slow","slower","veryslow","placebo"; Default = "medium"; EncParamsCompatible = $true }
        "libx264"    = @{ Valid = "ultrafast","superfast","veryfast","faster","fast","medium","slow","slower","veryslow","placebo"; Default = "slower"; EncParamsCompatible = $true }
        "hevc_nvenc" = @{ Valid = "p1","p2","p3","p4","p5","p6","p7"; Default = "p7"; IsNvenc = $true }
        "h264_nvenc" = @{ Valid = "p1","p2","p3","p4","p5","p6","p7"; Default = "p7"; IsNvenc = $true }
        "libaom-av1" = @{ Valid = 0..9  | ForEach-Object { "$_" }; Default = "8"; UsesCpuUsed = $true; EncParamsCompatible = $true }
        "libsvtav1"  = @{ Valid = 0..13 | ForEach-Object { "$_" }; Default = "5"; EncParamsCompatible = $true }
        "libvpx-vp9" = @{ Valid = 0..5  | ForEach-Object { "$_" }; Default = "4"; UsesCpuUsed = $true }
    }
    $EncoderInfo = $EncoderPresetInfo[$VideoEncoder]

    if ($EncoderPresetInfo.ContainsKey($VideoEncoder)) {
        if ($VideoEncoderPreset -notin $EncoderInfo.Valid) {
            if ($PSBoundParameters.ContainsKey('VideoEncoderPreset')) {
                Write-Warning "Preset `"$VideoEncoderPreset`" is not a valid preset for $VideoEncoder, defaulting to preset `"$($EncoderInfo.Default)`"."
            }
            $VideoEncoderPreset = $EncoderInfo.Default
        }
    }
    else {
        Write-Error "Unknown/Unavailable video encoders: $VideoEncoder. Check the available encoders in readme."
        exit 1
    }

    $AudioEncoders = @(
        "libopus",
        "aac",
        "copy"
    )
    if (-not $AudioEncoders.Contains($TargetAudioEncoder)){
        Write-Error "Unknown/Unavailable audio encoders: $TargetAudioEncoder. Check the available encoders in readme."
        exit 1
    }
   
    if (($TargetVideoBitrate_kbps -ge $StartingVideoBitrate_kbps) -and ($EncodingAttempts -lt 1) -and $PSBoundParameters.ContainsKey('TargetVideoTrim')){
        if ($ForceVideoEncoding -eq 0){
            Write-Warning("Target video bitrate is higher than the starting bitrate. Attempting to just trim the video, but this may result in a black video for the first few seconds. You may enable ForceVideoEncoding to re-encode the video even if the target bitrate is higher")
            $JustTrimmingEnabled = $true
            $FancyRename = $false
        }
        else {
            Write-Warning("Target video bitrate is higher than the starting bitrate. You may disable ForceVideoEncoding to try trimming the video without re-encoding.")
            $JustTrimmingEnabled = $false
        }
    }
    else { $JustTrimmingEnabled = $false }


    if ($FancyRename) {
        if (-not $PSBoundParameters.ContainsKey('TargetVideoBitrate_kbps') -and -not (-not $PSBoundParameters.ContainsKey('TargetVideoSize_MiB') -and $PSBoundParameters.ContainsKey('BitratePercentageLow'))) { 
            $outputfilename = "compressed_$($TargetVideoSize_MiB)mib_$([IO.Path]::GetFileNameWithoutExtension($InputVideo))_$($VideoEncoder)_$($VideoEncoderPreset).mp4" 
        }
        else { $outputfilename = "compressed_$([IO.Path]::GetFileNameWithoutExtension($InputVideo))_$($VideoEncoder)_$($VideoEncoderPreset).mp4" }
    }
    else {
        $outputfilename = "compressed_$([IO.Path]::GetFileNameWithoutExtension($InputVideo)).mp4"
    }

    if (-not $OutputFolder) {
        $InputVideoFullPath = Resolve-Path -LiteralPath $InputVideo
        $FinalOutputFile = Join-Path $(Split-Path -LiteralPath $InputVideoFullPath) $outputfilename
    }
    elseif (Test-Path -LiteralPath $OutputFolder) {
        $FinalOutputFile = Join-Path $OutputFolder $outputfilename
    }
    else {
        Write-Error "Output folder is invalid or it does not exist: `"$OutputFolder`"." 
        exit 1
    }

    Write-Host "Output file path: `"$FinalOutputFile`"."

    if ($JustTrimmingEnabled){
        $FFmpegArg_JustTrimming.AddRange( [string[]]@("-map", "0:v:$InputVideoStream") )
        $FFmpegArg_JustTrimming.AddRange( [string[]]@("-map", "0:a:$InputAudioStream") )

        if ($PSBoundParameters.ContainsKey("TargetVideoTrim")) {
            if ($TargetVideoTrimEnd -eq "end"){
                $FFmpegArg_JustTrimming.AddRange( [string[]]@("-ss", $TargetVideoTrimStart) )
            }
            else {
                $FFmpegArg_JustTrimming.AddRange( [string[]]@( "-ss", $TargetVideoTrimStart, "-to", $TargetVideoTrimEnd) )
            }
        }

        $FFmpegArg_JustTrimming.AddRange( [string[]]@("-c:v", "copy", "-c:a", "copy") )
        $FFmpegArg_JustTrimming.Add($FinalOutputFile)
    }
    else {
        $FFmpegArg_Pass1.AddRange( [string[]]@("-c:v", $VideoEncoder) )
        $FFmpegArg_Pass2.AddRange( [string[]]@("-c:v", $VideoEncoder) )

        $FFmpegArg_Pass1.AddRange( [string[]]@("-b:v", "$TargetVideoBitrate_kbps`k") )
        $FFmpegArg_Pass2.AddRange( [string[]]@("-b:v", "$TargetVideoBitrate_kbps`k") )

        if ($EncoderInfo.ContainsKey("UsesCpuUsed")) {
            # libvpx-vp9 and libaom-av1 uses the -cpu-used parameter instead of -preset
            $FFmpegArg_Pass1.AddRange( [string[]]@("-cpu-used", $VideoEncoderPreset, "-row-mt", "1") )
            $FFmpegArg_Pass2.AddRange( [string[]]@("-cpu-used", $VideoEncoderPreset, "-row-mt", "1") )
        }
        else {
            $FFmpegArg_Pass1.AddRange( [string[]]@("-preset", $VideoEncoderPreset) )
            $FFmpegArg_Pass2.AddRange( [string[]]@("-preset", $VideoEncoderPreset) )
        }

        if ($TargetAudioEncoder -in "libopus", "aac", "copy") {
            $FFmpegArg_Pass1.Add("-an") # discard audio on the 1st pass
            $FFmpegArg_Pass2.AddRange( [string[]]@("-c:a", $TargetAudioEncoder, "-b:a", "$TargetAudioBitrate_kbps`k") )
        }
        else {
            Write-Error "Unknown/Unavailable audio encoder. Check the available encoders in readme."
            exit 1
        }
        
        if ($EncoderInfo.ContainsKey("IsNvenc")){
            # enable CBR and fullres multipass for nvenc encoders
            $FFmpegArg_Pass1.AddRange( [string[]]@("-rc", "cbr", "-multipass", "fullres") )
            $FFmpegArg_Pass2.AddRange( [string[]]@("-rc", "cbr", "-multipass", "fullres") )
        }

        $FFmpegArg_Pass1.AddRange( [string[]]@("-map", "0:v:$InputVideoStream") )
        $FFmpegArg_Pass2.AddRange( [string[]]@("-map", "0:v:$InputVideoStream") )

        #$FFmpegArg_Pass1.AddRange( [string[]]@("-map", "0:a:$InputAudioStream") ) # audio is discarded on the 1st pass
        $FFmpegArg_Pass2.AddRange( [string[]]@("-map", "0:a:$InputAudioStream") )

        if (-not $EncoderInfo.ContainsKey("IsNvenc")){
            $FFmpegArg_Pass1.AddRange( [string[]]@("-pass", "1", "-passlogfile", $PassLogPrefix) )
            $FFmpegArg_Pass2.AddRange( [string[]]@("-pass", "2", "-passlogfile", $PassLogPrefix) )
        }

        if ($EncoderParameters) {
            if ($EncoderInfo.ContainsKey("EncParamsCompatible")){
                if ($VideoEncoder -eq "libaom-av1") {
                    $codecparam = "aom" # the correct parameter name for this is -aom-params
                }
                else {
                    $codecparam = $VideoEncoder.Substring(3) # other encoders just start with "lib", so im just cutting the first 3 letters
                }

                $FFmpegArg_Pass1.AddRange( [string[]]@("-$codecparam-params", "$EncoderParameters") )
                $FFmpegArg_Pass2.AddRange( [string[]]@("-$codecparam-params", "$EncoderParameters") )
            }
            else {
                Write-Warning "The video encoder $VideoEncoder does not support parameters via -params. Encoder parameters will be omitted."
            }

        }

        if (($TargetVideoWidth -ne -1) -or ($TargetVideoHeight -ne -1)) {
            $FFmpegArg_Pass1.AddRange( [string[]]@("-vf", "scale=$TargetVideoWidth`:$TargetVideoHeight") )
            $FFmpegArg_Pass2.AddRange( [string[]]@("-vf", "scale=$TargetVideoWidth`:$TargetVideoHeight") )
        }

        if ($PSBoundParameters.ContainsKey("TargetVideoTrim")) {
            $FFmpegArg_Pass1.AddRange( [string[]]@("-ss", $TargetVideoTrimStart ) )
            $FFmpegArg_Pass2.AddRange( [string[]]@("-ss", $TargetVideoTrimStart ) )

            if (-not($TargetVideoTrimEnd -eq "end")){
                $FFmpegArg_Pass1.AddRange( [string[]]@("-to", $TargetVideoTrimEnd) )
                $FFmpegArg_Pass2.AddRange( [string[]]@("-to", $TargetVideoTrimEnd) )
            }
        }

        if ($TargetAudioBitrate_kbps -eq 0){
            $FFmpegArg_Pass2.Add("-an")
            Write-Host "Target Audio Bitrate is 0. Audio streams will be discared."
        }

        if ($RemainingFFmpegUserArguments.Count -gt 0){
            [System.Collections.Generic.List[string]]$FFmpegArgs_Remaining =  Repair-SplitColonTokens $RemainingFFmpegUserArguments
            
            Write-Information "Found remaining ffmpeg arguments: $FFmpegArgs_Remaining"

            $FFmpegArg_Pass1.AddRange($FFmpegArgs_Remaining)
            $FFmpegArg_Pass2.AddRange($FFmpegArgs_Remaining)

            $FFmpegMergableAliasMap = @{
                '-filter:v'   = '-vf'
                '-filter:a'   = '-af'
            }

            Convert-MergableAliases $FFmpegArg_Pass1 $FFmpegMergableAliasMap
            Convert-MergableAliases $FFmpegArg_Pass2 $FFmpegMergableAliasMap

            Merge-FfmpegDuplicateArgs $FFmpegArg_Pass1 @("-vf", "-af")
            Merge-FfmpegDuplicateArgs $FFmpegArg_Pass2 @("-vf", "-af")
        }

        $FFmpegArg_Pass1.AddRange( [string[]]@("-an", "-f", "null", $NullDevice) )
        $FFmpegArg_Pass2.Add($FinalOutputFile)
    }

    if ($JustTrimmingEnabled) { Write-Debug "Final JustTrimming Arg List: $FFmpegArg_JustTrimming" }
    Write-Debug "Final Pass1 Arg List: $FFmpegArg_Pass1"
    Write-Debug "Final Pass2 Arg List: $FFmpegArg_Pass2"
    if ($DebugPreference -eq 'Continue'){ Pause } # if debug is enabled, pause the script so you can see the debug messages before starting to encode

    $EncodeAttemptStartTime = Get-Date

    if ($JustTrimmingEnabled) {
        Write-Host "Just trimming the video..."
        ffmpeg $FFmpegArg_JustTrimming
    }
    else {
        if (-not $EncoderInfo.IsNvenc){
            Write-Host "Start 1st pass..."
            ffmpeg $FFmpegArg_Pass1
        }
        Write-Host "Start final pass..."
        ffmpeg $FFmpegArg_Pass2
    }

    $EncodingAttempts++

    try {
        $ResultingVideoSize_MiB = (Get-Item -LiteralPath $FinalOutputFile -ErrorAction Stop).Length / 1MB
    }
    catch {
        Write-Error "Output file does not exist. An FFmpeg error may have occured."
        exit 1
    }

    if (($ResultingVideoSize_MiB -ge $TargetVideoSize_MiB) -and -not $PSBoundParameters.ContainsKey('TargetVideoBitrate_kbps') -and -not (-not $PSBoundParameters.ContainsKey('TargetVideoSize_MiB') -and $PSBoundParameters.ContainsKey('BitratePercentageLow'))) {
        if ($RetryEncodingIfTargetNotMet) {
            $EndTime = Get-Date
            $ElapsedAttemptTime = ([math]::Round(($EndTime - $EncodeAttemptStartTime).TotalSeconds, 2))

            Write-Warning ("Resulting file size ({0:F2} MiB) is over the target size." -f $ResultingVideoSize_MiB)

            if ($JustTrimmingEnabled){
                Write-Warning ("Just trimming the video failed to get it down to size. Falling back to re-encoding...")
                $FancyRename = ($PSBoundParameters['FancyRename'] -eq $false) ? $PSBoundParameters['FancyRename'] : $true # if FancyRename was bound and set to false, keep it that way. if it wasnt bound or its true enable it since it was disabled automatically
            }
            else {
                if ($RetryEncodingPercentageLowAmount -lt 0){                    
                    # "dynamic" retry bitrate-lowering percentage
                    # this calculates the percentage difference between the target bitrate and resulting bitrate, and rounds it up in 0.5 steps

                    $CurrentRetryEncodingPercentageLowAmount = ([math]::Abs($TargetVideoSize_MiB - $ResultingVideoSize_MiB) / (($TargetVideoSize_MiB + $ResultingVideoSize_MiB) / 2)) * 100
                    $CurrentRetryEncodingPercentageLowAmount = [Math]::Ceiling($CurrentRetryEncodingPercentageLowAmount / 0.5) * 0.5

                    Write-Host ("Retrying to encode with {0:F2}% lower video bitrate (dynamic)..." -f $CurrentRetryEncodingPercentageLowAmount)
                }
                else {
                    $CurrentRetryEncodingPercentageLowAmount = $CurrentRetryEncodingPercentageLowAmount + $RetryEncodingPercentageLowAmount
                    Write-Host "Retrying to encode with $RetryEncodingPercentageLowAmount% lower video bitrate..."
                }
                $TargetVideoBitrate_kbps = $TargetVideoBitrate_kbps * (1 - ($CurrentRetryEncodingPercentageLowAmount / 100))
            }

            Remove-Item -LiteralPath $FinalOutputFile -Force -ErrorAction SilentlyContinue

            Write-Host "Attempt $EncodingAttempts took $ElapsedAttemptTime seconds ($($ElapsedAttemptTime / 60) minutes)"
            Write-Host "=== === Attempt $($EncodingAttempts+1) === ==="
        }
        else {
            Write-Warning ("Resulting file size ({0:F2} MiB) is over the target size. Automatic encoding retry is disabled! Use -retry if you want to enable it." -f $ResultingVideoSize_MiB)
            break
        }
    }
    else {
        break
    }

    $FFmpegArg_JustTrimming.Clear()
    $FFmpegArg_Pass1.Clear()
    $FFmpegArg_Pass2.Clear()
} 
# End of encoding retry loop

Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $PassLogDir

$EndTime = Get-Date
if ($EncodingAttempts -gt 1) { Write-Host "Attempt $EncodingAttempts took $ElapsedAttemptTime seconds ($($ElapsedAttemptTime / 60) minutes)" }
$ElapsedAttemptTime = ([math]::Round(($EndTime - $EncodeTotalStartTime).TotalSeconds, 2))
Write-Host "Encoding took $ElapsedAttemptTime seconds in total ($($ElapsedAttemptTime / 60) minutes)"

Write-Host "=== === === Video Done! === === ==="