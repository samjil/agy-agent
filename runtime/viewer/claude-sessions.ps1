# Claude Desktop 코드 탭의 프로젝트(그룹)·세션 조회 및 위임/인수인계 색인 함수 라이브러리
# Windows PowerShell 5.1 호환 (BOM 포함 UTF-8, CRLF)

$ErrorActionPreference = 'Stop'

function Get-ClaudeDesktopDir {
    if (-not [string]::IsNullOrEmpty($env:CLAUDE_DESKTOP_DIR)) {
        return $env:CLAUDE_DESKTOP_DIR
    }
    # 설치 방식에 따라 Desktop 데이터 폴더가 다르다. 세션 폴더(claude-code-sessions)가 실제로 있는 쪽을 고른다.
    $roaming = Join-Path $env:APPDATA 'Claude'
    if (Test-Path -LiteralPath (Join-Path $roaming 'claude-code-sessions')) { return $roaming }
    if (-not [string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
        $dataRoot = Join-Path $env:LOCALAPPDATA 'Claude-Data'
        if (Test-Path -LiteralPath $dataRoot) {
            $found = @(Get-ChildItem -LiteralPath $dataRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'claude-code-sessions') } |
                Sort-Object LastWriteTime -Descending)
            if ($found.Count -gt 0) { return $found[0].FullName }
        }
    }
    return $roaming
}

function Get-ClaudeProjectsDir {
    if (-not [string]::IsNullOrEmpty($env:CLAUDE_PROJECTS_DIR)) {
        return $env:CLAUDE_PROJECTS_DIR
    }
    return (Join-Path $env:USERPROFILE '.claude\projects')
}

function Read-ClaudeDesktopSessions([string]$DesktopDir) {
    if ([string]::IsNullOrEmpty($DesktopDir)) {
        $DesktopDir = Get-ClaudeDesktopDir
    }
    $sessionsDir = Join-Path $DesktopDir 'claude-code-sessions'
    if (-not (Test-Path -LiteralPath $sessionsDir)) {
        return @()
    }

    $sessionFiles = @(Get-ChildItem -LiteralPath $sessionsDir -Filter 'local_*.json' -Recurse -File -ErrorAction SilentlyContinue)
    $results = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($file in $sessionFiles) {
        try {
            $raw = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
            $json = ConvertFrom-Json -InputObject $raw
            if ($null -eq $json) { continue }
            if ([string]::IsNullOrEmpty($json.cliSessionId)) { continue }

            $titleStr = ''
            if ($null -ne $json.title) { $titleStr = [string]$json.title }

            $cwdStr = ''
            if ($null -ne $json.cwd) { $cwdStr = [string]$json.cwd }

            $createdAtLong = [long]0
            if ($null -ne $json.createdAt) {
                [long]::TryParse([string]$json.createdAt, [ref]$createdAtLong) | Out-Null
            }

            $lastActivityAtLong = [long]0
            if ($null -ne $json.lastActivityAt) {
                [long]::TryParse([string]$json.lastActivityAt, [ref]$lastActivityAtLong) | Out-Null
            }

            $archivedBool = [bool]($json.isArchived -eq $true)

            $localIdStr = ''
            if ($null -ne $json.sessionId) { $localIdStr = [string]$json.sessionId }
            elseif ($file.BaseName.StartsWith('local_')) { $localIdStr = $file.BaseName }

            # 포크(대화 갈라내기)한 세션은 원본의 local id 를 가리킨다. Desktop 은 이런 세션을 원본 밑에 묶어 보이지만 그룹 배정 파일에는 따로 적지 않는다.
            $forkedFromStr = ''
            if ($null -ne $json.forkedFromSessionId) { $forkedFromStr = [string]$json.forkedFromSessionId }

            $results.Add(@{
                id             = [string]$json.cliSessionId
                localId        = $localIdStr
                forkedFrom     = $forkedFromStr
                title          = $titleStr
                cwd            = $cwdStr
                createdAt      = $createdAtLong
                lastActivityAt = $lastActivityAtLong
                archived       = $archivedBool
            })
        }
        catch {
            # 깨진 JSON 또는 읽기 실패 파일은 건너뜀
            continue
        }
    }

    return @($results.ToArray())
}

