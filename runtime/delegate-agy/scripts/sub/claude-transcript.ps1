# claude-transcript.ps1
# Claude Code 대화 기록 파일(.jsonl) 끝부분을 읽어 최근 모델·effort·컨텍스트 토큰 크기를 가져옵니다.

function Get-ClaudeTranscriptLastUsage([string]$SessionId = "", [string]$TranscriptPath = "") {
    $transcriptFile = $null
    if ($TranscriptPath) {
        if (Test-Path -LiteralPath $TranscriptPath) {
            $transcriptFile = (Resolve-Path -LiteralPath $TranscriptPath).Path
        } else {
            $transcriptFile = $TranscriptPath
        }
    } elseif ($SessionId) {
        try {
            $cleaned = ([string]$SessionId) -replace '[^A-Za-z0-9_-]', ''
            if ($cleaned) {
                $claudeProjectsDir = Join-Path $env:USERPROFILE ".claude\projects"
                if (Test-Path -LiteralPath $claudeProjectsDir) {
                    $matched = @(Resolve-Path (Join-Path $claudeProjectsDir "*\$cleaned.jsonl") -ErrorAction SilentlyContinue)
                    if ($matched.Count -gt 0) {
                        $transcriptFile = $matched[0].Path
                    }
                }
            }
        } catch {}
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
