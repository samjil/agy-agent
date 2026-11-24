# claude-transcript.ps1
# Claude Code 대화 기록 파일(.jsonl) 끝부분을 읽어 최근 모델·effort·컨텍스트 토큰 크기를 가져옵니다.

function Resolve-ClaudeTranscriptPath([string]$SessionId = "", [string]$ProjectsDir = "") {
    if (-not $SessionId) { return $null }
    try {
        $cleaned = ([string]$SessionId) -replace '[^A-Za-z0-9_-]', ''
        if ($cleaned) {
            $claudeProjectsDir = if ($ProjectsDir) {
                $ProjectsDir
            } elseif ($env:CLAUDE_PROJECTS_DIR) {
                $env:CLAUDE_PROJECTS_DIR
            } else {
                Join-Path $env:USERPROFILE ".claude\projects"
            }
            if (Test-Path -LiteralPath $claudeProjectsDir) {
                $matched = @(Resolve-Path (Join-Path $claudeProjectsDir "*\$cleaned.jsonl") -ErrorAction SilentlyContinue)
                if ($matched.Count -gt 0) {
                    return $matched[0].Path
                }
            }
        }
    } catch {}
    return $null
}

function Get-ClaudeTranscriptLastUsage([string]$SessionId = "", [string]$TranscriptPath = "") {
    $transcriptFile = $null
    if ($TranscriptPath) {
        if (Test-Path -LiteralPath $TranscriptPath) {
            $transcriptFile = (Resolve-Path -LiteralPath $TranscriptPath).Path
        } else {
            $transcriptFile = $TranscriptPath
        }
    } elseif ($SessionId) {
        $transcriptFile = Resolve-ClaudeTranscriptPath -SessionId $SessionId
    }

    if (-not $transcriptFile -or -not (Test-Path -LiteralPath $transcriptFile)) {
        return $null
    }

    # 끝에서부터 64KB 를 먼저 보고, 응답 줄을 못 찾으면 512KB 까지 늘려 다시 본다(질문마다 도는 훅이 쓰므로 빠르게).
    foreach ($tailBytes in @(65536L, 524288L)) {
    try {
        $fs = [System.IO.File]::Open($transcriptFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $len = $fs.Length
            $readBytes = [Math]::Min($len, $tailBytes)
            $offset = $len - $readBytes
            [void]$fs.Seek($offset, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] $readBytes
            $readTotal = 0
            while ($readTotal -lt $readBytes) {
                $r = $fs.Read($buf, $readTotal, $readBytes - $readTotal)
                if ($r -le 0) { break }
                $readTotal += $r
            }
            $rawText = [System.Text.Encoding]::UTF8.GetString($buf, 0, $readTotal)
        } finally {
            $fs.Dispose()
        }

        $lines = $rawText -split "[\r\n]+"
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $ln = $lines[$i]
            # 정규식보다 싼 포함 검사로 먼저 거른다(줄이 수십 KB 일 수 있다)
            if (-not $ln -or $ln.IndexOf('"usage"', [System.StringComparison]::Ordinal) -lt 0 -or $ln.IndexOf('"assistant"', [System.StringComparison]::Ordinal) -lt 0) { continue }
            $ln = $ln.Trim()
            if ($ln -match '"type"\s*:\s*"assistant"' -and -not $ln.Contains('"model":"<synthetic>"')) {
                $mModel = ""
                if ($ln -match '"model"\s*:\s*"([^"]+)"') { $mModel = $Matches[1] }
                if ($mModel -and $mModel -ne '<synthetic>') {
                    $uInp = 0; $uCc = 0; $uCr = 0; $uOut = 0
                    if ($ln -match '"input_tokens"\s*:\s*(\d+)') { $uInp = [long]$Matches[1] }
                    if ($ln -match '"cache_creation_input_tokens"\s*:\s*(\d+)') { $uCc = [long]$Matches[1] }
                    if ($ln -match '"cache_read_input_tokens"\s*:\s*(\d+)') { $uCr = [long]$Matches[1] }
                    if ($ln -match '"output_tokens"\s*:\s*(\d+)') { $uOut = [long]$Matches[1] }
                    $ctx = [long]($uInp + $uCc + $uCr + $uOut)

                    $effort = $null
                    if ($ln -match '"effort"\s*:\s*"([^"]+)"' -and $Matches[1].Trim()) {
                        $effort = $Matches[1].Trim()
                    } else {
                        for ($j = $i - 1; $j -ge 0; $j--) {
                            $prevLn = $lines[$j]
                            if ($prevLn.IndexOf('"effort"', [System.StringComparison]::Ordinal) -lt 0) { continue }
                            if ($prevLn -match '"effort"\s*:\s*"([^"]+)"' -and $Matches[1].Trim()) {
                                $effort = $Matches[1].Trim()
                                break
                            }
                        }
                    }

                    return @{
                        model  = $mModel
                        effort = $effort
                        ctx    = $ctx
                    }
                }
            }
        }
        # 파일 전체를 이미 읽었으면 더 늘려도 같다
        if ($readBytes -ge $len) { break }
    } catch {}
    }

    return $null
}

