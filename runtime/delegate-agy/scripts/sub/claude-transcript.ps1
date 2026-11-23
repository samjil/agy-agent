# claude-transcript.ps1
# Claude Code 대화 기록 파일(.jsonl) 끝부분을 읽어 최근 모델·effort·컨텍스트 토큰 크기를 가져옵니다.

function Resolve-ClaudeTranscriptPath([string]$SessionId = "") {
    if (-not $SessionId) { return $null }
    try {
        $cleaned = ([string]$SessionId) -replace '[^A-Za-z0-9_-]', ''
        if ($cleaned) {
            $claudeProjectsDir = Join-Path $env:USERPROFILE ".claude\projects"
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
