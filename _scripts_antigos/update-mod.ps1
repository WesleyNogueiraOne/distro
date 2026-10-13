# update-mod.ps1
# Uso: .\update-mod.ps1 -modPath "C:\caminho\novo-mod.jar" -modId "journeymap"

param(
    [Parameter(Mandatory=$true)]
    [string]$modPath,
    
    [Parameter(Mandatory=$true)]
    [string]$modId
)

$distroDir = "C:\Users\Usuario\Documents\distro"
$distroJson = "$distroDir\distribution.json"

# Verificar se arquivo existe
if(!(Test-Path $modPath)) {
    Write-Host "Arquivo nao encontrado: $modPath" -ForegroundColor Red
    exit 1
}

# Carregar JSON
$json = Get-Content $distroJson -Raw | ConvertFrom-Json

# Verificar se mod existe
$existing = $json.servers[0].modules | Where-Object { $_.id -like "*${modId}*" }
if(!$existing) {
    Write-Host "Mod '$modId' nao encontrado no distribution.json!" -ForegroundColor Red
    exit 1
}

$fileName = Split-Path $modPath -Leaf
$version = if($fileName -match "[\d]+\.[\d]+\.[\d]+") { $matches[0] } else { "1.0.0" }

Write-Host "Atualizando mod: $($existing.name) -> $fileName" -ForegroundColor Cyan

# Remover arquivo antigo do GitHub Release
$oldFileName = [Uri]::UnescapeDataString((Split-Path $existing.artifact.url -Leaf))
Write-Host "Removendo versao antiga: $oldFileName" -ForegroundColor Yellow
gh release delete-asset v2.0 $oldFileName --yes --repo WesleyNogueiraOne/modpack

# Upload novo arquivo
Write-Host "Fazendo upload da nova versao..." -ForegroundColor Cyan
gh release upload v2.0 $modPath --clobber --repo WesleyNogueiraOne/modpack

# Calcular novo MD5 e Size
$md5  = (Get-FileHash $modPath -Algorithm MD5).Hash.ToLower()
$size = (Get-Item $modPath).Length

Write-Host "MD5: $md5 | Size: $size" -ForegroundColor Yellow

# Montar nova URL
$encodedFileName = [Uri]::EscapeDataString($fileName)
$url = "https://github.com/WesleyNogueiraOne/modpack/releases/download/v2.0/$encodedFileName"

# Atualizar JSON
$existing.id              = "curse.maven:${modId}:${version}"
$existing.artifact.MD5    = $md5
$existing.artifact.size   = $size
$existing.artifact.url    = $url

[System.IO.File]::WriteAllText($distroJson, ($json | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Write-Host "distribution.json atualizado!" -ForegroundColor Green

# Commit e Push
Write-Host "Fazendo commit e push..." -ForegroundColor Cyan
Set-Location $distroDir
git add distribution.json
git commit -m "update mod $modId para $version"
git push

Write-Host "Mod '$modId' atualizado com sucesso!" -ForegroundColor Green