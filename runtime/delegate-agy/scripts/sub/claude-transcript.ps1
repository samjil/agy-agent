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

    try {
        $fs = [System.IO.File]::Open($transcriptFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $len = $fs.Length
            $readBytes = [Math]::Min($len, 524288L)
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
            $ln = $lines[$i].Trim()
            if (-not $ln -or -not ($ln -match '"usage"')) { continue }
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
                            $prevLn = $lines[$j].Trim()
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
    } catch {}

    return $null
}
