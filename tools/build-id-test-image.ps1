param(
    [string]$NextBuildDir = (Join-Path $env:USERPROFILE 'Documents\NextBuildv10'),
    [string]$OutputImage,
    [ValidateSet('Absent', 'Collision')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$build = Join-Path $repo 'build'
if (-not $OutputImage) {
    $OutputImage = Join-Path $build "mt32-next-id-$($Mode.ToLowerInvariant()).img"
}
$OutputImage = [IO.Path]::GetFullPath($OutputImage)
$baseImage = Join-Path $NextBuildDir 'img\cspect-next-2gb.img'
$python = Join-Path $NextBuildDir 'Python\python.exe'
$converter = Join-Path $NextBuildDir 'Scripts\txt2nextbasic.py'
$hdfmonkey = Join-Path $NextBuildDir 'Tools\hdfmonkey.exe'

if (Test-Path -LiteralPath $OutputImage) {
    throw "Refusing to overwrite existing image: $OutputImage"
}

& (Join-Path $PSScriptRoot 'build-test-client.ps1')
if ($Mode -eq 'Collision') {
    & (Join-Path $PSScriptRoot 'build-driver.ps1')
    & (Join-Path $PSScriptRoot 'build-collision-driver.ps1')
    $autoexec = Join-Path $repo 'tests\integration\cspect\autoexec-collision.txt'
    $clientName = 'MTCOLLIDE'
} else {
    $autoexec = Join-Path $repo 'tests\integration\cspect\autoexec-noid.txt'
    $clientName = 'MTNOID'
}

& $python $converter -i $autoexec -o (Join-Path $build 'autoexec-id-test.bas')
if ($LASTEXITCODE -ne 0) { throw 'Unable to create tokenised ID-test autoexec.bas' }

Copy-Item -LiteralPath $baseImage -Destination $OutputImage
& $hdfmonkey put $OutputImage (Join-Path $build $clientName) "/dot/$clientName"
if ($LASTEXITCODE -ne 0) { throw "Unable to inject $clientName" }
if ($Mode -eq 'Collision') {
    & $hdfmonkey put $OutputImage (Join-Path $build 'COLLIDE.DRV') '/nextzxos/COLLIDE.DRV'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inject COLLIDE.DRV' }
    & $hdfmonkey put $OutputImage (Join-Path $build 'GOLEM.DRV') '/nextzxos/GOLEM.DRV'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inject GOLEM.DRV' }
}
& $hdfmonkey put $OutputImage (Join-Path $build 'autoexec-id-test.bas') '/nextzxos/autoexec.bas'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject autoexec.bas' }
& $hdfmonkey rm $OutputImage '/nextzxos/autoexec.1st'
if ($LASTEXITCODE -ne 0) { throw 'Unable to disable the welcome autoexec in the copied image' }

Write-Host "Built disposable NextZXOS $Mode ID-test image: $OutputImage"
