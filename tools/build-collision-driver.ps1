param(
    [string]$Assembler = (Join-Path $env:USERPROFILE 'Documents\NextBuildv10\Emu\CSpect\SNasm.exe')
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo 'src\driver'
$build = Join-Path $repo 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null

Push-Location $source
try {
    & $Assembler -next 'collision_resident.s' (Join-Path $build 'collision_resident.bin')
    if ($LASTEXITCODE -ne 0) { throw 'SNasm failed building collision resident' }
    & $Assembler -next 'collision_drv.s' (Join-Path $build 'COLLIDE.DRV')
    if ($LASTEXITCODE -ne 0) { throw 'SNasm failed building collision driver' }
} finally {
    Pop-Location
}

$driver = Get-Item (Join-Path $build 'COLLIDE.DRV')
if ($driver.Length -ne 520) { throw "Unexpected COLLIDE.DRV size: $($driver.Length)" }
Write-Host "Built $($driver.FullName) ($($driver.Length) bytes)"