function Read-ClaudeGroups([string]$DesktopDir) {
    if ([string]::IsNullOrEmpty($DesktopDir)) {
        $DesktopDir = Get-ClaudeDesktopDir
    }
    $configFile = Join-Path $DesktopDir 'claude_desktop_config.json'
    if (-not (Test-Path -LiteralPath $configFile)) {
        return @{ Groups = @(); Assignments = @{} }
    }

    $cfg = $null
    try {
        $raw = [System.IO.File]::ReadAllText($configFile, [System.Text.Encoding]::UTF8)
        $cfg = ConvertFrom-Json -InputObject $raw
    }
    catch {
        return @{ Groups = @(); Assignments = @{} }
    }

    if ($null -eq $cfg -or $null -eq $cfg.preferences -or $null -eq $cfg.preferences.epitaxyPrefs) {
        return @{ Groups = @(); Assignments = @{} }
    }

    $epitaxy = $cfg.preferences.epitaxyPrefs
    $groupScopes = $null
    $codeSections = $null

    if ($null -ne $epitaxy.PSObject.Properties['dframe-group-scopes']) {
        $groupScopes = $epitaxy.'dframe-group-scopes'
    }
    if ($null -ne $epitaxy.PSObject.Properties['dframe-code-sections']) {
        $codeSections = $epitaxy.'dframe-code-sections'
    }

    if ($null -eq $groupScopes -and $null -eq $codeSections) {
        return @{ Groups = @(); Assignments = @{} }
    }

    $allGroupsMap = @{}
    $allGroupsOrder = [System.Collections.Generic.List[string]]::new()
    $assignments = @{}

    if ($null -ne $groupScopes) {
        foreach ($scopeProp in $groupScopes.PSObject.Properties) {
            $scopeVal = $scopeProp.Value
            if ($null -eq $scopeVal) { continue }

            if ($null -ne $scopeVal.groups) {
                foreach ($g in $scopeVal.groups) {
                    if ($null -eq $g -or [string]::IsNullOrEmpty($g.id)) { continue }
                    $gid = [string]$g.id
                    $gname = if ($null -ne $g.name) { [string]$g.name } else { '' }
                    if (-not $allGroupsMap.ContainsKey($gid)) {
                        $allGroupsMap[$gid] = $gname
                        $allGroupsOrder.Add($gid)
                    }
                }
            }

            if ($null -ne $scopeVal.assignments) {
                foreach ($assignProp in $scopeVal.assignments.PSObject.Properties) {
                    $key = $assignProp.Name
                    $val = [string]$assignProp.Value
                    if ($key.StartsWith('code:')) {
                        $key = $key.Substring(5)
                    }
                    $assignments[$key] = $val
                }
            }
        }
    }

    $manualSectionOrders = @{}
    $manualSectionList = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $codeSections) {
        foreach ($secScopeProp in $codeSections.PSObject.Properties) {
            $secScopeVal = $secScopeProp.Value
            if ($null -eq $secScopeVal -or $null -eq $secScopeVal.sections) { continue }

            foreach ($sec in $secScopeVal.sections) {
                if ($null -eq $sec) { continue }
                if ([string]$sec.kind -eq 'manual' -and -not [string]::IsNullOrEmpty($sec.id)) {
                    $secId = [string]$sec.id
                    $orderVal = 0
                    if ($null -ne $sec.order) {
                        [int]::TryParse([string]$sec.order, [ref]$orderVal) | Out-Null
                    }
                    if (-not $manualSectionOrders.ContainsKey($secId)) {
                        $manualSectionOrders[$secId] = $orderVal
                        $manualSectionList.Add($secId)
                        if ($null -ne $sec.name -and -not [string]::IsNullOrEmpty([string]$sec.name)) {
                            $allGroupsMap[$secId] = [string]$sec.name
                        }
                    }
                }
            }
        }
    }

    $sortedManualIds = @($manualSectionList | Sort-Object { $manualSectionOrders[$_] })

    $finalGroupIds = [System.Collections.Generic.List[string]]::new()
    $seenGroupIds = @{}

    foreach ($gid in $sortedManualIds) {
        if (-not $seenGroupIds.ContainsKey($gid)) {
            $seenGroupIds[$gid] = $true
            $finalGroupIds.Add($gid)
        }
    }

    foreach ($gid in $allGroupsOrder) {
        if (-not $seenGroupIds.ContainsKey($gid)) {
            $seenGroupIds[$gid] = $true
            $finalGroupIds.Add($gid)
        }
    }

    $finalGroups = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($gid in $finalGroupIds) {
        $name = if ($allGroupsMap.ContainsKey($gid)) { $allGroupsMap[$gid] } else { '' }
        $finalGroups.Add(@{
            id   = $gid
            name = $name
        })
    }

    return @{
        Groups      = @($finalGroups.ToArray())
        Assignments = $assignments
    }
}

