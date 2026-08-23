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

function Convert-MergableAliases {
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
        [string[]]$MergableArgs
    )

    $MergedArgList = [System.Collections.Generic.List[string]]::new()

    $FoundMergableArgs = @{}

    for ($i = 0; $i -lt $ArgList.Count; $i++) {

        if ($MergableArgs -contains $ArgList[$i]){

            if ($FoundMergableArgs.ContainsKey($ArgList[$i])){
                $FoundMergableArgs[$ArgList[$i]] += $ArgList[$i+1]
            }
            else {
                $FoundMergableArgs.Add($ArgList[$i], @($ArgList[$i+1]))
            }
        }
    }

    $EmittedArg = @{}
    for ($i = 0; $i -lt $ArgList.Count; $i++) {

        if ($MergableArgs -contains $ArgList[$i]){
            if (-not $EmittedArg.ContainsKey($ArgList[$i])) {
                $MergedArgList.Add($ArgList[$i])
                $MergedArgList.Add(($FoundMergableArgs[$ArgList[$i]] -join ","))
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