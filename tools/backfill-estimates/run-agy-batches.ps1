# run-agy-batches.ps1
# 질문 원문(extract-questions.js 의 결과)을 묶음으로 agy 에게 보내, 질문마다 "필요한 도구 호출 수와 난이도"를 어림하게 한다.
# 처리 결과(실제 호출 · 토큰 · 시간)는 agy 에게 주지 않는다 — 질문을 받을 때 낼 수 있었던 정보만으로 예상을 만들려고.
#   powershell -File run-agy-batches.ps1 -ItemsPath items.json -OutDir out [-BatchSize 60] [-Parallel 4] [-Max 0]
# 묶음마다 OutDir\bNNN.out.txt(agy 답변)가 생기면 건너뛰므로 중간에 멈춰도 이어서 돌린다.
param(
    [Parameter(Mandatory = $true)][string]$ItemsPath,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [int]$BatchSize = 60,
    [int]$Parallel = 4,
    [int]$Max = 0,                           # 0 이면 전부, 아니면 앞에서부터 이 묶음 수만(시험용)
    [string]$Model = "gemini-3.8-flash-medium"
)
$ErrorActionPreference = "Continue"   # submit-task 의 [브리프 점검] 경고가 stderr 로 나와도 멈추지 않게
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$submit = Join-Path $env:USERPROFILE ".samjil\delegate-agy\scripts\submit-task.ps1"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$items = @([System.IO.File]::ReadAllText($ItemsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
if ($items.Count -eq 1 -and $items[0] -is [System.Array]) { $items = @($items[0]) }   # PowerShell 5.1 은 JSON 배열을 한 덩어리로 돌려준다

$rubric = @'
아래는 사용자가 AI 코딩 도우미(Claude Code)에게 보낸 질문(요청)들이다. 각 질문마다 도우미가 처리하려면 필요했을 작업량을 어림해 JSON 으로만 답한다.
질문 앞의 "이전"은 바로 앞 질문(맥락)이다. 질문이 앞 질문에 이어지는 짧은 지시(예: "고치기", "같게 바꾸기")이면 앞 질문과 비슷한 규모로 본다.

각 질문에 대해 세 값을 정한다.
- direct_calls: 도우미가 직접 처리한다면 필요한 도구 호출 수(파일 읽기 + 파일 수정 + 명령 실행·확인). 설명·의견·확인만 하는 질문이면 0 또는 1.
- delegate_calls: 일부를 다른 도우미에게 맡길 때 도우미 본인의 호출 수 = 제출 1 + 결과 확인 0~2 + 검토 호출(읽기·확인 1~4). 일이 작으면 2~3, 크면 5~8.
- level: low = 설명·확인 또는 한 곳 수정 / medium = 파일 1~3개 수정과 간단한 시험 / high = 원인 찾기 · 여러 파일 설계 · 화면과 서버와 시험을 함께 바꿈.
정수로만, 감으로 부풀리지 않는다. 질문 내용에서 읽히는 만큼만 어림한다.

답변 형식(다른 설명 없이 JSON 배열 하나):
[{"id":123,"direct_calls":3,"delegate_calls":4,"level":"medium"}, ...]
모든 질문에 대해 id 를 그대로 써서 한 항목씩 낸다.

질문 목록(id <TAB> 이전 <TAB> 질문):
'@

$batches = @()
for ($i = 0; $i -lt $items.Count; $i += $BatchSize) {
    $end = [Math]::Min($i + $BatchSize, $items.Count) - 1
    $batches += , @($items[$i..$end])
}
if ($Max -gt 0 -and $batches.Count -gt $Max) { $batches = @($batches[0..($Max - 1)]) }

$todo = New-Object System.Collections.ArrayList
for ($b = 0; $b -lt $batches.Count; $b++) {
    $name = "b{0:D3}" -f $b
    if (Test-Path -LiteralPath (Join-Path $OutDir "$name.out.txt")) { continue }
    $lines = foreach ($it in $batches[$b]) { "{0}`t{1}`t{2}" -f $it.id, ([string]$it.prev), ([string]$it.text) }
    $brief = "@model: $Model`r`n" + $rubric + "`r`n" + ($lines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $OutDir "$name.brief.txt"), $brief, (New-Object System.Text.UTF8Encoding($false)))
    [void]$todo.Add($name)
}
Write-Host ("묶음 {0}개 중 새로 보낼 것 {1}개(묶음당 최대 {2}건)" -f $batches.Count, $todo.Count, $BatchSize)

$running = @{}      # name -> task id
$failed = New-Object System.Collections.ArrayList
while ($todo.Count -gt 0 -or $running.Count -gt 0) {
    while ($todo.Count -gt 0 -and $running.Count -lt $Parallel) {
        $name = [string]$todo[0]; $todo.RemoveAt(0)
        $o = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $submit -File (Join-Path $OutDir "$name.brief.txt") -NoWait 2>&1 | Out-String)
        if ($o -match 'submitted:\s*(claude_\d+_\d+)') { $running[$name] = $Matches[1]; Write-Host "  보냄 $name -> $($Matches[1])" }
        else { Write-Host "  보내기 실패 $name : $($o.Trim())"; [void]$failed.Add($name) }
    }
    foreach ($name in @($running.Keys)) {
        $id = $running[$name]
        $p = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $submit -Poll $id -WaitSeconds 15 2>&1 | Out-String)
        if ($p -match '===RESULT===') {
            $body = ($p -replace '(?s)^.*?===RESULT===[^\r\n]*\r?\n', '')
            [System.IO.File]::WriteAllText((Join-Path $OutDir "$name.out.txt"), $body, (New-Object System.Text.UTF8Encoding($false)))
            $running.Remove($name); Write-Host "  완료 $name"
        } elseif ($p -match '===ERROR===') {
            [System.IO.File]::WriteAllText((Join-Path $OutDir "$name.err.txt"), $p, (New-Object System.Text.UTF8Encoding($false)))
            $running.Remove($name); [void]$failed.Add($name); Write-Host "  오류 $name"
        }
    }
}
Write-Host ("끝. 실패 {0}개: {1}" -f $failed.Count, ($failed -join ", "))
