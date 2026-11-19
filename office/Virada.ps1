<#
.SYNOPSIS
  Virada do office.brpdv.com.br (OfficeManager web: API + banco om) do servidor antigo (166.0.186.213) para o
  novo (76.13.236.246). A API fica fora ~45 minutos; os Gateways guardam o que nao conseguirem enviar (so marcam
  syncws=true quando a API aceita) e reenviam depois.

  1. para a API antiga (ninguem mais grava no banco de la);
  2. backup do banco om no antigo (pg_dump, zstd, ~6 min), transferencia (~35 min a ~250 KB/s, saida do antigo),
     confere o SHA-256;
  3. no novo: recria o banco om (pt_BR.UTF-8, dono office), restaura (~3 min) e liga a API;
  4. no antigo: o /api do office.brpdv.com.br passa a ir para o servidor novo (quem ainda resolver o DNS antigo
     continua funcionando);
  5. confere.
  Depois: trocar no DNS do brpdv.com.br o registro "office" para 76.13.236.246 e, depois que propagar,
  .\Virada.ps1 -Certificado (certbot emite o certificado no servidor novo, no lugar do copiado do antigo).

  Volta (antes de trocar o DNS): .\Virada.ps1 -Voltar (religa a API antiga e o nginx de antes; o que os
  Gateways mandarem para o servidor novo nesse meio tempo fica so la).

.EXAMPLE
  .\Virada.ps1
  .\Virada.ps1 -Certificado
  .\Virada.ps1 -Voltar
#>
param(
    [string] $Antigo = "root@166.0.186.213",
    [string] $Novo   = "root@76.13.236.246",
    [switch] $Certificado,
    [switch] $Voltar
)

# OBSOLETO: virada de 19/11/2026 (166.0.186.213 antigo -> 76.13.236.246). Desde a tarde de 19/11/2026 o 166.0.186.213
# e o servidor de producao: rodar isto pararia a API dele e copiaria o banco para o 76.13.236.246.
throw "Virada.ps1 obsoleto: o 166.0.186.213 e hoje o servidor de producao (veja o LEIA-ME.md do OfficeDeploy)."

$ErrorActionPreference = "Stop"
$ssh = "$env:WINDIR\System32\OpenSSH\ssh.exe"
if (-not (Test-Path $ssh)) { $ssh = "ssh" }
$opcoes = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=30")

function Em([string] $servidor, [string] $comando) {
    & $ssh @opcoes $servidor ($comando -replace "`r", "")
    if ($LASTEXITCODE -ne 0) { throw "Falha em ${servidor}: $comando" }
}

if ($Voltar) {
    Write-Host "=== Voltando o servidor antigo" -ForegroundColor Yellow
    Em $Antigo @'
set -e
b=$(ls -t /root/nginx-officev2.conf.virada-* 2>/dev/null | head -1); [ -n "$b" ] && cp -p "$b" /etc/nginx/conf.d/officev2.conf
nginx -t && systemctl reload nginx
systemctl enable --now kestrel-officemanager >/dev/null 2>&1
systemctl is-active kestrel-officemanager
'@
    Em $Novo "systemctl stop kestrel-officemanager"
    return
}

if ($Certificado) {
    Write-Host "=== Certificado do office.brpdv.com.br no servidor novo" -ForegroundColor Cyan
    Em $Novo @'
set -e
for r in 8.8.8.8 1.1.1.1; do
  ip=$(dig +short office.brpdv.com.br @$r | tail -1)
  [ "$ip" = "76.13.236.246" ] || { echo "o DNS de office.brpdv.com.br ainda aponta para $ip (em $r)"; exit 1; }
done
mkdir -p /var/www/officev2/app/.well-known/acme-challenge
certbot certonly --webroot -w /var/www/officev2/app -d office.brpdv.com.br --non-interactive --agree-tos --keep-until-expiring
sed -i 's#/etc/nginx/ssl/office/fullchain.pem#/etc/letsencrypt/live/office.brpdv.com.br/fullchain.pem#; s#/etc/nginx/ssl/office/privkey.pem#/etc/letsencrypt/live/office.brpdv.com.br/privkey.pem#' /etc/nginx/conf.d/office.conf
nginx -t && systemctl reload nginx
rm -rf /etc/nginx/ssl/office
'@
    $codigo = curl.exe -s -o NUL -w "%{http_code}" "https://office.brpdv.com.br/"
    Write-Host "  https://office.brpdv.com.br/ -> $codigo (esperado 200)"
    return
}

