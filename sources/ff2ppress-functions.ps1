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