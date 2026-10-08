param(
    [string]$Assembler = (Join-Path $env:USERPROFILE 'Documents\NextBuildv10\Emu\CSpect\SNasm.exe')
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo 'src\dot'
$build = Join-Path $repo 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null

foreach ($name in @('MTTEST', 'MTSTRESS', 'MTAPIERR', 'MTNOID', 'MTCOLLIDE',
        'MTSTATE', 'MTDURATION', 'MTFRAME', 'MTLOAD', 'GSQ')) {
    Push-Location $source
    try {
        & $Assembler -next "$($name.ToLowerInvariant()).s" (Join-Path $build $name)
        if ($LASTEXITCODE -ne 0) { throw "SNasm failed building $name" }
    } finally {
        Pop-Location
    }

    $client = Get-Item (Join-Path $build $name)
    # Dot commands run from $2000-$3FFF, so 8 KB is the real limit.
    if ($client.Length -le 0 -or $client.Length -gt 8192) {
        throw "Unexpected $name size: $($client.Length)"
    }
    Write-Host "Built $($client.FullName) ($($client.Length) bytes)"
}
