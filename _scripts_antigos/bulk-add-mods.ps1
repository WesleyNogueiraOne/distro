# bulk-add-mods.ps1
# Uso: .\bulk-add-mods.ps1
# Le todos os .jar de C:\Users\Usuario\Documents\hoot_mods e atualiza o distribution.json

$modFolder  = "C:\Users\Usuario\Documents\hoot_mods"
$distroDir  = "C:\Users\Usuario\Documents\distro"
$distroJson = "$distroDir\distribution.json"
$repo       = "WesleyNogueiraOne/modpack"
$release    = "v2.0"

$jars = Get-ChildItem -Path $modFolder -Filter "*.jar"

if($jars.Count -eq 0) {
    Write-Host "Nenhum .jar encontrado em $modFolder" -ForegroundColor Red
    exit 1
}

Write-Host "Encontrados $($jars.Count) mods. Iniciando..." -ForegroundColor Cyan

$json = Get-Content $distroJson -Raw | ConvertFrom-Json

# Limpa módulos antigos do tipo ForgeMod
$json.servers[0].modules = @($json.servers[0].modules | Where-Object { $_.type -ne "ForgeMod" })

foreach($jar in $jars) {
    $fileName = $jar.Name
    $modId    = ($fileName -replace '[-_][\d]+\.[\d]+.*$', '' -replace '[^a-zA-Z0-9]', '-').ToLower()
    $version  = if($fileName -match '([\d]+\.[\d]+\.[\d]+)') { $matches[1] } else { "1.0.0" }
    $md5      = (Get-FileHash $jar.FullName -Algorithm MD5).Hash.ToLower()
    $size     = $jar.Length

    Write-Host "[$($jars.IndexOf($jar)+1)/$($jars.Count)] $fileName" -ForegroundColor Yellow
    Write-Host "  MD5: $md5 | Size: $size" -ForegroundColor Gray

    # Upload
    Write-Host "  Uploading..." -ForegroundColor Cyan
    gh release upload $release $jar.FullName --clobber --repo $repo 2>$null

    $encodedFileName = [Uri]::EscapeDataString($fileName)
    $url = "https://github.com/$repo/releases/download/$release/$encodedFileName"

    $newModule = [PSCustomObject]@{
        id       = "curse.maven:${modId}:${version}"
        name     = $fileName -replace '\.jar$', ''
        type     = "ForgeMod"
        artifact = [PSCustomObject]@{
            size = $size
            MD5  = $md5
            url  = $url
        }
    }

    $json.servers[0].modules += $newModule
    Write-Host "  OK!" -ForegroundColor Green
}

# Salva
[System.IO.File]::WriteAllText(
    $distroJson,
    ($json | ConvertTo-Json -Depth 20),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "`nAtualizando GitHub..." -ForegroundColor Cyan
Set-Location $distroDir
git add distribution.json
git commit -m "bulk update mods $($jars.Count) jars"
git push

Write-Host "`nConcluido! $($jars.Count) mods adicionados." -ForegroundColor Green