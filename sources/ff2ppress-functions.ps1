function ConvertTo-Seconds {
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

function Repair-SplitColonTokens {
    param([string[]]$Tokens)

    $fixed = [System.Collections.Generic.List[string]]::new()

    $i = 0
    while ($i -lt $Tokens.Count) {
        $tok = $Tokens[$i]
        
        if ($tok -match '^-[\w]+:$' -and ($i + 1) -lt $Tokens.Count) {
            $fixed.Add($tok + $Tokens[$i + 1])
            $i += 2
        } else {
            $fixed.Add($tok)
            $i += 1
        }
    }
    return $fixed.ToArray()
}

function Convert-MergeableAliases {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$ArgList,
        [Parameter(Mandatory)]
        [hashtable]$AliasMap
    )

    for ($i = 0; $i -lt $ArgList.Count; $i++) {
        if ($AliasMap.ContainsKey($ArgList[$i])) {
            $ArgList[$i] = $AliasMap[$ArgList[$i]]
        }
    }
}

function Merge-FfmpegDuplicateArgs {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$ArgList,
        [Parameter(Mandatory)]
        [string[]]$MergeableArgs,
        [string[]]$Separator = ","
    )

    $MergedArgList = [System.Collections.Generic.List[string]]::new()

    $FoundMergeableArgs = @{}

    for ($i = 0; $i -lt $ArgList.Count; $i++) {

        if ($MergeableArgs -contains $ArgList[$i]){

            if ($FoundMergeableArgs.ContainsKey($ArgList[$i])){
                $FoundMergeableArgs[$ArgList[$i]] += $ArgList[$i+1]
            }
            else {
                $FoundMergeableArgs.Add($ArgList[$i], @($ArgList[$i+1]))
            }
        }
    }

    $EmittedArg = @{}
    for ($i = 0; $i -lt $ArgList.Count; $i++) {

        if ($MergeableArgs -contains $ArgList[$i]){
            if (-not $EmittedArg.ContainsKey($ArgList[$i])) {
                $MergedArgList.Add($ArgList[$i])
                $MergedArgList.Add(($FoundMergeableArgs[$ArgList[$i]] -join "$Separator"))
                $EmittedArg[$ArgList[$i]] = $true
            }
            $i++
        }
        else {
            $MergedArgList.Add($ArgList[$i])
        }
    }

    $ArgList.Clear()
    $ArgList.AddRange($MergedArgList)
}

function Get-VideoBitrate {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$Video,
        [int]$VideoStream,
        [double]$VideoDuration,
        [string]$NullDevice
    )

    $Attempts = 1

    while (-not $VideoBitrate){
        switch ($Attempts) {
            1 {
                try { $VideoBitrate = (ffprobe -v error -select_streams v:$VideoStream -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 $Video) / 1000 }
                catch {$VideoBitrate = $null}
            }
            2 {
                [float]$VideoSize_KiB = (ffmpeg -i $Video -map 0:v:$VideoStream -c copy -f null $NullDevice 2>&1 | Out-String -Stream | Select-String -Pattern 'video:(\d+)KiB').Matches[0].Groups[1].Value
                $VideoBitrate = ($VideoSize_KiB * 8.192) / $VideoDuration
            }
            default {
                return $null
            }
        }
        $Attempts++
    }

    return [double]$VideoBitrate
}

function Get-AudioBitrate {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$Video,
        [int]$AudioStream,
        [double]$VideoDuration,
        [string]$NullDevice
    )

    $Attempts = 1

    while (($AudioBitrate -eq "N/A") -or -not $AudioBitrate){
        switch ($Attempts) {
            1 {
                try { $AudioBitrate = (ffprobe -v error -select_streams a:$AudioStream -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 $Video) / 1000 }
                catch {$AudioBitrate = $null}
            }
            2 {
                [float]$AudioSize_KiB = (ffmpeg -i $Video -map 0:a:$AudioStream -c copy -f null $NullDevice 2>&1 | Out-String -Stream | Select-String -Pattern 'audio:(\d+)KiB').Matches[0].Groups[1].Value
                $AudioBitrate = ($AudioSize_KiB * 8.192) / $VideoDuration
            }
            default {
                return $null
            }
        }
        $Attempts++
    }

    return [double]$AudioBitrate
}

function Write-ConsoleProgressBar {
    param(
        [Parameter(Mandatory)][double]$CurrentTime,
        [Parameter(Mandatory)][double]$EndTime,
        [Parameter(Mandatory)][string]$ElapsedTimestamp,

        [int]$PassNumber = 1,
        [int]$BarWidth = 40,
        [char]$Empty_Fill = " ",
        [char]$PassOne_Fill = "░",
        [char]$PassTwo_Fill = "▓"
    )

    $PercentageCompleteRatio = [math]::Clamp($($CurrentTime / $EndTime), 0.0, 1.0)

    $SegmentsFilled = [int][math]::Round($BarWidth * $PercentageCompleteRatio)
    $SegmentsEmpty = $BarWidth - $SegmentsFilled

    <#
    Write-Host
    Write-Host "Current Time: $CurrentTime"
    Write-Host "End Time: $EndTime"
    Write-Host "Complete ratio: $PercentageCompleteRatio"
    Write-Host "SegmentsFilled: $PercentageCompleteRatio"
    Write-Host "SegmentsEmpty: $PercentageCompleteRatio"
    #>

    switch ($PassNumber){
        0 {
            # pass 0 is used for pass 2, but if pass 1 was skipped. For example when NVENC encoders are used
            $ProgressBar = ([string]$PassTwo_Fill * $SegmentsFilled) + ([string]$Empty_Fill * $SegmentsEmpty)
        }
        1 {
            $ProgressBar = ([string]$PassOne_Fill * $SegmentsFilled) + ([string]$Empty_Fill * $SegmentsEmpty)
        }
        2 {
            $ProgressBar = ([string]$PassTwo_Fill * $SegmentsFilled) + ([string]$PassOne_Fill * $SegmentsEmpty)
        }
    }

    [string]$PercentageComplete = [System.Math]::Round($PercentageCompleteRatio * 100)
    # the percentage can vary between 1 and 3 characters (1-9%; 10-99%; 100%). This adds spaces so the percentage string is always 3 characters long, so everything stays aligned and looking nice
    $PrintPercentage = $PercentageComplete + [string]' ' * (3 - $PercentageComplete.Length)


    Write-Host -NoNewline ("`r{0}▏{1}% Pass {2} | Elapsed: {3}" -f $ProgressBar, $PrintPercentage, $PassNumber, $ElapsedTimestamp)
    #Write-Host -NoNewline ("`r{0}▏{1}% Pass {2}" -f $ProgressBar, $PrintPercentage, $PassNumber)
}

