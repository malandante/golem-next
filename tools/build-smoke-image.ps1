param(
    [string]$NextBuildDir = (Join-Path $env:USERPROFILE 'Documents\NextBuildv10'),
    [string]$OutputImage
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$build = Join-Path $repo 'build'
if (-not $OutputImage) { $OutputImage = Join-Path $build 'mt32-next-smoke.img' }
$OutputImage = [IO.Path]::GetFullPath($OutputImage)
$baseImage = Join-Path $NextBuildDir 'img\cspect-next-2gb.img'
$python = Join-Path $NextBuildDir 'Python\python.exe'
$converter = Join-Path $NextBuildDir 'Scripts\txt2nextbasic.py'
$hdfmonkey = Join-Path $NextBuildDir 'Tools\hdfmonkey.exe'

if (Test-Path -LiteralPath $OutputImage) {
    throw "Refusing to overwrite existing image: $OutputImage"
}

& (Join-Path $PSScriptRoot 'build-driver.ps1')
& (Join-Path $PSScriptRoot 'build-test-client.ps1')
& $python $converter `
    -i (Join-Path $repo 'tests\integration\cspect\autoexec-smoke.txt') `
    -o (Join-Path $build 'autoexec.bas')
if ($LASTEXITCODE -ne 0) { throw 'Unable to create tokenised autoexec.bas' }

# Work only on a copy. The NextBuild distribution image is never modified.
Copy-Item -LiteralPath $baseImage -Destination $OutputImage
& $hdfmonkey put $OutputImage (Join-Path $build 'GOLEM.DRV') '/nextzxos/GOLEM.DRV'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject GOLEM.DRV' }
& $hdfmonkey put $OutputImage (Join-Path $build 'MTTEST') '/dot/MTTEST'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject MTTEST' }
& $hdfmonkey put $OutputImage (Join-Path $build 'autoexec.bas') '/nextzxos/autoexec.bas'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inject autoexec.bas' }
& $hdfmonkey rm $OutputImage '/nextzxos/autoexec.1st'
if ($LASTEXITCODE -ne 0) { throw 'Unable to disable the welcome autoexec in the copied image' }

Write-Host "Built disposable NextZXOS smoke image: $OutputImage"
