# Distro — Root RP

Manifesto (`distribution.json`) + packs (`config.zip`, `kubejs.zip`) do modpack.
Servido via GitHub Pages: `https://wesleynogueiraone.github.io/distro/distribution.json`
(é o que o Root Client lê). Os `.jar` dos mods ficam no release `v2.0` do repo `modpack`.

**Não edite à mão.** Use o **Root Distro Manager** (`../distro-manager/Abrir.bat`) ou a CLI:

```powershell
.\distro.ps1 status    # o que mudou, sem publicar
.\distro.ps1 sync      # publica a pasta ../mods
.\distro.ps1 config    # publica config da instância
.\distro.ps1 kubejs    # publica kubejs da instância
.\distro.ps1 check     # confere se tudo está baixável
```

Scripts antigos (PowerShell puro) estão em `_scripts_antigos/` só como referência.