function Get-ClaudeSessionTree([string]$DesktopDir) {
    if ([string]::IsNullOrEmpty($DesktopDir)) {
        $DesktopDir = Get-ClaudeDesktopDir
    }

    $rawSessions = @(Read-ClaudeDesktopSessions -DesktopDir $DesktopDir | Where-Object { $null -ne $_ -and -not [string]::IsNullOrEmpty($_.id) })
    if ($rawSessions.Count -eq 0) {
        return @{
            Available = $false
            Projects  = @()
            Ungrouped = @()
        }
    }

    $groupsInfo = Read-ClaudeGroups -DesktopDir $DesktopDir
    $groupsList = @($groupsInfo.Groups)
    $assignments = $groupsInfo.Assignments
    if ($null -eq $assignments) { $assignments = @{} }

    $knownGroupIds = @{}
    foreach ($g in $groupsList) {
        $knownGroupIds[$g.id] = $true
    }

    $groupSessionsMap = @{}
    foreach ($g in $groupsList) {
        $groupSessionsMap[$g.id] = [System.Collections.Generic.List[hashtable]]::new()
    }
    $ungroupedSessions = [System.Collections.Generic.List[hashtable]]::new()

    # local id -> 세션(포크의 원본을 찾는 용도)
    $byLocalId = @{}
    foreach ($s in $rawSessions) { if (-not [string]::IsNullOrEmpty($s.localId)) { $byLocalId[$s.localId] = $s } }

    foreach ($s in $rawSessions) {
        $createdStr = ''
        if ($s.createdAt -gt 0) {
            $createdStr = [DateTimeOffset]::FromUnixTimeMilliseconds($s.createdAt).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss')
        }
        $lastActStr = ''
        if ($s.lastActivityAt -gt 0) {
            $lastActStr = [DateTimeOffset]::FromUnixTimeMilliseconds($s.lastActivityAt).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss')
        }

        $sessionObj = @{
            id              = $s.id
            title           = $s.title
            cwd             = $s.cwd
            created         = $createdStr
            lastActivity    = $lastActStr
            archived        = [bool]$s.archived
            _lastActivityAt = [long]$s.lastActivityAt
        }

        # 자기 배정이 없는 포크는 원본(원본의 원본까지)의 그룹을 따른다. 원본의 CLI 세션 id 는 forkOf 로 알려 화면이 원본 밑에 묶을 수 있게 한다.
        $forkParent = $null
        if (-not [string]::IsNullOrEmpty($s.forkedFrom) -and $byLocalId.ContainsKey($s.forkedFrom)) {
            $forkParent = $byLocalId[$s.forkedFrom]
            $sessionObj.forkOf = [string]$forkParent.id
        }

        $targetGid = $null
        $probe = $s
        for ($hop = 0; ($null -ne $probe) -and ($hop -lt 8); $hop++) {
            $probeLocal = $probe.localId
            if (-not [string]::IsNullOrEmpty($probeLocal) -and $assignments.ContainsKey($probeLocal)) {
                $assignedGid = $assignments[$probeLocal]
                if (-not [string]::IsNullOrEmpty($assignedGid) -and $knownGroupIds.ContainsKey($assignedGid)) { $targetGid = $assignedGid; break }
            }
            $next = $null
            if (-not [string]::IsNullOrEmpty($probe.forkedFrom) -and $byLocalId.ContainsKey($probe.forkedFrom)) { $next = $byLocalId[$probe.forkedFrom] }
            $probe = $next
        }

        if ($null -ne $targetGid -and $groupSessionsMap.ContainsKey($targetGid)) {
            $groupSessionsMap[$targetGid].Add($sessionObj)
        }
        else {
            $ungroupedSessions.Add($sessionObj)
        }
    }

    $projects = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($g in $groupsList) {
        $gid = $g.id
        $sessionsInGroup = $groupSessionsMap[$gid]
        if ($null -ne $sessionsInGroup -and $sessionsInGroup.Count -gt 0) {
            $sorted = @($sessionsInGroup | Sort-Object { $_._lastActivityAt } -Descending)
            $cleanSessions = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($item in $sorted) {
                $cleanSessions.Add(@{
                    id           = $item.id
                    title        = $item.title
                    cwd          = $item.cwd
                    created      = $item.created
                    lastActivity = $item.lastActivity
                    archived     = $item.archived
                    forkOf       = $item.forkOf
                })
            }
            $projects.Add(@{
                id       = $gid
                name     = $g.name
                sessions = @($cleanSessions.ToArray())
            })
        }
    }

    $sortedUngrouped = @($ungroupedSessions | Sort-Object { $_._lastActivityAt } -Descending)
    $cleanUngrouped = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($item in $sortedUngrouped) {
        $cleanUngrouped.Add(@{
            id           = $item.id
            title        = $item.title
            cwd          = $item.cwd
            created      = $item.created
            lastActivity = $item.lastActivity
            archived     = $item.archived
            forkOf       = $item.forkOf
        })
    }

    return @{
        Available = $true
        Projects  = @($projects.ToArray())
        Ungrouped = @($cleanUngrouped.ToArray())
    }
}

