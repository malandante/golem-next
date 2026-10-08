<#
.SYNOPSIS
Runs the .GOLEM error-report suite under CSpect, one disposable image per case.

.DESCRIPTION
Since issue #4 a failing .GOLEM command returns a NextZXOS error report, so
BASIC stops at the first failure and the old chained suites
(autoexec-negative.txt, autoexec-m3-invalid.txt) can no longer run several
negative cases in one image.

Each negative case writes F4 from BASIC, runs one command that must fail and
then writes F8. The F8 line is reached only if the command returned without an
error, so the expected capture is F4, then whatever MIDI the command itself
sends before failing (BADSYX closes its SysEx and cleans up), and never F8.
Positive controls (TEST1 return, BASIC memory) and the Golem error/timeout
variants are included. Captures, logs and the summary go to -WorkDir. The
image of a passing case is deleted, since each one is a full copy of the base
image; -KeepImages keeps them all.

Requirements: NextBuild 10 with CSpect, MT32NextUartBridge.dll next to
CSpect.exe, UARTReplacement.dll removed, and no other CSpect running.

.EXAMPLE
& .\tools\run-error-suite.ps1
& .\tools\run-error-suite.ps1 -Only smf-badsyx,usage-note-128
#>
param(
    [string]$NextBuildDir = (Join-Path $env:USERPROFILE 'Documents\NextBuildv10'),
    [string]$WorkDir = (Join-Path $env:TEMP ('mt32-error-suite-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [string[]]$Only,
    [int]$CaptureSeconds = 25,
    [switch]$KeepImages
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$cspectDir = Join-Path $NextBuildDir 'Emu\CSpect'
$cspectExe = Join-Path $cspectDir 'CSpect.exe'
$python = Join-Path $NextBuildDir 'Python\python.exe'
$capture = Join-Path $repo 'tools\host\capture_uart.py'
$responder = Join-Path $repo 'tools\host\golem_responder.py'

foreach ($required in @($cspectExe, $python, (Join-Path $cspectDir 'MT32NextUartBridge.dll'))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required file not found: $required" }
}
if (Test-Path -LiteralPath (Join-Path $cspectDir 'UARTReplacement.dll')) {
    throw 'UARTReplacement.dll conflicts with MT32NextUartBridge.dll; remove it first.'
}
if (Get-Process -Name 'CSpect' -ErrorAction SilentlyContinue) {
    throw 'CSpect is already running. Close it before starting the suite.'
}

# Bytes .GOLEM sends on every channel when it cleans up (#3).
$cleanup = @()
for ($channel = 0; $channel -lt 16; $channel++) {
    $status = 0xB0 + $channel
    $cleanup += @($status, 0x40, 0x00, $status, 0x7B, 0x00, $status, 0x78, 0x00)
}
# Bytes .GOLEM play sends before the song (since 2026-10-06): CC64, CC123,
# CC120 and CC7=100 on every channel.
$startCleanup = @()
for ($channel = 0; $channel -lt 16; $channel++) {
    $status = 0xB0 + $channel
    $startCleanup += @($status, 0x40, 0x00, $status, 0x7B, 0x00, $status, 0x78, 0x00, $status, 0x07, 0x64)
}
$test1 = $startCleanup + @(0xC1, 0x00, 0x91, 0x40, 0x64, 0x91, 0x40, 0x00) + $cleanup
$note = @(0x90, 0x3C, 0x64, 0x80, 0x3C, 0x00) + $cleanup

# Name, command line, expected bytes after F4, install the driver?
$negative = @(
    @('smf-format2', '.golem play "c:/BADFMT2.MID"', @(), $true),
    @('smf-smpte', '.golem play "c:/BADSMPTE.MID"', @(), $true),
    @('smf-truncated', '.golem play "c:/BADTRNC.MID"', @(), $true),
    @('smf-vlq', '.golem play "c:/BADVLQ.MID"', @(), $true),
    @('smf-badsyx', '.golem play "c:/BADSYX.MID"', ($startCleanup + @(0xF0, 0x41, 0x10, 0x16, 0xF7) + $cleanup), $true),
    @('file-missing', '.golem play "c:/NOFILE.MID"', @(), $true),
    @('usage-note-128', '.golem note 128 100 1 1', @(), $true),
    @('usage-velocity-0', '.golem note 60 0 1 1', @(), $true),
    @('usage-velocity-128', '.golem note 60 128 1 1', @(), $true),
    @('usage-seconds-0', '.golem note 60 100 0 1', @(), $true),
    @('usage-seconds-61', '.golem note 60 100 61 1', @(), $true),
    @('usage-channel-0', '.golem note 60 100 1 0', @(), $true),
    @('usage-channel-17', '.golem note 60 100 1 17', @(), $true),
    @('usage-note-extra', '.golem note 60 100 1 1 extra', @(), $true),
    @('usage-status-extra', '.golem status extra', @(), $true),
    @('no-driver', '.golem status', @(), $false)
)

$cases = @()
foreach ($item in $negative) {
    $cases += [pscustomobject]@{ Name = $item[0]; Kind = 'negative'; Command = $item[1]; Expected = @(0xF4) + $item[2]; Install = $item[3] }
}
$cases += [pscustomobject]@{ Name = 'ok-return'; Kind = 'builder'; Switch = 'ReturnCheck'; Expected = $test1 + @(0xF9) }
$cases += [pscustomobject]@{ Name = 'ok-memory'; Kind = 'builder'; Switch = 'MemoryCheck'; Expected = $note + $test1 + @(0xF9) }
$cases += [pscustomobject]@{ Name = 'golem-ok'; Kind = 'golem'; Responder = @('--inject-stale') }
$cases += [pscustomobject]@{ Name = 'golem-error'; Kind = 'golem'; Responder = @('--error-index', '0', '--expect-stop') }
$cases += [pscustomobject]@{ Name = 'golem-timeout'; Kind = 'golem'; Responder = @('--timeout-index', '0', '--expect-stop', '--timeout', '80') }
if ($Only) { $cases = @($cases | Where-Object { $Only -contains $_.Name }) }
if (-not $cases) { throw 'No case selected.' }

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Write-Host "Work directory: $WorkDir"

function ConvertTo-HexText([byte[]]$Bytes) { ($Bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ' ' }

function Start-CSpect([string]$Image) {
    Start-Process -FilePath $cspectExe -WorkingDirectory $cspectDir `
        -ArgumentList @('-w3', '-zxnext', '-nextrom', ('-mmc=' + $Image)) -PassThru
}

function Stop-CSpect($Process) {
    if ($null -ne $Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        $Process.WaitForExit(5000) | Out-Null
    }
    Start-Sleep -Seconds 1
}

$results = @()
foreach ($case in $cases) {
    Write-Host ''
    Write-Host "=== $($case.Name)"
    $image = Join-Path $WorkDir "$($case.Name).img"
    $output = Join-Path $WorkDir "$($case.Name).bin"
    $log = Join-Path $WorkDir "$($case.Name).log"
    $passed = $false
    $detail = ''
    $cspect = $null
    try {
        if ($case.Kind -eq 'negative') {
            $basic = Join-Path $WorkDir "$($case.Name).txt"
            $lines = @('#autostart 10', '10 OUT 9275,7: OUT 9531,0')
            if ($case.Install) { $lines += '20 .install "c:/nextzxos/GOLEM.DRV"' }
            $lines += @(
                '30 OUT 5435,64: OUT 4923,244',
                "40 $($case.Command)",
                '50 OUT 5435,64: OUT 4923,248',
                '60 STOP'
            )
            [IO.File]::WriteAllLines($basic, $lines)
            & (Join-Path $PSScriptRoot 'build-player-image.ps1') -NextBuildDir $NextBuildDir `
                -OutputImage $image -AutoexecFile $basic *> $log
        } elseif ($case.Kind -eq 'builder') {
            $builderArgs = @{ NextBuildDir = $NextBuildDir; OutputImage = $image }
            $builderArgs[$case.Switch] = $true
            & (Join-Path $PSScriptRoot 'build-player-image.ps1') @builderArgs *> $log
        } else {
            & (Join-Path $PSScriptRoot 'build-golem-control-image.ps1') -NextBuildDir $NextBuildDir `
                -OutputImage $image *> $log
        }

        $cspect = Start-CSpect $image
        # Windows PowerShell 5.1 turns redirected native stderr into terminating
        # errors under 'Stop'; the verdict comes from exit codes and files.
        $ErrorActionPreference = 'Continue'
        if ($case.Kind -eq 'golem') {
            $text = & $python $responder @($case.Responder) 2>&1
            $text | Out-File -FilePath $log -Append
            $passed = ($LASTEXITCODE -eq 0)
            $detail = ($text | Select-Object -Last 1) -join ''
        } else {
            # Positive controls play music and scan BASIC memory: give them longer.
            $seconds = if ($case.Kind -eq 'builder') { $CaptureSeconds + 20 } else { $CaptureSeconds }
            & $python $capture --capture-only --quiet --capture-timeout $seconds --output $output *>> $log
            $actual = if (Test-Path -LiteralPath $output) { [IO.File]::ReadAllBytes($output) } else { [byte[]]@() }
            $expected = [byte[]]$case.Expected
            $passed = ((ConvertTo-HexText $actual) -eq (ConvertTo-HexText $expected))
            if ($passed) {
                $detail = "$($actual.Length) bytes exactos"
            } elseif ($actual -contains 0xF8 -and $case.Kind -eq 'negative') {
                $detail = 'F8 recibido: el comando volvio sin error'
            } else {
                $detail = "esperado [$(ConvertTo-HexText $expected)] recibido [$(ConvertTo-HexText $actual)]"
            }
        }
    } catch {
        $detail = "error del banco: $($_.Exception.Message)"
    } finally {
        $ErrorActionPreference = 'Stop'
        Stop-CSpect $cspect
    }
    # Each image is a full copy of the 2 GB base image: keep only failures.
    if ($passed -and -not $KeepImages) {
        Remove-Item -LiteralPath $image -Force -ErrorAction SilentlyContinue
    }
    $verdict = if ($passed) { 'PASS' } else { 'FAIL' }
    Write-Host "$verdict  $detail"
    $results += [pscustomobject]@{ Case = $case.Name; Result = $verdict; Detail = $detail }
}

$summary = Join-Path $WorkDir 'summary.txt'
$results | Format-Table -AutoSize | Out-String -Width 200 | Tee-Object -FilePath $summary
$results | ConvertTo-Json | Out-File -FilePath (Join-Path $WorkDir 'summary.json') -Encoding utf8
$failed = @($results | Where-Object { $_.Result -ne 'PASS' }).Count
Write-Host "$($results.Count - $failed)/$($results.Count) PASS. Resumen: $summary"
if ($failed) { exit 1 }
