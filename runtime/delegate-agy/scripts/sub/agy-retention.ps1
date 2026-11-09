# agy-retention.ps1
# 위임할 때 만들어진 작업 파일(처리한 지시 · 답변 · 스크린샷 · 번역 캐시 · 백업 · 임시 프롬프트)을 보관 기간(개월)이 지나면 지웁니다.
# 워처가 켜질 때 한 번 부릅니다. 지우는 기준은 파일의 마지막 수정 시각입니다.
# 지우지 않는 것: inbox(아직 처리 전인 작업), delegate.db(위임 기록 DB - 같은 보관 기간으로 워처가 행 단위로 지웁니다), runtime\logs 의 로그 파일.
# 폴더 배치는 agy-layout.ps1 이 정합니다. 테스트: tests\delegate-agy\agy-retention.tests.ps1

function Remove-DelegationFilesOlderThan([string]$RuntimeDir, [int]$Months = 3) {
    $L = Get-AgyLayout $RuntimeDir
    $cutoff = (Get-Date).AddMonths(-$Months)
    $dirs = @($L.ProcessedDir, $L.OutboxDir, $L.StuckDir, $L.ScreenshotsDir, $L.BackupsDir, (Join-Path $L.CacheDir "process-ko"), $L.PromptsDir, $L.RunningDir)
    $removed = 0
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue)) {
            if ($f.LastWriteTime -lt $cutoff) {
                try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $removed++ } catch {}
            }
        }
        # 비게 된 하위 폴더도 정리한다(최상위 폴더 자체는 남긴다).
        foreach ($d in @(Get-ChildItem -LiteralPath $dir -Recurse -Directory -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
            if (-not (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
    return $removed
}
