param(
    [string]$Assembler = (Join-Path $env:USERPROFILE 'Documents\NextBuildv10\Emu\CSpect\SNasm.exe')
)

# Builds the Golem command and its aliases: GOLEM (keeps the synth engine),
# MT32 (asks a Golem for the MT-32 engine), GM (FluidSynth) and OPL3 (FM). One source,
# src/dot/golem_cli.s, with CLI_ENGINE set by each top file. Also MIDIMON,
# the MIDI monitor (src/dot/midimon.s).
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo 'src\dot'
$build = Join-Path $repo 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null

Push-Location $source
try {
    foreach ($name in 'GOLEM', 'MT32', 'GM', 'OPL3', 'MIDIMON') {
        & $Assembler -next "$($name.ToLower()).s" (Join-Path $build $name)
        if ($LASTEXITCODE -ne 0) { throw "SNasm failed building $name" }
        $command = Get-Item (Join-Path $build $name)
        if ($command.Length -le 0 -or $command.Length -gt 8192) {
            throw "Unexpected $name size: $($command.Length)"
        }
        Write-Host "Built $($command.FullName) ($($command.Length) bytes)"
    }
} finally {
    Pop-Location
}

# The help the commands point to (.guide golem): copy it to c:/docs/guides/
$guide = Copy-Item (Join-Path $repo 'src\guide\GOLEM.GDE') $build -PassThru
Write-Host "Copied $($guide.FullName) (for c:/docs/guides/)"

