<#
.SYNOPSIS
  Envia .\publicar para o servidor de atualizacoes (/var/www/officeupdate) por SSH, so com o que mudou.

  1. compara o SHA-256 de cada arquivo local com o do publicado no servidor;
  2. no servidor, copia o publicado para uma pasta temporaria e manda para ela so os arquivos novos ou alterados
     (os que sairam de .\publicar sao apagados dela);
  3. so no fim a pasta temporaria substitui o publicado (quem estiver baixando nao pega metade de uma versao).
  A versao anterior fica em /var/www/officeupdate.anterior ate o proximo envio.

  Acesso: chave SSH (no PowerShell, uma vez; pede a senha do root):
    Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@166.0.186.213 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

.EXAMPLE
  .\Enviar.ps1
  .\Enviar.ps1 -Tudo        # manda tudo, sem comparar
#>
param(
    [string] $Servidor = "root@166.0.186.213",
    [string] $Remoto   = "/var/www/officeupdate",
    [string] $Dono     = "www-data",
    [switch] $Tudo
)

$ErrorActionPreference = "Stop"
$Publicar = Join-Path $PSScriptRoot "publicar"
if (-not (Test-Path (Join-Path $Publicar "instaladores"))) { throw "Nada para enviar: rode antes o Gerar.ps1." }

$ssh = "$env:WINDIR\System32\OpenSSH\ssh.exe"
$scp = "$env:WINDIR\System32\OpenSSH\scp.exe"
if (-not (Test-Path $scp)) { $ssh = "ssh"; $scp = "scp" }
$opcoes = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=30")
$temp = "$Remoto.envio"

function Remoto([string] $comando) {
    $saida = & $ssh @opcoes $Servidor $comando
    if ($LASTEXITCODE -ne 0) { throw "Falha no servidor: $comando" }
    return $saida
}

# arquivos locais: caminho relativo (com /) -> hash
$locais = @{}
Get-ChildItem $Publicar -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($Publicar.Length + 1).Replace('\', '/')
    $locais[$rel] = @{ Hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(); Tamanho = $_.Length }
}

# publicado no servidor
Write-Host "Comparando com ${Servidor}:$Remoto ..." -ForegroundColor Cyan
& $ssh @opcoes $Servidor "true"
if ($LASTEXITCODE -ne 0) { throw "Sem acesso ao servidor $Servidor (veja a chave SSH no inicio deste script)." }
$remotos = @{}
if (-not $Tudo) {
    Remoto "if [ -d '$Remoto' ]; then cd '$Remoto' && find . -type f -print0 | xargs -0 -r sha256sum; fi" | ForEach-Object {
        if ($_ -match '^([0-9a-f]{64})\s+\*?\./(.+)$') { $remotos[$Matches[2]] = $Matches[1] }
    }
}

$enviar = @($locais.Keys | Where-Object { $remotos[$_] -ne $locais[$_].Hash } | Sort-Object)
$apagar = @($remotos.Keys | Where-Object { -not $locais.ContainsKey($_) } | Sort-Object)
$bytes = ($enviar | ForEach-Object { $locais[$_].Tamanho } | Measure-Object -Sum).Sum
Write-Host ("Enviar: {0} arquivo(s), {1:N0} MB | iguais: {2} | apagar: {3}" -f $enviar.Count, ($bytes / 1MB), ($locais.Count - $enviar.Count), $apagar.Count)
if ($enviar.Count -eq 0 -and $apagar.Count -eq 0) { Write-Host "Nada mudou." -ForegroundColor Green; return }

# pasta temporaria = copia do publicado (os iguais nao trafegam)
Remoto "rm -rf '$temp' && if [ -d '$Remoto' ]; then cp -a '$Remoto' '$temp'; else mkdir -p '$temp'; fi"
foreach ($rel in $apagar) { Remoto "rm -f '$temp/$rel'" | Out-Null }

# um scp por pasta, com os arquivos dela
$porPasta = $enviar | Group-Object { $d = [IO.Path]::GetDirectoryName($_); if ($d) { $d.Replace('\', '/') } else { "" } }
# caminhos relativos a .\publicar (sem "D:", que o scp confunde com um servidor)
Push-Location $Publicar
try {
    foreach ($g in $porPasta) {
        $destino = if ($g.Name) { "$temp/$($g.Name)" } else { $temp }
        Remoto "mkdir -p '$destino'" | Out-Null
        $arquivos = @($g.Group | ForEach-Object { $_.Replace('/', '\') })
        $mb = ($g.Group | ForEach-Object { $locais[$_].Tamanho } | Measure-Object -Sum).Sum / 1MB
        Write-Host ("  {0}/ ({1} arquivo(s), {2:N0} MB) ..." -f $(if ($g.Name) { $g.Name } else { "." }), $g.Count, $mb)
        & $scp @opcoes -q @arquivos "${Servidor}:$destino/"
        if ($LASTEXITCODE -ne 0) { throw "Falha no envio de $($g.Name) (scp). Nada foi alterado no publicado; a pasta parcial ficou em $temp." }
    }
}
finally { Pop-Location }

# troca: o publicado vira .anterior e a pasta enviada vira a publicada
$troca = "set -e; " +
         "if [ -d '$Remoto' ]; then rm -rf '$Remoto.anterior'; mv '$Remoto' '$Remoto.anterior'; fi; " +
         "mv '$temp' '$Remoto'; " +
         "(id -u '$Dono' >/dev/null 2>&1 && chown -R '${Dono}:$Dono' '$Remoto') || true; " +
         "find '$Remoto' -type d -exec chmod 755 {} +; find '$Remoto' -type f -exec chmod 644 {} +"
Remoto $troca | Out-Null

# conferencia: o publicado tem que bater com o local
$conferir = @{}
Remoto "cd '$Remoto' && find . -type f -print0 | xargs -0 -r sha256sum" | ForEach-Object {
    if ($_ -match '^([0-9a-f]{64})\s+\*?\./(.+)$') { $conferir[$Matches[2]] = $Matches[1] }
}
$diferentes = @($locais.Keys | Where-Object { $conferir[$_] -ne $locais[$_].Hash })
if ($diferentes.Count -gt 0 -or $conferir.Count -ne $locais.Count) {
    throw "Publicado diferente do local em $($diferentes.Count) arquivo(s): $($diferentes -join ', ')"
}
Write-Host "Publicado e conferido em ${Servidor}:$Remoto ($($locais.Count) arquivos; anterior em $Remoto.anterior)." -ForegroundColor Green
