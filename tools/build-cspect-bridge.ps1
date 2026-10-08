param(
    [string]$CSpectDir = (Join-Path $env:USERPROFILE 'Documents\NextBuildv10\Emu\CSpect'),
    [string]$MSBuild = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe',
    [switch]$Install
)

$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'cspect-uart-bridge\MT32NextUartBridge.csproj'
& $MSBuild $project /t:Build /p:Configuration=Release /p:CSpectPluginDir=$CSpectDir /nologo /verbosity:minimal
if ($LASTEXITCODE -ne 0) { throw 'MSBuild failed building the CSpect UART bridge' }

$dll = Join-Path $PSScriptRoot 'cspect-uart-bridge\bin\Release\MT32NextUartBridge.dll'
if (-not (Test-Path $dll)) { throw "Bridge output not found: $dll" }
Write-Host "Built $dll"
if ($Install) {
    $installed = Join-Path $CSpectDir 'MT32NextUartBridge.dll'
    Copy-Item -LiteralPath $dll -Destination $installed -Force
    Write-Host "Installed $installed"
}