function Invoke-FFmpeg {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$FFmpegArgList,
        [Parameter(Mandatory)][double]$VideoDuration,
        [Parameter(Mandatory)][int]$PassNumber,
        [bool]$UseProgressBar = $true
    )
    
    $FFmpeg_Process = [System.Diagnostics.Process]::new()
    $FFmpeg_PSI = [System.Diagnostics.ProcessStartInfo]::new('ffmpeg')
    foreach ($arg in $FFmpegArgList) { $FFmpeg_PSI.ArgumentList.Add($arg) }
    
    if ($UseProgressBar){
        $FFmpeg_PSI.UseShellExecute = $false
        $FFmpeg_PSI.CreateNoWindow = $true
        # redirect stdout to be able to read ffmpeg's -progress output, so our own loading bar can be drawn
        $FFmpeg_PSI.RedirectStandardOutput = $true
        $FFmpeg_PSI.RedirectStandardError = $true

        $FFmpeg_Process = [System.Diagnostics.Process]::new()
        $FFmpeg_Process.StartInfo = $FFmpeg_PSI

        $StdErr_Lines = [System.Collections.Generic.List[string]]::new()
        $StdErr_SourceId = "ffmpeg_stderr_$([guid]::NewGuid())"
        # Subscribe to ErrorDataReceived so ffmpeg errors can still be read
        $null = Register-ObjectEvent -InputObject $FFmpeg_Process -EventName ErrorDataReceived -SourceIdentifier $StdErr_SourceId -MessageData $StdErr_Lines -Action {
            if ($EventArgs.Data) { 
                #Write-Host "`n$($EventArgs.Data)"
                $Event.MessageData.Add($EventArgs.Data)
            }
        }

        try {
            $null = $FFmpeg_Process.Start()
            $FFmpeg_Process.BeginErrorReadLine()

            # start a stopwatch to print the elapsed time on the loading bar
            $ElapsedTime_Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $HighestCurrentTime = 0
            while (-not $FFmpeg_Process.StandardOutput.EndOfStream){
                $StdOut_Line = $FFmpeg_Process.StandardOutput.ReadLine()
                if ([string]::IsNullOrEmpty($StdOut_Line)) { continue }

                if (($StdOut_Line -match "^out_time=((\d+:|.)*)") -and -not($Matches[1] -eq "N/A")){
                    #Write-Host "`n$StdOut_Line"
                    $CurrentTime = ConvertTo-Seconds $Matches[1]

                    # ffmpeg's out_time is not always accurate, sometimes the out time jumps backwards, which makes the progress bar also jump. HighestCurrentTime keeps track of the highest seen time, to at least make the progress bar freeze rather than go backwards
                    if (-not($CurrentTime -gt $HighestCurrentTime)){
                        $CurrentTime = $HighestCurrentTime
                    } else { $HighestCurrentTime = $CurrentTime }

                    Write-ConsoleProgressBar -CurrentTime $CurrentTime -EndTime $VideoDuration -PassNumber $PassNumber -ElapsedTimestamp $ElapsedTime_Stopwatch.Elapsed.ToString('hh\:mm\:ss')
                }
            }
            $FFmpeg_Process.WaitForExit()
        }
        finally {
            if (-not $FFmpeg_Process.HasExited){
                $FFmpeg_Process.Kill($true)
            }
        }

        if ($FFmpeg_Process.ExitCode -ne 0) {
            # if ffmpeg exits with an error, write the exit code
            Write-Host ""
            Write-Error "ffmpeg exited with code $($FFmpeg_Process.ExitCode)"
            # print ffmpeg's error
            Write-Host $($StdErr_Lines -join [Environment]::NewLine) -ForegroundColor Red
            return $FFmpeg_Process.ExitCode
        }

        Unregister-Event -SourceIdentifier $StdErr_SourceId
        Remove-Job -Name $StdErr_SourceId -Force # Register-ObjectEvent also creates a job apparently, which we can remove after we've unsubscribed.
    }
    else {
        $FFmpeg_Process.StartInfo = $FFmpeg_PSI

        if ($PassNumber -eq 1){
            Write-Host "Start 1st pass..."
        }
        else {
            Write-Host "Start final pass..."
        }
        try {
            $null = $FFmpeg_Process.Start()
            $FFmpeg_Process.WaitForExit()
        }
        finally {
            if (-not $FFmpeg_Process.HasExited){
                $FFmpeg_Process.Kill($true)
            }
        }
    }

    return $FFmpeg_Process.ExitCode
}