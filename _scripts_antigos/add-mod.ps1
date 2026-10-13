# add-mod.ps1
# Uso: .\add-mod.ps1 -modPath "C:\caminho\para\mod.jar" -modName "Nome do Mod" -modId "nome-do-mod"
# Exemplo: .\add-mod.ps1 -modPath "C:\Downloads\jei-1.0.0.jar" -modName "JEI" -modId "jei"

param(
    [Parameter(Mandatory=$true)]
    [string]$modPath,
    
    [Parameter(Mandatory=$true)]
    [string]$modName,
    
    [Parameter(Mandatory=$true)]
    [string]$modId
)

$distroDir = "C:\Users\Usuario\Documents\distro"
$distroJson = "$distroDir\distribution.json"

# Verificar se o arquivo existe
if(!(Test-Path $modPath)) {
    Write-Host "Arquivo nao encontrado: $modPath" -ForegroundColor Red
    exit 1
}

# Pegar nome do arquivo e versao
$fileName = Split-Path $modPath -Leaf
$version = if($fileName -match "[\d]+\.[\d]+\.[\d]+") { $matches[0] } else { "1.0.0" }

Write-Host "Adicionando mod: $modName ($fileName)" -ForegroundColor Cyan

# Calcular MD5 e Size
$md5  = (Get-FileHash $modPath -Algorithm MD5).Hash.ToLower()
$size = (Get-Item $modPath).Length

Write-Host "MD5: $md5 | Size: $size" -ForegroundColor Yellow

# Upload no GitHub Release
Write-Host "Fazendo upload no GitHub Release..." -ForegroundColor Cyan
gh release upload v2.0 $modPath --clobber --repo WesleyNogueiraOne/modpack

# Montar URL
$encodedFileName = [Uri]::EscapeDataString($fileName)
$url = "https://github.com/WesleyNogueiraOne/modpack/releases/download/v2.0/$encodedFileName"

# Criar novo modulo
$newModule = [PSCustomObject]@{
    id       = "curse.maven:${modId}:${version}"
    name     = $modName
    type     = "ForgeMod"
    artifact = [PSCustomObject]@{
        size = $size
        MD5  = $md5
        url  = $url
    }
}

# Atualizar distribution.json
$json = Get-Content $distroJson -Raw | ConvertFrom-Json

# Verificar se mod ja existe
$existing = $json.servers[0].modules | Where-Object { $_.id -like "*${modId}*" }
if($existing) {
    Write-Host "Mod ja existe no distribution.json, atualizando..." -ForegroundColor Yellow
    $existing.artifact.MD5  = $md5
    $existing.artifact.size = $size
    $existing.artifact.url  = $url
} else {
    Write-Host "Adicionando novo mod ao distribution.json..." -ForegroundColor Cyan
    $json.servers[0].modules += $newModule
}

[System.IO.File]::WriteAllText($distroJson, ($json | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Write-Host "distribution.json atualizado!" -ForegroundColor Green

# Commit e Push
Write-Host "Fazendo commit e push..." -ForegroundColor Cyan
Set-Location $distroDir
git add distribution.json
git commit -m "add mod $modName $version"
git push

Write-Host "Mod $modName adicionado com sucesso!" -ForegroundColor Green