# switch-sub-agy.ps1
# 소진·쿨다운된 부계정에서 다른 Google 계정으로 agy 를 다시 로그인한 뒤
# refresh.signal 을 남기고 cooldown_until 을 즉시 초기화합니다.
#
# 사용법:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File switch-sub-agy.ps1            # 쿨다운 걸린 슬롯 자동 추천
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File switch-sub-agy.ps1 -Slot sub1
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File switch-sub-agy.ps1 -Slot sub1 -RefreshOnly

param(
    [string]$Slot = "",
    [string]$ModelsConfigDir = "",
    [string]$BridgeDir = "",
    [string]$ComputerName = $env:COMPUTERNAME,
    [switch]$RefreshOnly,
    [scriptblock]$InteractiveRunner = $null,
    [scriptblock]$ConfirmPrompt = $null
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function New-SubLoginCommandContent {
    <# 부계정 runas 세션용 ASCII 전용 login.cmd 내용을 생성해 cmd.exe 코드페이지·중첩 따옴표 오류를 방지한다. #>
    param(
        [Parameter(Mandatory = $true)][string]$SlotId,
        [Parameter(Mandatory = $true)][string]$TargetAccount,
        [string]$AgyBinDir = ""
    )
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("@echo off")
    [void]$lines.Add("title Samjil Agy Sub Login ($SlotId - $TargetAccount)")
    if (-not [string]::IsNullOrWhiteSpace($AgyBinDir)) {
        [void]$lines.Add(('set "PATH={0};%PATH%"' -f $AgyBinDir.Trim()))
    }
    [void]$lines.Add('cd /d "%USERPROFILE%"')
    [void]$lines.Add("echo [samjil] Starting agy login session for $SlotId ($TargetAccount)...")
    [void]$lines.Add("echo [samjil] Please sign in with a DIFFERENT Google account in this session.")
    [void]$lines.Add("call agy")
    [void]$lines.Add('set "AGY_EC=%ERRORLEVEL%"')
    [void]$lines.Add("echo.")
    [void]$lines.Add('if not "%AGY_EC%"=="0" (')
    [void]$lines.Add('    echo [!] agy exited with code %AGY_EC%.')
    [void]$lines.Add("    pause")
    [void]$lines.Add('    exit /b %AGY_EC%')
    [void]$lines.Add(")")
    [void]$lines.Add("echo [+] Login session closed. You may close this window.")
    [void]$lines.Add("pause >nul")
    return (($lines.ToArray()) -join "`r`n") + "`r`n"
}

function Get-SubRunasArguments {
    <# runas.exe 가 중첩 따옴표 없이 부계정 프로필(/profile)로 login.cmd 를 실행하도록 인자 배열을 만든다. #>
    param(
        [Parameter(Mandatory = $true)][string]$TargetAccount,
        [Parameter(Mandatory = $true)][string]$LoginCmdPath
    )
    $cmdSpec = if ($LoginCmdPath -match '\s') {
        'cmd.exe /c \"' + $LoginCmdPath + '\"'
    } else {
        "cmd.exe /c $LoginCmdPath"
    }
    return @("/profile", "/user:$TargetAccount", $cmdSpec)
}

function Select-SubSwitchSlot {
    param(
        [Parameter(Mandatory = $true)]$SubCfg,
        [Parameter(Mandatory = $true)][string]$BridgeRoot,
        [string]$ExplicitSlot = ""
    )
    $slots = @($SubCfg.Slots)
    if ($slots.Count -eq 0) {
        throw "models.local.json 의 sub_accounts.slots 에 등록된 부계정이 없습니다."
    }

    if ($ExplicitSlot) {
        foreach ($s in $slots) {
            if ($s.Id -eq $ExplicitSlot) { return $s }
        }
        $avail = ($slots | ForEach-Object { $_.Id }) -join ", "
        throw "알 수 없는 슬롯 ID 입니다: [$ExplicitSlot] (등록된 슬롯: $avail)"
    }

    $nowUtc = [datetime]::UtcNow
    $cooled = @()
    $errored = @()
    foreach ($s in $slots) {
        $lay = Get-AgySubSlotLayout -BridgeRoot $BridgeRoot -SlotId $s.Id
        $st = Read-BridgeJson $lay.StateFile
        if (-not $st) { continue }
        $isCooled = $false
        $cdVal = if ($st -is [System.Collections.IDictionary]) { $st["cooldown_until"] } else { $st.cooldown_until }
        if ($cdVal) {
            try {
                $cd = [datetime]::Parse([string]$cdVal, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                if ($cd -gt $nowUtc) { $isCooled = $true; $cooled += [pscustomobject]@{ Slot = $s; Until = $cd } }
            } catch {}
        }
        $errVal = if ($st -is [System.Collections.IDictionary]) { $st["last_error"] } else { $st.last_error }
        if (-not $isCooled -and $errVal) {
            $errored += $s
        }
    }

    if ($cooled.Count -gt 0) {
        $best = $cooled | Sort-Object Until | Select-Object -First 1
        return $best.Slot
    }
    if ($errored.Count -gt 0) {
        return $errored[0]
    }
    return $slots[0]
}

function Invoke-SubAccountSwitch {
    param(
        [string]$Slot = "",
        [string]$ModelsConfigDir = "",
        [string]$BridgeDir = "",
        [string]$ComputerName = $env:COMPUTERNAME,
        [switch]$RefreshOnly,
        [scriptblock]$InteractiveRunner = $null,
        [scriptblock]$ConfirmPrompt = $null
    )
    $cfgDir = if ($ModelsConfigDir) {
        $ModelsConfigDir
    } elseif ($env:AGY_MODELS_CONFIG_DIR) {
        $env:AGY_MODELS_CONFIG_DIR
    } else {
        Join-Path (Split-Path $PSScriptRoot -Parent) "config"
    }

    $cfg = Get-AgyModelConfig $cfgDir
    if (-not $cfg -or -not $cfg.SubAccounts -or -not $cfg.SubAccounts.Enabled) {
        throw "sub_accounts 가 활성화되어 있지 않습니다 ($cfgDir\models.local.json)."
    }

    $bridgeRoot = if ($BridgeDir) { $BridgeDir } else { Get-AgySubBridgeRoot $cfg.SubAccounts }
    $slotObj = Select-SubSwitchSlot -SubCfg $cfg.SubAccounts -BridgeRoot $bridgeRoot -ExplicitSlot $Slot
    $layout = Get-AgySubSlotLayout -BridgeRoot $bridgeRoot -SlotId $slotObj.Id
    [void](Initialize-AgySubSlotDirectories $layout)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if (-not $RefreshOnly) {
        Write-Host ("[i] 부계정 [{0}] ({1}\{2}) 로 agy 로그인 세션을 엽니다. 다른 Google 계정으로 로그인한 뒤 창을 닫아 주세요..." -f $slotObj.Id, $ComputerName, $slotObj.WindowsUser) -ForegroundColor Cyan
        if ($null -ne $InteractiveRunner) {
            & $InteractiveRunner $slotObj.WindowsUser $ComputerName
        } else {
            $targetAccount = "{0}\{1}" -f $ComputerName, $slotObj.WindowsUser
            $agyBin = if ($cfg.SubAccounts.AgyBinDir) { [string]$cfg.SubAccounts.AgyBinDir } else { "" }
            if (-not $agyBin) {
                $agyFound = Get-Command agy -ErrorAction SilentlyContinue
                if ($agyFound -and $agyFound.Source) { $agyBin = Split-Path $agyFound.Source -Parent }
            }
            $loginCmdPath = Join-Path $layout.StatusDir "login.cmd"
            $loginCmdText = New-SubLoginCommandContent -SlotId $slotObj.Id -TargetAccount $targetAccount -AgyBinDir $agyBin
            [System.IO.File]::WriteAllText($loginCmdPath, $loginCmdText, $utf8NoBom)
            try {
                $runasArgs = @(Get-SubRunasArguments -TargetAccount $targetAccount -LoginCmdPath $loginCmdPath)
                Write-Host ("[i] 아래에 부계정({0}) 비밀번호를 입력하세요 (입력 중 화면에 표시되지 않습니다)." -f $targetAccount) -ForegroundColor Yellow
                & runas.exe @runasArgs
                if ($LASTEXITCODE -ne 0) {
                    throw "부계정 로그인 실행이 종료 코드 $LASTEXITCODE 로 끝났습니다 ($targetAccount)."
                }
                # runas.exe 는 새 콘솔 창을 띄우고 즉시 반환되므로, 실제 로그인 완료 후 Enter 를 기다린다
                if ($null -ne $ConfirmPrompt) {
                    & $ConfirmPrompt $slotObj.WindowsUser $ComputerName
                } else {
                    [void](Read-Host "새 창($targetAccount)에서 Google 계정 로그인을 마친 뒤 Enter 를 누르세요 (취소: Ctrl+C)")
                }
            } finally {
                Remove-Item -LiteralPath $loginCmdPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $layout.RefreshSignal -Parent) | Out-Null
    [System.IO.File]::WriteAllText($layout.RefreshSignal, ([datetime]::UtcNow.ToString("o") + "`r`n"), $utf8NoBom)
    [void](Clear-AgySubSlotCooldown -BridgeRoot $bridgeRoot -SlotId $slotObj.Id)

    Write-Host ("[+] 부계정 [{0}] ({1}) 갱신 완료: refresh.signal 기록 및 쿨다운 초기화" -f $slotObj.Id, $slotObj.WindowsUser) -ForegroundColor Green
    return [pscustomobject]@{
        SlotId          = $slotObj.Id
        WindowsUser     = $slotObj.WindowsUser
        RefreshSignal   = $layout.RefreshSignal
        CooldownCleared = $true
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }

. (Join-Path $PSScriptRoot "sub\agy-models.ps1")
. (Join-Path $PSScriptRoot "sub\agy-sub-bridge.ps1")

[void](Invoke-SubAccountSwitch -Slot $Slot -ModelsConfigDir $ModelsConfigDir -BridgeDir $BridgeDir -ComputerName $ComputerName -RefreshOnly:$RefreshOnly -InteractiveRunner $InteractiveRunner -ConfirmPrompt $ConfirmPrompt)
