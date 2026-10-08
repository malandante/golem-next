param(
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$nextBuild = if ($env:MT32_NEXT_NEXTBUILD) {
    [IO.Path]::GetFullPath($env:MT32_NEXT_NEXTBUILD)
} else {
    Join-Path $env:USERPROFILE 'Documents\NextBuildv10'
}
$midiFile = if ($env:MT32_NEXT_MI1_MIDI) {
    [IO.Path]::GetFullPath($env:MT32_NEXT_MI1_MIDI)
} else {
    Join-Path $env:USERPROFILE 'Documents\mt32-pi\mimp\MI_1.MID'
}
$muntExe = if ($env:MT32_NEXT_MUNT_EXE) {
    [IO.Path]::GetFullPath($env:MT32_NEXT_MUNT_EXE)
} else {
    Join-Path $env:ProgramFiles 'munt\mt32emu-qt.exe'
}
$cspectDir = Join-Path $nextBuild 'Emu\CSpect'
$cspectExe = Join-Path $cspectDir 'CSpect.exe'
$pythonExe = Join-Path $nextBuild 'Python\python.exe'
$bridgeScript = Join-Path $repo 'tools\host\midi_bridge.py'
$imageBuilder = Join-Path $repo 'tools\build-player-image.ps1'
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempBase ("mt32-next-mi1-demo-{0}-{1}" -f $PID, [guid]::NewGuid().ToString('N'))
$image = Join-Path $tempRoot 'mt32-next-mi1-demo.img'
$bridgeOut = Join-Path $tempRoot 'midi-bridge.out.log'
$bridgeErr = Join-Path $tempRoot 'midi-bridge.err.log'
$bridgeProcess = $null
$muntProcess = $null
$startedMunt = $false
$failed = $false

function Assert-File([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description not found: $Path"
    }
}

function Stop-DemoProcess([Diagnostics.Process]$Process) {
    if ($null -ne $Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        $Process.WaitForExit(3000) | Out-Null
    }
}

try {
    Assert-File $midiFile 'MI_1.MID'
    Assert-File $cspectExe 'CSpect'
    Assert-File $pythonExe 'NextBuild Python'
    Assert-File $bridgeScript 'MIDI bridge'
    Assert-File $imageBuilder 'player image builder'

    $midi = Get-Item -LiteralPath $midiFile
    if ($midi.Length -gt 1048575) {
        throw "MI_1.MID exceeds the current 1048575-byte player limit: $($midi.Length)"
    }
    if (Get-Process -Name 'CSpect' -ErrorAction SilentlyContinue) {
        throw 'CSpect is already running. Close every CSpect window before starting the demo.'
    }

    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    Write-Host 'Preparing a clean disposable NextZXOS image...'
    & $imageBuilder `
        -NextBuildDir $nextBuild `
        -OutputImage $image `
        -MidiFile $midi.FullName `
        -MidiTarget 'MI_1.MID' `
        -Manual
    if ($LASTEXITCODE -ne 0) { throw 'Unable to build the disposable demo image' }
    Assert-File $image 'disposable demo image'

    if ($PrepareOnly) {
        Write-Host 'PASS: the disposable MI_1 demo image was prepared successfully.'
        return
    }

    $plugin = Join-Path $cspectDir 'MT32NextUartBridge.dll'
    Assert-File $plugin 'golem-next CSpect UART plugin'
    if (Test-Path -LiteralPath (Join-Path $cspectDir 'UARTReplacement.dll')) {
        throw 'UARTReplacement.dll conflicts with MT32NextUartBridge.dll; remove it before the demo.'
    }

    $existingMunt = Get-Process -Name 'mt32emu-qt' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $existingMunt) {
        Assert-File $muntExe 'Munt'
        Write-Host 'Starting Munt...'
        $muntProcess = Start-Process -FilePath $muntExe -PassThru
        $startedMunt = $true
        Start-Sleep -Seconds 2
    }

    $outputs = & $pythonExe $bridgeScript --list 2>&1
    $outputText = $outputs -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0 -or $outputText -notmatch '(?i)(MT-32|Munt|Synth Emulator)') {
        throw "Munt MIDI output is not available. Detected outputs:`n$($outputs -join [Environment]::NewLine)"
    }

    Write-Host 'Starting the hidden CSpect-to-Munt bridge...'
    $quotedBridge = '"' + $bridgeScript + '"'
    $bridgeProcess = Start-Process `
        -FilePath $pythonExe `
        -ArgumentList @($quotedBridge, '--quiet', '--stop-after-cleanup') `
        -RedirectStandardOutput $bridgeOut `
        -RedirectStandardError $bridgeErr `
        -WindowStyle Hidden `
        -PassThru
    Start-Sleep -Milliseconds 500
    if ($bridgeProcess.HasExited) {
        $details = @()
        if (Test-Path -LiteralPath $bridgeOut) { $details += Get-Content -LiteralPath $bridgeOut }
        if (Test-Path -LiteralPath $bridgeErr) { $details += Get-Content -LiteralPath $bridgeErr }
        throw "The MIDI bridge stopped before CSpect started:`n$($details -join [Environment]::NewLine)"
    }

    Write-Host ''
    Write-Host 'CSpect will show the two commands to type:'
    Write-Host '  .install c:/nextzxos/GOLEM.DRV'
    Write-Host '  .mt32 play c:/MI_1.MID'
    Write-Host ''
    Write-Host 'Close CSpect when the recording is finished; temporary files will then be deleted.'

    $cspectArgs = @('-w3', '-basickeys', '-zxnext', '-nextrom', ('-mmc=' + $image))
    $cspectProcess = Start-Process `
        -FilePath $cspectExe `
        -WorkingDirectory $cspectDir `
        -ArgumentList $cspectArgs `
        -PassThru
    $cspectProcess.WaitForExit()
} catch {
    $failed = $true
    Write-Error $_
    if (Test-Path -LiteralPath $bridgeOut) {
        Write-Host 'MIDI bridge output:'
        Get-Content -LiteralPath $bridgeOut
    }
    if (Test-Path -LiteralPath $bridgeErr) {
        Write-Host 'MIDI bridge errors:'
        Get-Content -LiteralPath $bridgeErr
    }
} finally {
    Stop-DemoProcess $bridgeProcess
    if ($null -ne $bridgeProcess) {
        & $pythonExe $bridgeScript --panic --quiet
        if ($LASTEXITCODE -ne 0) {
            $failed = $true
            Write-Error 'Unable to send the final MIDI panic to Munt'
        }
    }
    if ($startedMunt -and $null -ne $muntProcess -and -not $muntProcess.HasExited) {
        if (-not $muntProcess.CloseMainWindow() -or -not $muntProcess.WaitForExit(3000)) {
            Stop-DemoProcess $muntProcess
        }
    }

    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $safePrefix = $tempBase.TrimEnd('\') + '\'
    $safeName = [IO.Path]::GetFileName($resolvedTemp)
    if ($resolvedTemp.StartsWith($safePrefix, [StringComparison]::OrdinalIgnoreCase) -and
        $safeName.StartsWith('mt32-next-mi1-demo-', [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $resolvedTemp) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
    } else {
        $failed = $true
        Write-Error "Refusing to remove unexpected temporary path: $resolvedTemp"
    }
}

if ($failed) { exit 1 }
Write-Host 'Demo closed; disposable image and session logs removed.'
