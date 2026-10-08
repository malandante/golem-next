param(
    [string]$NextBuildDir = (Join-Path $env:USERPROFILE 'Documents\NextBuildv10'),
    [string]$OutputImage,
    [string]$MidiFile,
    [string]$MidiTarget = 'USER.MID',
    [switch]$Manual,
    [ValidateSet('TEST0.MID', 'TEST1.MID', 'TESTCAN.MID', 'TESTSYX.MID', 'TESTSAB.MID', 'TESTTIM.MID',
        'BADFMT2.MID', 'BADSMPTE.MID', 'BADTRNC.MID', 'BADVLQ.MID', 'BADSYX.MID')]
    [string]$Fixture = 'TEST1.MID',
    [switch]$NegativeSuite,
    [ValidateSet('None', 'Note', 'Invalid', 'Cancel')]
    [string]$M3Suite = 'None',
    [ValidateRange(0, 3)]
    [int]$CpuSpeed = 0,
    # Append .uninstall and an F9 marker after play to prove the command
    # returned to BASIC (issue #1). Works with -Fixture or -MidiFile.
    [switch]$ReturnCheck,
    # Run status, note and play with a 9000-byte BASIC string over
    # $6000-$7FFF and emit F9 only if it is intact, F8 otherwise (issue #2).
    [switch]$MemoryCheck,
    # Use this BASIC text as autoexec (tools/run-error-suite.ps1 generates one
    # per negative case, because each failing command now stops BASIC).
    [string]$AutoexecFile
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$build = Join-Path $repo 'build'
if (-not $OutputImage) { $OutputImage = Join-Path $build 'mt32-next-player.img' }
$OutputImage = [IO.Path]::GetFullPath($OutputImage)
$baseImage = Join-Path $NextBuildDir 'img\cspect-next-2gb.img'
$python = Join-Path $NextBuildDir 'Python\python.exe'
$converter = Join-Path $NextBuildDir 'Scripts\txt2nextbasic.py'
$hdfmonkey = Join-Path $NextBuildDir 'Tools\hdfmonkey.exe'
$autoexecSource = Join-Path $repo 'tests\integration\cspect\autoexec-player.txt'

if (($MidiFile -and $NegativeSuite) -or
    ($M3Suite -ne 'None' -and ($MidiFile -or $NegativeSuite))) {
    throw '-MidiFile, -NegativeSuite and -M3Suite are mutually exclusive'
}
if ($NegativeSuite -or $M3Suite -eq 'Invalid') {
    throw 'Since #4 each failing .GOLEM command stops BASIC; use tools\run-error-suite.ps1 (one image per case)'
}
if ($AutoexecFile -and ($MemoryCheck -or $ReturnCheck -or $Manual -or $M3Suite -ne 'None')) {
    throw '-AutoexecFile cannot be combined with -MemoryCheck, -ReturnCheck, -Manual or -M3Suite'
}
if ($MemoryCheck -and ($ReturnCheck -or $NegativeSuite -or $M3Suite -ne 'None' -or $MidiFile -or $Manual)) {
    throw '-MemoryCheck is a standalone TEST1 suite'
}
if ($ReturnCheck -and ($NegativeSuite -or $M3Suite -ne 'None' -or $Manual)) {
    throw '-ReturnCheck applies only to automatic -Fixture or -MidiFile playback'
}
if ($Manual -and -not $MidiFile) {
    throw '-Manual requires -MidiFile'
}
if ($MidiTarget -notmatch '^[A-Za-z0-9_]{1,8}\.[A-Za-z0-9]{1,3}$') {
    throw "Invalid 8.3 MIDI target name: $MidiTarget"
}

if (Test-Path -LiteralPath $OutputImage) {
    throw "Refusing to overwrite existing image: $OutputImage"
}

& (Join-Path $PSScriptRoot 'build-driver.ps1')
& (Join-Path $PSScriptRoot 'build-golem.ps1')
& (Join-Path $PSScriptRoot 'generate-midi-fixtures.ps1')
if ($AutoexecFile) {
    $autoexecSource = [IO.Path]::GetFullPath($AutoexecFile)
} elseif ($MemoryCheck) {
    $autoexecSource = Join-Path $repo 'tests\integration\cspect\autoexec-memory.txt'
} elseif ($ReturnCheck) {
    $played = if ($MidiFile) { $MidiTarget } else { $Fixture }
    $autoexecSource = Join-Path $build 'autoexec-player-return.txt'
    [IO.File]::WriteAllLines($autoexecSource, @(
        '#autostart 10',
        '10 OUT 9275,7',
        "20 OUT 9531,$CpuSpeed",
        '30 .install "c:/nextzxos/GOLEM.DRV"',
        "40 .golem play `"c:/$played`"",
        '50 .uninstall "c:/nextzxos/GOLEM.DRV"',
        '60 OUT 5435,64',
        '70 OUT 4923,249',
        '80 STOP'
    ))
} elseif ($NegativeSuite) {
    throw 'unreachable: -NegativeSuite is rejected above'
} elseif ($M3Suite -eq 'Note') {
    $autoexecSource = Join-Path $repo 'tests\integration\cspect\autoexec-m3-note.txt'
} elseif ($M3Suite -eq 'Invalid') {
    throw 'unreachable: -M3Suite Invalid is rejected above'
} elseif ($M3Suite -eq 'Cancel') {
    $autoexecSource = Join-Path $repo 'tests\integration\cspect\autoexec-m3-cancel.txt'
} elseif ($MidiFile -and $Manual) {
    $autoexecSource = Join-Path $repo 'tests\demo\mi1\autoexec-manual.txt'
} elseif ($MidiFile) {
    $autoexecSource = Join-Path $build 'autoexec-player-user.txt'
    [IO.File]::WriteAllLines($autoexecSource, @(
        '#autostart 10',
        '10 OUT 9275,7',
        "20 OUT 9531,$CpuSpeed",
        '30 .install "c:/nextzxos/GOLEM.DRV"',
        "40 .golem play `"c:/$MidiTarget`"",
        '50 STOP'
    ))
} elseif ($Fixture -ne 'TEST1.MID' -or $CpuSpeed -ne 0) {
    $autoexecSource = Join-Path $build 'autoexec-player-fixture.txt'
    [IO.File]::WriteAllLines($autoexecSource, @(
        '#autostart 10',
        '10 OUT 9275,7',
        "20 OUT 9531,$CpuSpeed",
        '30 .install "c:/nextzxos/GOLEM.DRV"',
        "40 .golem play `"c:/$Fixture`"",
        '50 STOP'
    ))
}
& $python $converter `
    -i $autoexecSource `
    -o (Join-Path $build 'autoexec-player.bas')
if ($LASTEXITCODE -ne 0) { throw 'Unable to create tokenised player autoexec.bas' }

Copy-Item -LiteralPath $baseImage -Destination $OutputImage
& $hdfmonkey put $OutputImage (Join-Path $build 'GOLEM.DRV') '/nextzxos/GOLEM.DRV'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject GOLEM.DRV' }
& $hdfmonkey put $OutputImage (Join-Path $build 'MT32') '/dot/MT32'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject MT32' }
& $hdfmonkey put $OutputImage (Join-Path $build 'GOLEM') '/dot/GOLEM'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject GOLEM' }
& $hdfmonkey put $OutputImage (Join-Path $build 'GM') '/dot/GM'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject GM' }
& $hdfmonkey put $OutputImage (Join-Path $repo 'tests\fixtures\TEST0.MID') '/TEST0.MID'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject TEST0.MID' }
& $hdfmonkey put $OutputImage (Join-Path $repo 'tests\fixtures\TEST1.MID') '/TEST1.MID'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject TEST1.MID' }
& $hdfmonkey put $OutputImage (Join-Path $repo 'tests\fixtures\TESTCAN.MID') '/TESTCAN.MID'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject TESTCAN.MID' }
& $hdfmonkey put $OutputImage (Join-Path $repo 'tests\fixtures\TESTSYX.MID') '/TESTSYX.MID'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject TESTSYX.MID' }
& $hdfmonkey put $OutputImage (Join-Path $repo 'tests\fixtures\TESTSAB.MID') '/TESTSAB.MID'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject TESTSAB.MID' }
& $hdfmonkey put $OutputImage (Join-Path $repo 'tests\fixtures\TESTTIM.MID') '/TESTTIM.MID'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject TESTTIM.MID' }
& $hdfmonkey put $OutputImage (Join-Path $repo 'tests\fixtures\BADFMT2.MID') '/BADFMT2.MID'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject BADFMT2.MID' }
& $hdfmonkey put $OutputImage (Join-Path $repo 'tests\fixtures\BADSMPTE.MID') '/BADSMPTE.MID'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject BADSMPTE.MID' }
& $hdfmonkey put $OutputImage (Join-Path $repo 'tests\fixtures\BADTRNC.MID') '/BADTRNC.MID'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject BADTRNC.MID' }
& $hdfmonkey put $OutputImage (Join-Path $repo 'tests\fixtures\BADVLQ.MID') '/BADVLQ.MID'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject BADVLQ.MID' }
& $hdfmonkey put $OutputImage (Join-Path $repo 'tests\fixtures\BADSYX.MID') '/BADSYX.MID'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject BADSYX.MID' }
if ($MidiFile) {
    $MidiFile = [IO.Path]::GetFullPath($MidiFile)
    $midi = Get-Item -LiteralPath $MidiFile
    if ($midi.Length -gt 1048575) { throw "MIDI exceeds the 1048575-byte player limit: $($midi.Length)" }
    & $hdfmonkey put $OutputImage $midi.FullName "/$MidiTarget"
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inject the user MIDI file' }
}
& $hdfmonkey put $OutputImage (Join-Path $build 'autoexec-player.bas') '/nextzxos/autoexec.bas'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject autoexec.bas' }
& $hdfmonkey rm $OutputImage '/nextzxos/autoexec.1st'
if ($LASTEXITCODE -ne 0) { throw 'Unable to disable the welcome autoexec in the copied image' }

Write-Host "Built disposable NextZXOS player image: $OutputImage"