# 본 세션 아래 subagents\agent-*.jsonl 을 훑어 지금 submit-task 를 호출 중인 서브에이전트를 찾는다.
# tool_use 는 실행 전에 기록되고 tool_result 는 끝난 뒤에 기록되므로, 짝이 아직 없는 submit-task 호출(-Poll/-Cancel 제외)을 가진 파일이 제출자다.
function Find-ClaudeSubmittingSubagent([string]$MainTranscriptPath = "", [int]$WindowSec = 120) {
    try {
        if (-not $MainTranscriptPath) { return $null }
        $subDir = Join-Path ($MainTranscriptPath -replace '\.jsonl$', '') "subagents"
        if (-not (Test-Path -LiteralPath $subDir -PathType Container)) { return $null }

        $cutoff = (Get-Date).AddSeconds(-$WindowSec)
        $candidates = @(Get-ChildItem -LiteralPath $subDir -Filter "agent-*.jsonl" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $cutoff } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 8)

        $tailBytes = 65536L
        foreach ($cand in $candidates) {
            $rawText = $null
            try {
                $fs = [System.IO.File]::Open($cand.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $len = $fs.Length
                    $readBytes = [Math]::Min($len, $tailBytes)
                    $offset = $len - $readBytes
                    [void]$fs.Seek($offset, [System.IO.SeekOrigin]::Begin)
                    $buf = New-Object byte[] $readBytes
                    $readTotal = 0
                    while ($readTotal -lt $readBytes) {
                        $r = $fs.Read($buf, $readTotal, $readBytes - $readTotal)
                        if ($r -le 0) { break }
                        $readTotal += $r
                    }
                    $rawText = [System.Text.Encoding]::UTF8.GetString($buf, 0, $readTotal)
                } finally {
                    $fs.Dispose()
                }
            } catch {
                continue
            }

            if (-not $rawText -or $rawText.IndexOf("submit-task", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }

            $pendingIds = New-Object System.Collections.Generic.List[string]
            $lines = $rawText -split "[\r\n]+"
            foreach ($ln in $lines) {
                if (-not $ln) { continue }
                if ($ln.IndexOf('"tool_use"', [System.StringComparison]::Ordinal) -lt 0) { continue }
                if ($ln.IndexOf("submit-task", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }

                $parsed = $false
                try {
                    $obj = ConvertFrom-Json -InputObject $ln
                    if ($null -ne $obj -and $null -ne $obj.message -and $null -ne $obj.message.content) {
                        $parsed = $true
                        foreach ($blk in @($obj.message.content)) {
                            if ($null -eq $blk -or $blk.type -ne "tool_use") { continue }
                            $tid = [string]$blk.id
                            if (-not $tid -or $tid -notmatch '^toolu_') { continue }
                            $cmd = ""
                            if ($null -ne $blk.input -and $null -ne $blk.input.command) {
                                $cmd = [string]$blk.input.command
                            }
                            if (-not $cmd -or $cmd.IndexOf("submit-task", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
                            if ($cmd -match '(?i)submit-task[^\r\n]*-(?:Poll|Cancel)\b') { continue }
                            [void]$pendingIds.Add($tid)
                        }
                    }
                } catch {}

                if (-not $parsed) {
                    if ($ln -notmatch '(?i)-(?:Poll|Cancel)\b') {
                        foreach ($m in [regex]::Matches($ln, '"id"\s*:\s*"(toolu_[^"]+)"')) {
                            [void]$pendingIds.Add($m.Groups[1].Value)
                        }
                    }
                }
            }

            if ($pendingIds.Count -eq 0) { continue }

            $doneIds = @{}
            foreach ($m in [regex]::Matches($rawText, '"tool_use_id"\s*:\s*"([^"]+)"')) {
                $doneIds[$m.Groups[1].Value] = $true
            }

            $hasPending = $false
            foreach ($tid in $pendingIds) {
                if (-not $doneIds.ContainsKey($tid)) {
                    $hasPending = $true
                    break
                }
            }
            if (-not $hasPending) { continue }

            $agentId = $cand.BaseName -replace '^agent-', ''
            $usage = Get-ClaudeTranscriptLastUsage -TranscriptPath $cand.FullName
            $metaType = ""
            $metaDesc = ""
            $metaPath = Join-Path $subDir ($cand.BaseName + ".meta.json")
            if (Test-Path -LiteralPath $metaPath -PathType Leaf) {
                try {
                    $metaRaw = [System.IO.File]::ReadAllText($metaPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
                    if ($metaRaw) {
                        $metaObj = ConvertFrom-Json -InputObject $metaRaw
                        if ($null -ne $metaObj) {
                            if ($null -ne $metaObj.agentType) { $metaType = [string]$metaObj.agentType }
                            if ($null -ne $metaObj.description) { $metaDesc = [string]$metaObj.description }
                        }
                    }
                } catch {}
            }

            return @{
                id     = $agentId
                model  = if ($usage -and $usage.model) { [string]$usage.model } else { "" }
                effort = if ($usage -and $usage.effort) { [string]$usage.effort } else { "" }
                ctx    = if ($usage -and $null -ne $usage.ctx) { [long]$usage.ctx } else { 0L }
                type   = $metaType
                desc   = $metaDesc
            }
        }
    } catch {}
    return $null
}

# 본 대화 기록 경로와 에이전트 ID 로 서브에이전트 기록(.jsonl) 경로를 만든다.
function Get-ClaudeSubagentTranscriptPath([string]$MainTranscriptPath = "", [string]$AgentId = "") {
    if (-not $MainTranscriptPath -or -not $AgentId) { return $null }
    $safe = ([string]$AgentId) -replace '[^A-Za-z0-9_-]', ''
    if (-not $safe) { return $null }
    $subDir = Join-Path ($MainTranscriptPath -replace '\.jsonl$', '') "subagents"
    return (Join-Path $subDir ("agent-{0}.jsonl" -f $safe))
}

# 위임 한 건에 쓰인 Claude 토큰을 본 세션(및 서브에이전트) 기록에서 집계한다.
# 스트리밍으로 같은 message.id 가 여러 줄 찍히므로 message.id 마다 한 번만 센다.
# 반환: @{ main = @{ in; cache_write; cache_read; out; total; calls }; sub = @{...} or $null } (기록이 없으면 $null)
function Get-ClaudeDelegationUsage([string]$MainTranscriptPath = "", [string]$TaskId = "", [string]$AgentId = "") {
    if (-not $TaskId -and -not $AgentId) { return $null }
    if (-not ('System.Web.Script.Serialization.JavaScriptSerializer' -as [type])) {
        Add-Type -AssemblyName System.Web.Extensions
    }
    $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $js.MaxJsonLength = [int]::MaxValue
    $js.RecursionLimit = 256

    $flattenContent = {
        param($content)
        if ($null -eq $content) { return "" }
        if ($content -is [string]) { return $content }
        if ($content -is [System.Collections.IEnumerable]) {
            $sb = New-Object System.Text.StringBuilder
            foreach ($item in $content) {
                if ($item -is [string]) {
                    [void]$sb.AppendLine($item)
                } elseif ($item -is [System.Collections.IDictionary]) {
                    if ($item["type"] -eq "text" -and $null -ne $item["text"]) {
                        [void]$sb.AppendLine([string]$item["text"])
                    }
                }
            }
            return $sb.ToString()
        }
        return [string]$content
    }

    $toLong = {
        param($val)
        if ($null -eq $val -or $val -is [bool] -or $val -is [string]) { return 0L }
        try { return [long]$val } catch { return 0L }
    }

    $readUsageObj = {
        param($obj, [int]$lineNum)
        if ($null -eq $obj -or -not ($obj -is [System.Collections.IDictionary])) { return $null }
        if ($obj["type"] -ne "assistant") { return $null }
        if ($obj["isApiErrorMessage"] -eq $true) { return $null }
        $msg = $obj["message"]
        if ($null -eq $msg -or -not ($msg -is [System.Collections.IDictionary])) { return $null }
        $model = [string]$msg["model"]
        if (-not $model -or $model -eq "<synthetic>") { return $null }
        $usage = $msg["usage"]
        if ($null -eq $usage -or -not ($usage -is [System.Collections.IDictionary])) { return $null }
        $msgId = if ($msg["id"]) { [string]$msg["id"] } elseif ($obj["uuid"]) { [string]$obj["uuid"] } else { "line_$lineNum" }
        return @{
            id          = $msgId
            in          = (& $toLong $usage["input_tokens"])
            cache_write = (& $toLong $usage["cache_creation_input_tokens"])
            cache_read  = (& $toLong $usage["cache_read_input_tokens"])
            out         = (& $toLong $usage["output_tokens"])
            content     = $msg["content"]
        }
    }

    $mainIn = 0L; $mainCw = 0L; $mainCr = 0L; $mainOut = 0L; $mainCalls = 0
    if ($MainTranscriptPath -and (Test-Path -LiteralPath $MainTranscriptPath -PathType Leaf)) {
        $msgUsage = @{}
        $toolUseToMsgId = @{}
        $toolUseIsBgAgent = @{}
        $matchedIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

        $awaitReview = $false
        $launchMsgId = ""
        $launchIsAsync = $false
        $seenLaunchResult = $false
        $awaitAfterLaunch = $false
        $syncAfterLaunchMsgId = ""
        $awaitAfterHandback = $false
        $handbackAfterMsgId = ""

        $fs = $null; $sr = $null
        try {
            $fs = [System.IO.File]::Open($MainTranscriptPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
            $lineNum = 0
            while ($null -ne ($ln = $sr.ReadLine())) {
                $lineNum++
                if (-not $ln) { continue }
                $isAsstHint = ($ln.IndexOf('"assistant"', [System.StringComparison]::Ordinal) -ge 0)
                $isUserHint = ($ln.IndexOf('"user"', [System.StringComparison]::Ordinal) -ge 0)
                if (-not $isAsstHint -and -not $isUserHint) { continue }
                if (-not $isAsstHint) {
                    $needle = if ($AgentId) { $AgentId } else { $TaskId }
                    if ($needle -and $ln.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) { continue }
                }

                $obj = $null
                try { $obj = $js.DeserializeObject($ln) } catch { continue }
                if ($null -eq $obj -or -not ($obj -is [System.Collections.IDictionary])) { continue }
                $recType = [string]$obj["type"]

                if ($recType -eq "assistant") {
                    $u = & $readUsageObj $obj $lineNum
                    if ($null -eq $u) { continue }
                    $mid = $u.id
                    if ($msgUsage.ContainsKey($mid)) {
                        $prev = $msgUsage[$mid]
                        if ($u.in -gt $prev.in) { $prev.in = $u.in }
                        if ($u.cache_write -gt $prev.cache_write) { $prev.cache_write = $u.cache_write }
                        if ($u.cache_read -gt $prev.cache_read) { $prev.cache_read = $u.cache_read }
                        if ($u.out -gt $prev.out) { $prev.out = $u.out }
                    } else {
                        $msgUsage[$mid] = @{ in = $u.in; cache_write = $u.cache_write; cache_read = $u.cache_read; out = $u.out }
                    }

                    if ($AgentId) {
                        if ($awaitAfterLaunch) {
                            if (-not $syncAfterLaunchMsgId) { $syncAfterLaunchMsgId = $mid }
                            $awaitAfterLaunch = $false
                        }
                        if ($awaitAfterHandback) {
                            if (-not $handbackAfterMsgId) { $handbackAfterMsgId = $mid }
                            $awaitAfterHandback = $false
                        }
                    } else {
                        if ($awaitReview) {
                            [void]$matchedIds.Add($mid)
                            $awaitReview = $false
                        }
                    }

                    $blocks = $u.content
                    if ($blocks -is [System.Collections.IEnumerable] -and -not ($blocks -is [string])) {
                        foreach ($blk in $blocks) {
                            if (-not ($blk -is [System.Collections.IDictionary])) { continue }
                            if ($blk["type"] -ne "tool_use") { continue }
                            $tid = [string]$blk["id"]
                            if (-not $tid) { continue }
                            $toolUseToMsgId[$tid] = $mid
                            $tName = [string]$blk["name"]
                            $tInput = $blk["input"]
                            if ($AgentId) {
                                if (($tName -eq "Agent" -or $tName -eq "Task") -and ($tInput -is [System.Collections.IDictionary])) {
                                    if ($tInput["run_in_background"] -eq $true) { $toolUseIsBgAgent[$tid] = $true }
                                }
                            } else {
                                if ($TaskId -and $null -ne $tInput) {
                                    $inpStr = ""
                                    try { $inpStr = $js.Serialize($tInput) } catch {}
                                    if ($inpStr -and $inpStr.IndexOf($TaskId, [System.StringComparison]::Ordinal) -ge 0) {
                                        [void]$matchedIds.Add($mid)
                                    }
                                }
                            }
                        }
                    }
                } elseif ($recType -eq "user") {
                    $uMsg = $obj["message"]
                    if ($null -eq $uMsg -or -not ($uMsg -is [System.Collections.IDictionary])) { continue }
                    $uContent = $uMsg["content"]
                    if ($AgentId) {
                        $foundLaunchInLine = $false
                        $mentionsAgentInLine = $false
                        if ($uContent -is [string]) {
                            if ($uContent.IndexOf($AgentId, [System.StringComparison]::Ordinal) -ge 0) { $mentionsAgentInLine = $true }
                        } elseif ($uContent -is [System.Collections.IEnumerable]) {
                            foreach ($blk in $uContent) {
                                if ($blk -is [System.Collections.IDictionary] -and $blk["type"] -eq "tool_result") {
                                    $rt = & $flattenContent $blk["content"]
                                    if ($rt -and $rt.IndexOf($AgentId, [System.StringComparison]::Ordinal) -ge 0) {
                                        $mentionsAgentInLine = $true
                                        $tuid = [string]$blk["tool_use_id"]
                                        if (-not $launchMsgId -and $tuid -and $toolUseToMsgId.ContainsKey($tuid) -and $rt.IndexOf(("agentId: " + $AgentId), [System.StringComparison]::Ordinal) -ge 0) {
                                            $launchMsgId = $toolUseToMsgId[$tuid]
                                            $seenLaunchResult = $true
                                            $foundLaunchInLine = $true
                                            $launchIsAsync = $toolUseIsBgAgent.ContainsKey($tuid) -or ($rt.IndexOf("Async agent launched", [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
                                            if (-not $launchIsAsync) { $awaitAfterLaunch = $true }
                                        }
                                    }
                                } elseif ($blk -is [System.Collections.IDictionary] -and $blk["type"] -eq "text" -and $null -ne $blk["text"]) {
                                    if (([string]$blk["text"]).IndexOf($AgentId, [System.StringComparison]::Ordinal) -ge 0) { $mentionsAgentInLine = $true }
                                }
                            }
                        }
                        if ($seenLaunchResult -and -not $foundLaunchInLine -and $mentionsAgentInLine -and -not $handbackAfterMsgId) {
                            $awaitAfterHandback = $true
                        }
                    } else {
                        if ($uContent -is [System.Collections.IEnumerable] -and -not ($uContent -is [string])) {
                            foreach ($blk in $uContent) {
                                if (-not ($blk -is [System.Collections.IDictionary]) -or $blk["type"] -ne "tool_result") { continue }
                                $rt = & $flattenContent $blk["content"]
                                if (-not $rt) { continue }
                                $tuid = [string]$blk["tool_use_id"]
                                if ($tuid -and $toolUseToMsgId.ContainsKey($tuid) -and $rt.IndexOf(("submitted: " + $TaskId), [System.StringComparison]::Ordinal) -ge 0) {
                                    [void]$matchedIds.Add($toolUseToMsgId[$tuid])
                                }
                                if ($rt.IndexOf(("===RESULT=== " + $TaskId), [System.StringComparison]::Ordinal) -ge 0 -or
                                    $rt.IndexOf(("===CANCELLED=== " + $TaskId), [System.StringComparison]::Ordinal) -ge 0 -or
                                    $rt.IndexOf(("===ERROR=== " + $TaskId), [System.StringComparison]::Ordinal) -ge 0) {
                                    $awaitReview = $true
                                }
                            }
                        }
                    }
                }
            }
        } catch {
        } finally {
            if ($sr) { $sr.Dispose() } elseif ($fs) { $fs.Dispose() }
        }

        if ($AgentId) {
            if ($launchMsgId) { [void]$matchedIds.Add($launchMsgId) }
            if ($handbackAfterMsgId) { [void]$matchedIds.Add($handbackAfterMsgId) }
            elseif ($syncAfterLaunchMsgId) { [void]$matchedIds.Add($syncAfterLaunchMsgId) }
        }

        foreach ($mid in $matchedIds) {
            if ($msgUsage.ContainsKey($mid)) {
                $mu = $msgUsage[$mid]
                $mainIn += $mu.in
                $mainCw += $mu.cache_write
                $mainCr += $mu.cache_read
                $mainOut += $mu.out
                $mainCalls++
            }
        }
    }

    $subResult = $null
    if ($AgentId -and $MainTranscriptPath) {
        $subPath = Get-ClaudeSubagentTranscriptPath -MainTranscriptPath $MainTranscriptPath -AgentId $AgentId
        if ($subPath -and (Test-Path -LiteralPath $subPath -PathType Leaf)) {
            $subUsage = @{}
            $fs2 = $null; $sr2 = $null
            try {
                $fs2 = [System.IO.File]::Open($subPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $sr2 = New-Object System.IO.StreamReader($fs2, [System.Text.Encoding]::UTF8)
                $lineNum2 = 0
                while ($null -ne ($ln2 = $sr2.ReadLine())) {
                    $lineNum2++
                    if (-not $ln2 -or $ln2.IndexOf('"assistant"', [System.StringComparison]::Ordinal) -lt 0 -or $ln2.IndexOf('"usage"', [System.StringComparison]::Ordinal) -lt 0) { continue }
                    $obj2 = $null
                    try { $obj2 = $js.DeserializeObject($ln2) } catch { continue }
                    $u2 = & $readUsageObj $obj2 $lineNum2
                    if ($null -eq $u2) { continue }
                    $mid2 = $u2.id
                    if ($subUsage.ContainsKey($mid2)) {
                        $prev2 = $subUsage[$mid2]
                        if ($u2.in -gt $prev2.in) { $prev2.in = $u2.in }
                        if ($u2.cache_write -gt $prev2.cache_write) { $prev2.cache_write = $u2.cache_write }
                        if ($u2.cache_read -gt $prev2.cache_read) { $prev2.cache_read = $u2.cache_read }
                        if ($u2.out -gt $prev2.out) { $prev2.out = $u2.out }
                    } else {
                        $subUsage[$mid2] = @{ in = $u2.in; cache_write = $u2.cache_write; cache_read = $u2.cache_read; out = $u2.out }
                    }
                }
            } catch {
            } finally {
                if ($sr2) { $sr2.Dispose() } elseif ($fs2) { $fs2.Dispose() }
            }

            if ($subUsage.Count -gt 0) {
                $sIn = 0L; $sCw = 0L; $sCr = 0L; $sOut = 0L
                foreach ($v in $subUsage.Values) {
                    $sIn += $v.in; $sCw += $v.cache_write; $sCr += $v.cache_read; $sOut += $v.out
                }
                $subResult = [ordered]@{
                    in         = $sIn
                    cache_write = $sCw
                    cache_read = $sCr
                    out        = $sOut
                    total      = ($sIn + $sCw + $sCr + $sOut)
                    calls      = $subUsage.Count
                }
            }
        }
    }

    if ($mainCalls -eq 0 -and $null -eq $subResult) { return $null }

    return [ordered]@{
        main = [ordered]@{
            in          = $mainIn
            cache_write = $mainCw
            cache_read  = $mainCr
            out         = $mainOut
            total       = ($mainIn + $mainCw + $mainCr + $mainOut)
            calls       = $mainCalls
        }
        sub  = $subResult
    }
}
