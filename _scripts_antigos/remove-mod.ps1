# remove-mod.ps1
# Uso: .\remove-mod.ps1 -modId "journeymap"

param(
    [Parameter(Mandatory=$true)]
    [string]$modId
)

$distroDir = "C:\Users\Usuario\Documents\distro"
$distroJson = "$distroDir\distribution.json"

# Carregar JSON
$json = Get-Content $distroJson -Raw | ConvertFrom-Json

# Verificar se mod existe
$existing = $json.servers[0].modules | Where-Object { $_.id -like "*${modId}*" }
if(!$existing) {
    Write-Host "Mod '$modId' nao encontrado no distribution.json!" -ForegroundColor Red
    exit 1
}

Write-Host "Removendo mod: $($existing.name) ($($existing.id))" -ForegroundColor Cyan

# Remover do GitHub Release
$fileName = Split-Path $existing.artifact.url -Leaf
$decodedFileName = [Uri]::UnescapeDataString($fileName)
Write-Host "Removendo arquivo do GitHub Release: $decodedFileName" -ForegroundColor Yellow
gh release delete-asset v2.0 $decodedFileName --yes --repo WesleyNogueiraOne/modpack

# Remover do JSON
$json.servers[0].modules = $json.servers[0].modules | Where-Object { $_.id -notlike "*${modId}*" }

[System.IO.File]::WriteAllText($distroJson, ($json | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Write-Host "distribution.json atualizado!" -ForegroundColor Green

# Commit e Push
Write-Host "Fazendo commit e push..." -ForegroundColor Cyan
Set-Location $distroDir
git add distribution.json
git commit -m "remove mod $modId"
git push

Write-Host "Mod '$modId' removido com sucesso!" -ForegroundColor Green