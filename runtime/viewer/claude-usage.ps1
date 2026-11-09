# claude-usage.ps1
# Claude 세션 기록(transcript, <프로젝트 폴더>\<세션 ID>.jsonl)에서 "Claude 호출 하나"의 사용량을 읽는 함수 모음입니다.
# 뷰어(serve-viewer.ps1)가 dot-source 해서 쓰고, 핸드오프 c2a 메시지 카드에 Claude 쪽 토큰을 보이는 데 씁니다.
#
# 알아 둘 점:
#   - 세션 기록은 응답 하나를 블록(thinking / text / tool_use)마다 한 줄씩 나눠 적는다. 같은 응답(message.id)의 줄들은 usage 가 같으므로 응답 ID 로 한 번만 센다.
#   - usage 의 input_tokens 는 캐시에 못 들어간 일반 입력이고, cache_creation_input_tokens 는 이번 호출에서 캐시에 새로 쓴 입력, cache_read_input_tokens 는 앞서 캐시에 있던
#     대화 맥락을 다시 읽은 양이다. 마지막 것은 호출마다 대화 전체가 거의 그대로 다시 읽히는 값이라 "이 일에 든 양"이 아니라 맥락 크기다.
#     그래서 "이 호출이 한 일"은 출력 + 새 입력(input + cache_creation)으로 보고, 맥락 크기(전부 더한 것)는 따로 둔다.
#   - 어느 호출이 어느 메시지를 만들었는지는 기록에 없다. 메시지 파일이 생긴 시각 바로 앞의 Claude 호출을 그 호출로 짐작한다(도구를 부른 호출이 끝난 뒤에 도구가 파일을 쓰므로).
#     그래서 근사치다: 메시지를 만들기까지 이어진 다른 호출은 빠지고, 한 호출 안에서 여러 일을 했으면 그 전부가 들어간다.

$script:ClaudeUsageCache = @{}

# 세션 ID 로 기록 파일 경로를 찾는다. ID 모양이 아니거나 파일이 없으면 $null. ($ProjectsDir 을 안 주면 Claude 의 프로젝트 폴더)
function Get-ClaudeTranscriptPath([string]$SessionId, [string]$ProjectsDir = "") {
    if ($SessionId -notmatch '^[A-Za-z0-9-]{8,64}$') { return $null }
    if (-not $ProjectsDir) {
        $ProjectsDir = if (Get-Command Get-ClaudeProjectsDir -ErrorAction SilentlyContinue) { Get-ClaudeProjectsDir } else { Join-Path $env:USERPROFILE ".claude\projects" }
    }
    if (-not (Test-Path -LiteralPath $ProjectsDir -PathType Container)) { return $null }
    $m = @(Get-Item -Path (Join-Path $ProjectsDir "*\$SessionId.jsonl") -ErrorAction SilentlyContinue)
    if ($m.Count -gt 0) { return $m[0].FullName }
    return $null
}

# 기록의 한 줄에서 Claude 응답의 사용량을 읽는다. assistant 줄이 아니거나 usage 가 없으면 $null.
# 줄 전체를 JSON 으로 풀지 않고 필요한 값만 정규식으로 꺼낸다(도구 결과가 든 줄이 수백 KB 라 풀면 느리다).
function ConvertFrom-ClaudeUsageLine([string]$Line) {
    if (-not $Line -or -not $Line.Contains('"type":"assistant"')) { return $null }
    $u = $Line.LastIndexOf('"usage":{')   # 따옴표가 이스케이프되지 않은 것만 진짜 구조라, 본문 속 글자와 섞이지 않는다
    if ($u -lt 0) { return $null }
    $seg = $Line.Substring($u, [Math]::Min(1500, $Line.Length - $u))
    $num = { param($key) $m = [regex]::Match($seg, '"' + $key + '":(\d+)'); if ($m.Success) { [long]$m.Groups[1].Value } else { [long]0 } }
    $id = [regex]::Match($Line, '"id":"(msg_[A-Za-z0-9_]+)"')
    $ts = [regex]::Match($Line, '"timestamp":"([^"]+)"')
    if (-not $id.Success -or -not $ts.Success) { return $null }
    $at = [datetime]::MinValue
    if (-not [datetime]::TryParse($ts.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal), [ref]$at)) { return $null }
    $model = [regex]::Match($Line, '"model":"([^"]+)"')
    return [pscustomobject]@{
        Id = $id.Groups[1].Value; At = $at; Model = $(if ($model.Success) { $model.Groups[1].Value } else { "" })
        Input = (& $num "input_tokens"); CacheCreate = (& $num "cache_creation_input_tokens"); CacheRead = (& $num "cache_read_input_tokens"); Output = (& $num "output_tokens")
    }
}

# 기록 파일 하나의 Claude 호출 목록(시각 순, 응답 ID 로 한 번씩). 파일이 바뀌지 않았으면 이전에 읽은 것을 쓴다.
function Get-ClaudeUsageCalls([string]$Path) {
    $fi = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $fi) { return @() }
    $c = $script:ClaudeUsageCache[$Path]
    if ($c -and $c.Length -eq $fi.Length -and $c.Ticks -eq $fi.LastWriteTimeUtc.Ticks) { return $c.Calls }
    $byId = @{}
    $fs = $null; $sr = $null
    try {
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        while ($null -ne ($line = $sr.ReadLine())) {
            $r = ConvertFrom-ClaudeUsageLine $line
            if (-not $r) { continue }
            if ($byId.ContainsKey($r.Id)) { if ($r.At -gt $byId[$r.Id].At) { $byId[$r.Id].At = $r.At } }   # 응답의 마지막 블록이 끝난 시각
            else { $byId[$r.Id] = $r }
        }
    } catch { return @() }
    finally { if ($sr) { $sr.Dispose() } elseif ($fs) { $fs.Dispose() } }
    $calls = @($byId.Values | Sort-Object At)
    $script:ClaudeUsageCache[$Path] = @{ Length = $fi.Length; Ticks = $fi.LastWriteTimeUtc.Ticks; Calls = $calls }
    return $calls
}

# 시각($AtUtc) 바로 앞에 끝난 Claude 호출을 찾아 사용량을 돌려준다. $WindowSeconds 보다 오래 전이면(그 사이에 다른 일이 있었을 수 있다) $null.
#   front   = 출력 + 새 입력                      이 호출이 한 일의 크기(앞에 보이는 값)
#   context = 새 입력 + 캐시에서 다시 읽은 입력     그 호출이 본 대화 맥락의 크기(따로 보이는 값)
function Find-ClaudeCallBefore($Calls, [datetime]$AtUtc, [int]$WindowSeconds = 180) {
    $best = $null
    foreach ($c in @($Calls)) {
        if ($c.At -le $AtUtc.AddSeconds(2)) { $best = $c } else { break }   # 시각 순이라 넘으면 멈춘다
    }
    if (-not $best) { return $null }
    if (($AtUtc - $best.At).TotalSeconds -gt $WindowSeconds) { return $null }
    $newInput = [long]$best.Input + [long]$best.CacheCreate
    return [pscustomobject]@{
        at = $best.At.ToString("yyyy-MM-ddTHH:mm:ssZ"); model = [string]$best.Model
        output = [long]$best.Output; newInput = $newInput; cacheRead = [long]$best.CacheRead
        front = [long]$best.Output + $newInput; context = $newInput + [long]$best.CacheRead
    }
}
