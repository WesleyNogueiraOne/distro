<#
    distro.ps1 - Gerenciador do modpack Hoot Client
    ------------------------------------------------
    Um script so pra tudo. Substitui add-mod / bulk-add-mods / remove-mod /
    update-mod / update-distro.

    USO:
      .\distro.ps1 sync                 Espelha a pasta de mods -> distro.
                                        Sobe os novos, remove os que sumiram
                                        (inclusive do GitHub), reescreve o json,
                                        commita e da push.
      .\distro.ps1 add <caminho.jar>    Adiciona/atualiza um mod avulso.
      .\distro.ps1 remove <slug>        Remove um mod avulso (por slug ou nome).
      .\distro.ps1 config               Atualiza kubejs.zip + config.zip a partir
                                        da instancia do launcher.
      .\distro.ps1 list                 Lista os mods atuais do distribution.json.
      .\distro.ps1 publish [msg]        Commit + push manual.

    FLAGS:
      -NoPush     Faz tudo local (json, zip, upload) mas NAO da git push.
      -DryRun     Só mostra o que faria. Nao sobe, nao escreve, nao commita.
      -Yes        Nao pergunta confirmacao (pro sync deletar sem perguntar).

    Ex:  .\distro.ps1 sync
         .\distro.ps1 add "C:\Downloads\jei-1.21.1.jar"
         .\distro.ps1 remove jei
         .\distro.ps1 config
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('sync','add','remove','config','list','publish')]
    [string]$Command = 'list',

    [Parameter(Position=1)]
    [string]$Arg,

    [switch]$NoPush,
    [switch]$DryRun,
    [switch]$Yes
)

# ======================= CONFIG (edite aqui) =======================
$RepoRoot     = "C:\Users\Usuario\Documents\root_client"
$DistroDir    = Join-Path $RepoRoot "distro"
$DistroJson   = Join-Path $DistroDir "distribution.json"
$ModsDir      = Join-Path $RepoRoot "mods"
$GhRepo       = "WesleyNogueiraOne/modpack"
$GhRelease    = "v2.0"
$InstanceName = "MeuServidor"
$ServerIndex  = 0
# Jars que NAO sao mods e devem ser ignorados pelo sync (instalador do loader etc).
$ExcludeJarPatterns = @('*installer*', 'neoforge-*.jar')
# Raizes possiveis dos dados do launcher (a instancia com config/kubejs).
$DataRootCandidates = @(
    (Join-Path $env:APPDATA ".rootclient"),
    (Join-Path $env:APPDATA ".hootclient"),
    (Join-Path $env:APPDATA ".helioslauncher")
)
# ==================================================================

$ErrorActionPreference = 'Stop'

# ------------------------- helpers --------------------------------

