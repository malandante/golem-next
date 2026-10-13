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
    & $Assembler -next 'mt32drv.s' (Join-Path $build 'mt32drv.bin')
    if ($LASTEXITCODE -ne 0) { throw "SNasm failed building resident image" }
    & $Assembler -next 'mt32_drv.s' (Join-Path $build 'GOLEM.DRV')
    if ($LASTEXITCODE -ne 0) { throw "SNasm failed packaging GOLEM.DRV" }
} finally {
    Pop-Location
}

$driver = Get-Item (Join-Path $build 'GOLEM.DRV')
$resident = Get-Item (Join-Path $build 'mt32drv.bin')
$bytes = [IO.File]::ReadAllBytes($driver.FullName)
$signature = [Text.Encoding]::ASCII.GetString($bytes, 0, 4)
if ($signature -ne 'NDRV') { throw "Invalid .DRV signature: $signature" }
# Sizes follow the relocation count in the header (tools/ci/check_driver_relocations.py
# checks that it matches the table): 512-byte resident image + 2 bytes per entry.
$expected = 512 + 2 * $bytes[5]
if ($resident.Length -ne $expected) {
    throw "Unexpected resident+relocation size: $($resident.Length), expected $expected"
}
if ($driver.Length -ne $expected + 8) {
    throw "Unexpected GOLEM.DRV size: $($driver.Length), expected $($expected + 8)"
}
for ($index = 0; $index -lt $bytes[5]; $index++) {
    $offset = 8 + 512 + (2 * $index)
    $relocation = $bytes[$offset] + (256 * $bytes[$offset + 1])
    if ($relocation -ge 512) { throw "Relocation outside resident image: $relocation" }
    $opcode = $bytes[8 + $relocation - 2]
    if ($opcode -notin 0x21, 0x32, 0x3a, 0xc2, 0xc3, 0xca, 0xcd, 0xda) {
        throw ('Relocation {0} does not point at a recognised 16-bit operand (opcode ${1:X2})' -f $relocation, $opcode)
    }
}
Write-Host "Built $($driver.FullName) ($($driver.Length) bytes)"
