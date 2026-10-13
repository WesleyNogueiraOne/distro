# Atalho pra CLI do Root Distro Manager (mesma l??gica da janela).
# Uso: .\distro.ps1 status | sync | config | kubejs | check | list | neoforge [versao]
$ErrorActionPreference = "Stop"
$electron = Join-Path $PSScriptRoot "..\HeliosLauncher-neoforge\node_modules\electron\dist\electron.exe"
$cli = Join-Path $PSScriptRoot "..\distro-manager\cli.js"
if (Get-Command node -ErrorAction SilentlyContinue) {
    & node $cli @args
} elseif (Test-Path $electron) {
    $env:ELECTRON_RUN_AS_NODE = "1"
    & $electron $cli @args
} else {
    Write-Error "Precisa do Node.js ou rodar npm install no launcher."
}
exit $LASTEXITCODE