function Test-IsEarlierMention([string]$newTs, [string]$newSession, [string]$currTs, [string]$currSession, [hashtable]$sessionCreatedAt) {
    $newHasTs = -not [string]::IsNullOrEmpty($newTs)
    $currHasTs = -not [string]::IsNullOrEmpty($currTs)

    if ($newHasTs -and $currHasTs) {
        $cmp = [string]::CompareOrdinal($newTs, $currTs)
        if ($cmp -lt 0) { return $true }
        if ($cmp -gt 0) { return $false }
    }
    elseif ($newHasTs -and -not $currHasTs) {
        return $true
    }
    elseif (-not $newHasTs -and $currHasTs) {
        return $false
    }

    $newCreated = [long]::MaxValue
    if ($sessionCreatedAt.ContainsKey($newSession)) {
        $newCreated = [long]$sessionCreatedAt[$newSession]
    }
    $currCreated = [long]::MaxValue
    if ($sessionCreatedAt.ContainsKey($currSession)) {
        $currCreated = [long]$sessionCreatedAt[$currSession]
    }

    if ($newCreated -lt $currCreated) { return $true }
    if ($newCreated -gt $currCreated) { return $false }

    $cmpId = [string]::CompareOrdinal($newSession, $currSession)
    if ($cmpId -lt 0) { return $true }
    return $false
}

