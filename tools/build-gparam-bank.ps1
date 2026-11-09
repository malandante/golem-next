param(
    [string]$Assembler = (Join-Path $env:USERPROFILE 'Documents\NextBuildv10\Emu\CSpect\SNasm.exe')
)

# Builds the gp_* library as loadable 8K banks, one per slot address
# (src/lib/gparam_bank.s): build\GPAR4000.BIN ... build\GPARE000.BIN.
# A program loads the one for the slot where it will map the bank.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo 'src\lib'
$build = Join-Path $repo 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null

foreach ($slot in @('4000', '6000', '8000', 'A000', 'C000', 'E000')) {
    $name = "GPAR$slot.BIN"
    Push-Location $source
    try {
        & $Assembler -next "gparam_$($slot.ToLowerInvariant()).s" (Join-Path $build $name)
        if ($LASTEXITCODE -ne 0) { throw "SNasm failed building $name" }
    } finally {
        Pop-Location
    }

    $bank = Get-Item (Join-Path $build $name)
    if ($bank.Length -le 0 -or $bank.Length -gt 8192) {
        throw "Unexpected $name size: $($bank.Length)"
    }
    $bytes = [System.IO.File]::ReadAllBytes($bank.FullName)
    if ([System.Text.Encoding]::ASCII.GetString($bytes, 27, 4) -ne 'GPAR' -or $bytes[31] -ne 1) {
        throw "$name has no GPAR signature at offset 27"
    }
    Write-Host "Built $($bank.FullName) ($($bank.Length) bytes)"
}