$inicio = Get-Date
Write-Host "=== 1. Parando a API no servidor antigo ($(Get-Date -Format HH:mm))" -ForegroundColor Cyan
Em $Antigo "systemctl stop kestrel-officemanager; systemctl is-active kestrel-officemanager || true"

Write-Host "=== 2. Backup do banco om no antigo e transferencia" -ForegroundColor Cyan
Em $Antigo "rm -f /tmp/om-virada.dump; sudo -u postgres pg_dump -Fc --compress=zstd:9 -d om -f /tmp/om-virada.dump 2>/tmp/om-virada.err; rc=`$?; grep -v 'unable to resolve' /tmp/om-virada.err; rm -f /tmp/om-virada.err; [ `$rc -eq 0 ] || exit `$rc; ls -la /tmp/om-virada.dump"
$o = $opcoes -join " "
cmd /c "`"$ssh`" $o $Antigo `"cat /tmp/om-virada.dump`" | `"$ssh`" $o $Novo `"cat > /tmp/om-virada.dump`""
if ($LASTEXITCODE -ne 0) { throw "Falha na transferencia (a API antiga esta parada: rode .\Virada.ps1 -Voltar)." }
$h1 = (& $ssh @opcoes $Antigo "sha256sum /tmp/om-virada.dump | cut -d' ' -f1")
$h2 = (& $ssh @opcoes $Novo "sha256sum /tmp/om-virada.dump | cut -d' ' -f1")
if (-not $h1 -or $h1 -ne $h2) { throw "O backup chegou diferente ($h1 x $h2). A API antiga esta parada: rode .\Virada.ps1 -Voltar." }
Write-Host "  conferido: $h1"

Write-Host "=== 3. Restaurando no servidor novo" -ForegroundColor Cyan
Em $Novo @'
set -e
systemctl stop kestrel-officemanager
sudo -u postgres psql -p 5433 -v ON_ERROR_STOP=1 -q -c "DROP DATABASE IF EXISTS om" -c "CREATE DATABASE om OWNER office ENCODING 'UTF8' LC_COLLATE 'pt_BR.UTF-8' LC_CTYPE 'pt_BR.UTF-8' TEMPLATE template0"
chmod 644 /tmp/om-virada.dump
sudo -u postgres pg_restore -p 5433 -d om --no-owner --role=office -j 2 /tmp/om-virada.dump
sudo -u postgres psql -p 5433 -d om -q -c "ANALYZE"
systemctl start kestrel-officemanager; sleep 8; systemctl is-active kestrel-officemanager
rm -f /tmp/om-virada.dump
'@
Em $Antigo "rm -f /tmp/om-virada.dump /tmp/om-teste.dump"

Write-Host "=== 4. Servidor antigo: /api do office para o servidor novo" -ForegroundColor Cyan
Em $Antigo @'
set -e
d=$(date +%Y%m%d%H%M%S)
cp -p /etc/nginx/conf.d/officev2.conf /root/nginx-officev2.conf.virada-$d
sed -i -E 's#proxy_pass( +)http://localhost:3000;#proxy_pass https://76.13.236.246; proxy_ssl_server_name on; proxy_ssl_name office.brpdv.com.br;#' /etc/nginx/conf.d/officev2.conf
sed -i -E 's#proxy_set_header( +)Host \$host;#proxy_set_header Host office.brpdv.com.br;#' /etc/nginx/conf.d/officev2.conf
if nginx -t 2>/dev/null; then systemctl reload nginx; else cp -p /root/nginx-officev2.conf.virada-$d /etc/nginx/conf.d/officev2.conf; nginx -t; exit 1; fi
systemctl disable kestrel-officemanager >/dev/null 2>&1 || true
'@

Write-Host "=== 5. Conferindo" -ForegroundColor Cyan
$pelaAntiga = curl.exe -s -m 20 -o NUL -w "%{http_code}" "https://office.brpdv.com.br/api/companies"
$pelaNova   = curl.exe -s -m 20 -o NUL -w "%{http_code}" --resolve "office.brpdv.com.br:443:76.13.236.246" "https://office.brpdv.com.br/api/companies"
Write-Host "  pelo endereco atual (repasse do antigo): $pelaAntiga (esperado 401: pede login)"
Write-Host "  direto no novo:                          $pelaNova (esperado 401)"
Write-Host ("Pronto em {0:N0} min. Agora troque no DNS o 'office' do brpdv.com.br para 76.13.236.246 e, depois que propagar, rode .\Virada.ps1 -Certificado." -f ((Get-Date) - $inicio).TotalMinutes) -ForegroundColor Green