function Info($m){ Write-Host $m -ForegroundColor Cyan }
function Ok($m){ Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Err($m){ Write-Host $m -ForegroundColor Red }

function Require-Tools {
    foreach($t in @('gh','git')){
        if(-not (Get-Command $t -ErrorAction SilentlyContinue)){
            throw "Ferramenta '$t' nao encontrada no PATH. Instale antes de continuar."
        }
    }
    # gh precisa estar autenticado pra upload.
    gh auth status 2>$null | Out-Null
    if($LASTEXITCODE -ne 0){ throw "gh nao esta autenticado. Rode: gh auth login" }
}

function Load-Distro {
    if(-not (Test-Path $DistroJson)){ throw "distribution.json nao encontrado em $DistroJson" }
    Get-Content $DistroJson -Raw | ConvertFrom-Json
}

function Save-Distro($json){
    if($DryRun){ Info "  [dry-run] distribution.json NAO foi escrito."; return }
    $out = $json | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText($DistroJson, $out, [System.Text.UTF8Encoding]::new($false))
}

# Slug estavel derivado do nome do arquivo: tira versao/mc-version, vira kebab.
function Get-ModSlug([string]$fileName){
    $b = $fileName -replace '\.jar$',''
    # remove sufixos de versao tipo -1.2.3, +1.21.1, -beta.5, etc a partir do 1o -<numero>
    $b = $b -replace '[-_]v?[\d]+\.[\d].*$',''
    $b = $b -replace '[^a-zA-Z0-9]+','-'
    $b = $b.Trim('-').ToLower()
    if([string]::IsNullOrWhiteSpace($b)){ $b = ($fileName -replace '\.jar$','' -replace '[^a-zA-Z0-9]+','-').Trim('-').ToLower() }
    return $b
}

# Versao "melhor esforco". Ignora a versao do Minecraft (1.21 / 1.21.1).
function Get-ModVersion([string]$fileName){
    $b = $fileName -replace '\.jar$',''
    $b = $b -replace '1\.21(\.\d+)?',''      # tira mc version
    $m = [regex]::Match($b, '([\d]+\.[\d]+(\.[\d]+)?)')
    if($m.Success){ return $m.Groups[1].Value }
    return '1.0.0'
}

function Get-AssetNameFromUrl([string]$url){
    [Uri]::UnescapeDataString(($url -split '/')[-1])
}

function Upload-Asset([string]$path){
    if($DryRun){ Info "  [dry-run] upload $([System.IO.Path]::GetFileName($path))"; return }
    gh release upload $GhRelease $path --clobber --repo $GhRepo
    if($LASTEXITCODE -ne 0){ throw "Falha no upload de $path (gh saiu com codigo $LASTEXITCODE)." }
}

function Delete-Asset([string]$assetName){
    if($DryRun){ Info "  [dry-run] delete asset $assetName"; return }
    gh release delete-asset $GhRelease $assetName --yes --repo $GhRepo 2>$null
    # nao trava se o asset ja nao existir.
}

function Build-ModModule([System.IO.FileInfo]$jar){
    $fileName = $jar.Name
    $slug     = Get-ModSlug $fileName
    $version  = Get-ModVersion $fileName
    $md5      = (Get-FileHash $jar.FullName -Algorithm MD5).Hash.ToLower()
    $size     = $jar.Length
    $encoded  = [Uri]::EscapeDataString($fileName)
    $url      = "https://github.com/$GhRepo/releases/download/$GhRelease/$encoded"
    [PSCustomObject]@{
        id       = "curse.maven:${slug}:${version}"
        name     = ($fileName -replace '\.jar$','')
        type     = "ForgeMod"
        artifact = [PSCustomObject]@{
            size = $size
            MD5  = $md5
            url  = $url
        }
    }
}

function Publish-Git([string]$msg){
    if($NoPush){ Warn "  -NoPush ativo: pulando git push."; }
    if($DryRun){ Info "  [dry-run] git commit -m `"$msg`""; return }
    Push-Location $DistroDir
    try {
        git add distribution.json kubejs.zip config.zip 2>$null
        git commit -m $msg
        if($LASTEXITCODE -ne 0){ Warn "  Nada pra commitar (ou commit falhou)."; return }
        if(-not $NoPush){
            git push
            if($LASTEXITCODE -ne 0){ throw "git push falhou." }
        }
    } finally { Pop-Location }
}

function Resolve-InstanceDir {
    foreach($root in $DataRootCandidates){
        $p = Join-Path $root "instances\$InstanceName"
        if(Test-Path (Join-Path $p "config")){ return $p }
    }
    throw "Instancia '$InstanceName' com pasta 'config' nao encontrada. Rode o servidor/instancia uma vez, ou ajuste `$DataRootCandidates."
}

function Get-Server($json){ $json.servers[$ServerIndex] }

# Lista os .jar da pasta de mods, ignorando instaladores/nao-mods.
function Get-ModJars {
    $all = @(Get-ChildItem -Path $ModsDir -Filter *.jar)
    $all | Where-Object {
        $name = $_.Name
        -not ($ExcludeJarPatterns | Where-Object { $name -like $_ })
    }
}

# ------------------------- comandos -------------------------------

function Cmd-List {
    $json = Load-Distro
    $srv  = Get-Server $json
    $mods = @($srv.modules | Where-Object { $_.type -eq 'ForgeMod' })
    Info "Servidor: $($srv.name)  |  MC $($srv.minecraftVersion)  |  addr $($srv.address)"
    Info "ForgeMods: $($mods.Count)"
    $mods | Sort-Object name | ForEach-Object {
        $slug = ($_.id -split ':')[1]
        Write-Host ("  {0,-32} {1}" -f $slug, $_.name) -ForegroundColor Gray
    }
    $others = @($srv.modules | Where-Object { $_.type -ne 'ForgeMod' })
    Info "Outros modulos (nao mexidos pelo sync): $($others.Count)"
    $others | ForEach-Object { Write-Host ("  [{0}] {1}" -f $_.type, $_.name) -ForegroundColor DarkGray }
}

function Cmd-Add {
    if(-not $Arg){ throw "Uso: .\distro.ps1 add <caminho.jar>" }
    if(-not (Test-Path $Arg)){ throw "Arquivo nao encontrado: $Arg" }
    Require-Tools
    $jar  = Get-Item $Arg
    $json = Load-Distro
    $srv  = Get-Server $json
    $mod  = Build-ModModule $jar
    $slug = ($mod.id -split ':')[1]

    Info "Adicionando/atualizando: $($mod.name)  (slug: $slug)"
    Upload-Asset $jar.FullName

    $existing = $srv.modules | Where-Object { $_.type -eq 'ForgeMod' -and ($_.id -split ':')[1] -eq $slug }
    if($existing){
        Warn "  Ja existe, atualizando entrada."
        $existing.id            = $mod.id
        $existing.name          = $mod.name
        $existing.artifact.size = $mod.artifact.size
        $existing.artifact.MD5  = $mod.artifact.MD5
        $existing.artifact.url  = $mod.artifact.url
    } else {
        $srv.modules += $mod
    }
    Save-Distro $json
    Ok "  distribution.json atualizado."
    Publish-Git "add mod $slug"
    Ok "Pronto."
}

function Cmd-Remove {
    if(-not $Arg){ throw "Uso: .\distro.ps1 remove <slug>" }
    Require-Tools
    $json = Load-Distro
    $srv  = Get-Server $json
    $match = @($srv.modules | Where-Object { $_.type -eq 'ForgeMod' -and (($_.id -split ':')[1] -like "*$Arg*" -or $_.name -like "*$Arg*") })
    if($match.Count -eq 0){ Err "Nenhum mod bate com '$Arg'."; return }
    Info "Vai remover $($match.Count) mod(s):"
    $match | ForEach-Object { Write-Host "  - $($_.name)" -ForegroundColor Yellow }
    if(-not $Yes -and -not $DryRun){
        $r = Read-Host "Confirma? (s/N)"
        if($r -ne 's'){ Warn "Cancelado."; return }
    }
    foreach($m in $match){ Delete-Asset (Get-AssetNameFromUrl $m.artifact.url) }
    $removeIds = $match | ForEach-Object { $_.id }
    $srv.modules = @($srv.modules | Where-Object { $removeIds -notcontains $_.id })
    Save-Distro $json
    Ok "  distribution.json atualizado."
    Publish-Git "remove mod $Arg"
    Ok "Pronto."
}

function Cmd-Sync {
    Require-Tools
    if(-not (Test-Path $ModsDir)){ throw "Pasta de mods nao existe: $ModsDir" }
    $jars = @(Get-ModJars)
    if($jars.Count -eq 0){ throw "Nenhum .jar (mod) em $ModsDir. Coloque os mods la primeiro." }

    $json = Load-Distro
    $srv  = Get-Server $json

    # slug -> jar desejado (a partir da pasta). Avisa se 2 jars derem o mesmo slug.
    $desired = @{}
    foreach($j in $jars){
        $slug = Get-ModSlug $j.Name
        if($desired.ContainsKey($slug)){
            Warn "  DUPLICADO: '$($j.Name)' e '$($desired[$slug].Name)' tem o mesmo slug '$slug'. Usando o ultimo. Tire um dos dois da pasta."
        }
        $desired[$slug] = $j
    }

    $existingMods = @($srv.modules | Where-Object { $_.type -eq 'ForgeMod' })
    $existingSlugs = @{}
    foreach($m in $existingMods){ $existingSlugs[($m.id -split ':')[1]] = $m }

    $toAdd    = @($desired.Keys | Where-Object { -not $existingSlugs.ContainsKey($_) })
    $toRemove = @($existingSlugs.Keys | Where-Object { -not $desired.ContainsKey($_) })
    $toKeep   = @($desired.Keys | Where-Object { $existingSlugs.ContainsKey($_) })

    Info "Sync da pasta: $ModsDir"
    Info "  na pasta: $($jars.Count) jars"
    Ok   "  novos:    $($toAdd.Count)"
    Warn "  remover:  $($toRemove.Count)"
    Info "  manter:   $($toKeep.Count) (re-upload pra garantir MD5)"
    if($toRemove.Count -gt 0){ $toRemove | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow } }

    if($toRemove.Count -gt 0 -and -not $Yes -and -not $DryRun){
        $r = Read-Host "Remover esses $($toRemove.Count) e sincronizar? (s/N)"
        if($r -ne 's'){ Warn "Cancelado."; return }
    }

    # deleta assets dos removidos
    foreach($slug in $toRemove){ Delete-Asset (Get-AssetNameFromUrl $existingSlugs[$slug].artifact.url) }

    # sobe cada mod unico (por slug) e monta os modulos
    $uniqueJars = @($desired.Values)
    $newForgeMods = @()
    $i = 0
    foreach($j in $uniqueJars){
        $i++
        Write-Host ("[{0}/{1}] {2}" -f $i, $uniqueJars.Count, $j.Name) -ForegroundColor Gray
        Upload-Asset $j.FullName
        $newForgeMods += Build-ModModule $j
    }

    # preserva nao-ForgeMod, troca os ForgeMod
    $others = @($srv.modules | Where-Object { $_.type -ne 'ForgeMod' })
    $srv.modules = @($others + $newForgeMods)

    Save-Distro $json
    Ok "  distribution.json reescrito ($($newForgeMods.Count) mods)."
    Publish-Git "sync mods: +$($toAdd.Count) -$($toRemove.Count) (total $($newForgeMods.Count))"
    Ok "Sync concluido."
}

function Cmd-Config {
    Require-Tools
    $inst = Resolve-InstanceDir
    Info "Instancia: $inst"
    $kubejsSrc = Join-Path $inst "kubejs"
    $configSrc = Join-Path $inst "config"
    $kubejsZip = Join-Path $DistroDir "kubejs.zip"
    $configZip = Join-Path $DistroDir "config.zip"

    if($DryRun){ Info "  [dry-run] zipar kubejs e config, atualizar json, subir."; return }

    Info "Zipando kubejs e config..."
    if(Test-Path $kubejsSrc){ Compress-Archive -Path "$kubejsSrc\*" -DestinationPath $kubejsZip -Force } else { Warn "  kubejs nao encontrado, pulando." }
    if(Test-Path $configSrc){ Compress-Archive -Path "$configSrc\*" -DestinationPath $configZip -Force } else { Warn "  config nao encontrado, pulando." }

    $json = Load-Distro
    $srv  = Get-Server $json
    foreach($m in $srv.modules){
        if($m.id -like '*kubejs-pack*' -and (Test-Path $kubejsZip)){
            $m.artifact.MD5  = (Get-FileHash $kubejsZip -Algorithm MD5).Hash.ToLower()
            $m.artifact.size = (Get-Item $kubejsZip).Length
        }
        if($m.id -like '*config-pack*' -and (Test-Path $configZip)){
            $m.artifact.MD5  = (Get-FileHash $configZip -Algorithm MD5).Hash.ToLower()
            $m.artifact.size = (Get-Item $configZip).Length
        }
    }
    Save-Distro $json
    Ok "  distribution.json atualizado."

    Info "Subindo zips..."
    if(Test-Path $kubejsZip){ Upload-Asset $kubejsZip }
    if(Test-Path $configZip){ Upload-Asset $configZip }

    Publish-Git "update kubejs e config - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    Ok "Patch publicado."
}

function Cmd-Publish {
    $msg = if($Arg){ $Arg } else { "update distro - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
    Publish-Git $msg
    Ok "Publicado."
}

# ------------------------- dispatch -------------------------------

try {
    switch($Command){
        'list'    { Cmd-List }
        'add'     { Cmd-Add }
        'remove'  { Cmd-Remove }
        'sync'    { Cmd-Sync }
        'config'  { Cmd-Config }
        'publish' { Cmd-Publish }
    }
} catch {
    Err "ERRO: $($_.Exception.Message)"
    exit 1
}
