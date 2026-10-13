# update-distro.ps1
$instanceDir = "$env:APPDATA\.helioslauncher\instances\MeuServidor"
$distroDir = "C:\Users\Usuario\Documents\distro"
$distroJson = "$distroDir\distribution.json"

# Zipar pastas
Write-Host "Zipando kubejs e config..."
Compress-Archive -Path "$instanceDir\kubejs\*" -DestinationPath "$distroDir\kubejs.zip" -Force
Compress-Archive -Path "$instanceDir\config\*" -DestinationPath "$distroDir\config.zip" -Force

# Calcular MD5 e Size
$kubejsMD5  = (Get-FileHash "$distroDir\kubejs.zip" -Algorithm MD5).Hash.ToLower()
$kubejsSize = (Get-Item "$distroDir\kubejs.zip").Length
$configMD5  = (Get-FileHash "$distroDir\config.zip" -Algorithm MD5).Hash.ToLower()
$configSize = (Get-Item "$distroDir\config.zip").Length

Write-Host "kubejs.zip -> MD5: $kubejsMD5 | Size: $kubejsSize"
Write-Host "config.zip -> MD5: $configMD5 | Size: $configSize"

# Atualizar distribution.json
$json = Get-Content $distroJson -Raw | ConvertFrom-Json
foreach($module in $json.servers[0].modules) {
    if($module.id -like "*kubejs-pack*") {
        $module.artifact.MD5  = $kubejsMD5
        $module.artifact.size = $kubejsSize
        $module.artifact.path = "files/kubejs-pack/1.0.0/kubejs-pack-1.0.0.zip"
    }
    if($module.id -like "*config-pack*") {
        $module.artifact.MD5  = $configMD5
        $module.artifact.size = $configSize
        $module.artifact.path = "files/config-pack/1.0.0/config-pack-1.0.0.zip"
    }
}
[System.IO.File]::WriteAllText($distroJson, ($json | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Write-Host "distribution.json atualizado!"

# Upload no GitHub Release
Write-Host "Fazendo upload no GitHub Release..."
gh release upload v2.0 "$distroDir\kubejs.zip" --clobber --repo WesleyNogueiraOne/modpack
gh release upload v2.0 "$distroDir\config.zip" --clobber --repo WesleyNogueiraOne/modpack

# Commit e Push
Write-Host "Fazendo commit e push..."
Set-Location $distroDir
git add distribution.json
git commit -m "update kubejs e config - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
git push

Write-Host "Patch publicado com sucesso!"