function Update-ClaudeLinkIndex([string]$IndexFile, [string]$DesktopDir, [string]$ProjectsDir) {
    if ([string]::IsNullOrEmpty($DesktopDir)) {
        $DesktopDir = Get-ClaudeDesktopDir
    }
    if ([string]::IsNullOrEmpty($ProjectsDir)) {
        $ProjectsDir = Get-ClaudeProjectsDir
    }

    $desktopSessions = @(Read-ClaudeDesktopSessions -DesktopDir $DesktopDir | Where-Object { $null -ne $_ -and -not [string]::IsNullOrEmpty($_.id) })
    $sessionCreatedAt = @{}
    $activeSessionIds = @{}
    foreach ($s in $desktopSessions) {
        $sessionCreatedAt[$s.id] = [long]$s.createdAt
        $activeSessionIds[$s.id] = $true
    }

    $targetFiles = @{}
    if (Test-Path -LiteralPath $ProjectsDir) {
        foreach ($sid in @($activeSessionIds.Keys)) {
            $matched = @(Get-Item -Path (Join-Path $ProjectsDir "*\$sid.jsonl") -ErrorAction SilentlyContinue)
            if ($matched.Count -gt 0) {
                $targetFiles[$sid] = $matched[0]
            }
        }
    }

    $filesMap = @{}
    $tasksMap = @{}
    $msgsMap  = @{}

    if (Test-Path -LiteralPath $IndexFile) {
        try {
            $rawIndex = [System.IO.File]::ReadAllText($IndexFile, [System.Text.Encoding]::UTF8)
            $parsed = ConvertFrom-Json -InputObject $rawIndex
            if ($null -ne $parsed -and $parsed.version -eq 1 -and $null -ne $parsed.files -and $null -ne $parsed.tasks -and $null -ne $parsed.msgs) {
                # 메시지 키 형식이 바뀌기 전(msgKeyVer 없음)이나 작업 ID 규칙이 넓어지기 전(taskKeyVer 없음)의 색인은
                # 메시지 연결과 읽은 위치를 버리고 다시 훑는다(읽은 위치부터 이어 훑기만 하면 이미 읽은 기록의 새 모양 ID 는 영영 못 찾는다). 작업 연결은 그대로 둔다.
                $keepMsgs = ($parsed.msgKeyVer -eq 2 -and $parsed.taskKeyVer -eq 2)
                foreach ($prop in $parsed.files.PSObject.Properties) {
                    if (-not $keepMsgs) { continue }
                    $filesMap[$prop.Name] = @{
                        offset = [long]$prop.Value.offset
                        size   = [long]$prop.Value.size
                    }
                }
                foreach ($prop in $parsed.tasks.PSObject.Properties) {
                    $tasksMap[$prop.Name] = @{
                        session = [string]$prop.Value.session
                        ts      = [string]$prop.Value.ts
                    }
                }
                foreach ($prop in $parsed.msgs.PSObject.Properties) {
                    if (-not $keepMsgs) { continue }
                    $msgsMap[$prop.Name] = @{
                        session = [string]$prop.Value.session
                        ts      = [string]$prop.Value.ts
                    }
                }
            }
        }
        catch {
            $filesMap = @{}
            $tasksMap = @{}
            $msgsMap  = @{}
        }
    }

    # Desktop에서 사라진 세션 정리
    $staleFileKeys = @()
    foreach ($k in $filesMap.Keys) {
        if (-not $activeSessionIds.ContainsKey($k)) { $staleFileKeys += $k }
    }
    foreach ($k in $staleFileKeys) { $filesMap.Remove($k) }

    $staleTaskKeys = @()
    foreach ($k in $tasksMap.Keys) {
        if (-not $activeSessionIds.ContainsKey($tasksMap[$k].session)) { $staleTaskKeys += $k }
    }
    foreach ($k in $staleTaskKeys) { $tasksMap.Remove($k) }

    $staleMsgKeys = @()
    foreach ($k in $msgsMap.Keys) {
        if (-not $activeSessionIds.ContainsKey($msgsMap[$k].session)) { $staleMsgKeys += $k }
    }
    foreach ($k in $staleMsgKeys) { $msgsMap.Remove($k) }

    $taskRegex = [regex]::new('claude_\d{9,11}_\d+(?:_[a-z])?')
    # claude_ 로 시작하지 않는 작업 ID(dbtest_<초>_<번호>_easy, claude_sqlitecheck_<초>_solo 처럼 이름을 붙인 것)도 세션에 붙인다.
    # 모양: <이름>_<초 단위 시각 9~11자리>_<번호>[_<꼬리>]. 이름은 영문자로 시작하는 단어를 _ 로 최대 3개 이은 것이다.
    # 성능: 이름·꼬리를 길이로 막고 단어 시작(앞이 영숫자·_ 가 아닌 자리)에서만 시도해서, 수 MB 짜리 한 줄에서도 시작 위치마다 되돌아가 보지 않는다.
    # 줄을 이 정규식으로 바로 훑지 않고 먼저 "_<9~11자리 숫자>_" 가 있는 줄만 거른다(아래 taskHintRegex) — claude_ 가 없는 대부분의 줄은 이 검사 하나로 끝난다.
    $taskRegexAny  = [regex]::new('(?<![A-Za-z0-9_])[A-Za-z][A-Za-z0-9-]{0,30}(?:_[A-Za-z][A-Za-z0-9-]{0,30}){0,2}_\d{9,11}_[A-Za-z0-9]{1,16}(?:_[A-Za-z0-9]{1,16})?')
    $taskHintRegex = [regex]::new('_\d{9,11}_', [System.Text.RegularExpressions.RegexOptions]::Compiled)
    # 채널 이름이 붙은 경로(<채널>/msg/<파일>)는 "채널/파일" 키로, 파일 이름만 나온 경우는 파일 이름 키로 모은다.
    # 서로 다른 채널의 0001-c2a-채널-개통... 처럼 이름이 같은 메시지가 섞여 붙는 것을 막기 위함이다.
    # 채널 이름 앞의 (?<!...) 와 {1,64} 는 성능 때문에 꼭 필요하다: 없으면 수 MB 짜리 한 줄에서 시작 위치마다 줄 끝까지 되돌아가 보느라 시간이 줄 길이의 제곱으로 늘어
    # 스캔이 사실상 멈춘다(8000자 한 줄에 4초, 시험의 수 MB 줄은 끝나지 않았다). 단어가 시작하는 자리에서만, 최대 64자까지만 본다.
    $msgRegex  = [regex]::new('(?:(?<![A-Za-z0-9가-힣_.-])([A-Za-z0-9가-힣_.-]{1,64})(?:\\{1,4}|/)msg(?:\\{1,4}|/))?(\d{4}-(?:c2a|a2c)-[A-Za-z0-9가-힣_-]+\.md)')
    $tsRegex   = [regex]::new('"timestamp"\s*:\s*"([^"]+)"')

    $scannedFilesCount = 0
    $newBytesTotal = [long]0

    foreach ($sid in @($targetFiles.Keys)) {
        $fi = $targetFiles[$sid]
        $fi.Refresh()
        $currentSize = [long]$fi.Length
        $oldOffset = [long]0
        if ($filesMap.ContainsKey($sid)) {
            $oldOffset = [long]$filesMap[$sid].offset
        }

        # 파일이 축소되었으면 처음부터 다시 읽기
        if ($currentSize -lt $oldOffset) {
            $toRemoveTasks = @()
            foreach ($k in $tasksMap.Keys) {
                if ($tasksMap[$k].session -eq $sid) { $toRemoveTasks += $k }
            }
            foreach ($k in $toRemoveTasks) { $tasksMap.Remove($k) }

            $toRemoveMsgs = @()
            foreach ($k in $msgsMap.Keys) {
                if ($msgsMap[$k].session -eq $sid) { $toRemoveMsgs += $k }
            }
            foreach ($k in $toRemoveMsgs) { $msgsMap.Remove($k) }

            $oldOffset = [long]0
        }

        if ($currentSize -le $oldOffset) {
            $filesMap[$sid] = @{
                offset = $oldOffset
                size   = $currentSize
            }
            continue
        }

        $fs = [System.IO.File]::Open($fi.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $bytesProcessedInThisRun = [long]0
        $foundTasks = @{}
        $foundMsgs  = @{}

        try {
            $fs.Seek($oldOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
            $chunkSize = 65536
            $buf = New-Object byte[] $chunkSize
            $ms = New-Object System.IO.MemoryStream
            $streamReadPos = [long]0

            while ($true) {
                $bytesRead = $fs.Read($buf, 0, $chunkSize)
                if ($bytesRead -le 0) { break }

                $startIdx = 0
                while ($startIdx -lt $bytesRead) {
                    $idx = [System.Array]::IndexOf($buf, [byte]10, $startIdx, $bytesRead - $startIdx)
                    if ($idx -ge 0) {
                        $len = $idx - $startIdx
                        if ($len -gt 0) {
                            $ms.Write($buf, $startIdx, $len)
                        }

                        $lineBytes = $ms.ToArray()
                        $ms.SetLength(0)
                        $lineStr = [System.Text.Encoding]::UTF8.GetString($lineBytes)

                        $hasClaude = $lineStr.Contains('claude_')
                        $hasTaskHint = $taskHintRegex.IsMatch($lineStr)
                        if ($hasClaude -or $hasTaskHint -or $lineStr.Contains('-c2a-') -or $lineStr.Contains('-a2c-')) {
                            $tsVal = ''
                            $tsM = $tsRegex.Match($lineStr)
                            if ($tsM.Success) {
                                $tsVal = $tsM.Groups[1].Value
                            }

                            # 예전 모양(claude_<초>_<번호>[_a])은 그대로 먼저 잡고, 이름이 다른 ID 는 새 정규식으로 더 잡는다
                            if ($hasClaude) {
                                foreach ($tm in $taskRegex.Matches($lineStr)) {
                                    $tid = $tm.Value
                                    if (-not $foundTasks.ContainsKey($tid)) {
                                        $foundTasks[$tid] = $tsVal
                                    }
                                }
                            }
                            if ($hasTaskHint) {
                                foreach ($tm in $taskRegexAny.Matches($lineStr)) {
                                    $tid = $tm.Value
                                    if (-not $foundTasks.ContainsKey($tid)) {
                                        $foundTasks[$tid] = $tsVal
                                    }
                                }
                            }

                            if ($lineStr.Contains('-c2a-') -or $lineStr.Contains('-a2c-')) {
                                $mMatches = $msgRegex.Matches($lineStr)
                                foreach ($mm in $mMatches) {
                                    $mid = $mm.Groups[2].Value
                                    if ($mm.Groups[1].Success) { $mid = $mm.Groups[1].Value + '/' + $mid }
                                    if (-not $foundMsgs.ContainsKey($mid)) {
                                        $foundMsgs[$mid] = $tsVal
                                    }
                                }
                            }
                        }

                        $bytesProcessedInThisRun = $streamReadPos + ($idx + 1)
                        $startIdx = $idx + 1
                    }
                    else {
                        $rem = $bytesRead - $startIdx
                        $ms.Write($buf, $startIdx, $rem)
                        $startIdx = $bytesRead
                    }
                }
                $streamReadPos += $bytesRead
            }
            $ms.Dispose()
        }
        finally {
            $fs.Dispose()
        }

        $newOffset = $oldOffset + $bytesProcessedInThisRun
        if ($bytesProcessedInThisRun -gt 0) {
            $newBytesTotal += $bytesProcessedInThisRun
            $scannedFilesCount++
        }

        $filesMap[$sid] = @{
            offset = $newOffset
            size   = $currentSize
        }

        foreach ($tid in $foundTasks.Keys) {
            $tsVal = $foundTasks[$tid]
            if (-not $tasksMap.ContainsKey($tid)) {
                $tasksMap[$tid] = @{ session = $sid; ts = $tsVal }
            }
            else {
                $curr = $tasksMap[$tid]
                if ($curr.session -ne $sid) {
                    if (Test-IsEarlierMention -newTs $tsVal -newSession $sid -currTs $curr.ts -currSession $curr.session -sessionCreatedAt $sessionCreatedAt) {
                        $tasksMap[$tid] = @{ session = $sid; ts = $tsVal }
                    }
                }
            }
        }

        foreach ($mid in $foundMsgs.Keys) {
            $tsVal = $foundMsgs[$mid]
            if (-not $msgsMap.ContainsKey($mid)) {
                $msgsMap[$mid] = @{ session = $sid; ts = $tsVal }
            }
            else {
                $curr = $msgsMap[$mid]
                if ($curr.session -ne $sid) {
                    if (Test-IsEarlierMention -newTs $tsVal -newSession $sid -currTs $curr.ts -currSession $curr.session -sessionCreatedAt $sessionCreatedAt) {
                        $msgsMap[$mid] = @{ session = $sid; ts = $tsVal }
                    }
                }
            }
        }
    }

    $outObj = @{
        version = 1
        msgKeyVer = 2
        taskKeyVer = 2
        updated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        files   = $filesMap
        tasks   = $tasksMap
        msgs    = $msgsMap
    }

    $jsonText = ConvertTo-Json -InputObject $outObj -Depth 5
    $parentDir = Split-Path -Parent $IndexFile
    if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
        [System.IO.Directory]::CreateDirectory($parentDir) | Out-Null
    }

    $tmpFile = "$IndexFile.tmp." + [Guid]::NewGuid().ToString('N')
    $noBomUtf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmpFile, $jsonText, $noBomUtf8)

    if (Test-Path -LiteralPath $IndexFile) {
        Remove-Item -LiteralPath $IndexFile -Force
    }
    Move-Item -LiteralPath $tmpFile -Destination $IndexFile -Force

    return @{
        Scanned  = $scannedFilesCount
        NewBytes = $newBytesTotal
    }
}

$script:ClaudeLinkIndexCache = @{}

function Read-ClaudeLinkIndex([string]$IndexFile) {
    if ([string]::IsNullOrEmpty($IndexFile) -or -not (Test-Path -LiteralPath $IndexFile)) {
        return @{ Tasks = @{}; Msgs = @{}; Updated = '' }
    }
    try {
        $item = Get-Item -LiteralPath $IndexFile -ErrorAction Stop
        $cacheKey = $item.FullName.ToLowerInvariant()
        $cached = $script:ClaudeLinkIndexCache[$cacheKey]
        if ($null -ne $cached -and $cached.Ticks -eq $item.LastWriteTimeUtc.Ticks -and $cached.Length -eq $item.Length) {
            return $cached.Data
        }

        $raw = [System.IO.File]::ReadAllText($IndexFile, [System.Text.Encoding]::UTF8)
        $obj = ConvertFrom-Json -InputObject $raw
        if ($null -eq $obj) {
            return @{ Tasks = @{}; Msgs = @{}; Updated = '' }
        }

        $tasks = @{}
        if ($null -ne $obj.tasks) {
            foreach ($p in $obj.tasks.PSObject.Properties) {
                if ($null -ne $p.Value -and $null -ne $p.Value.session) {
                    $tasks[$p.Name] = [string]$p.Value.session
                }
            }
        }

        $msgs = @{}
        if ($null -ne $obj.msgs) {
            foreach ($p in $obj.msgs.PSObject.Properties) {
                if ($null -ne $p.Value -and $null -ne $p.Value.session) {
                    $msgs[$p.Name] = [string]$p.Value.session
                }
            }
        }

        $updated = ''
        if ($null -ne $obj.updated) {
            $updated = [string]$obj.updated
        }

        $result = @{
            Tasks   = $tasks
            Msgs    = $msgs
            Updated = $updated
        }
        $script:ClaudeLinkIndexCache[$cacheKey] = @{
            Ticks  = $item.LastWriteTimeUtc.Ticks
            Length = $item.Length
            Data   = $result
        }
        return $result
    }
    catch {
        return @{ Tasks = @{}; Msgs = @{}; Updated = '' }
    }
}
