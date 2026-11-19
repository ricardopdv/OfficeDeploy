<#
.SYNOPSIS
  Virada das licencas e revendas (API do site + banco brpdv) do servidor antigo (166.0.186.213) para o novo
  (76.13.236.246). Rodar SO na hora da virada, com o DNS pronto para ser trocado.

  1. para a API no servidor antigo (ninguem mais grava no banco de la);
  2. copia o banco brpdv do antigo para o novo (substitui a copia de teste) e reinicia a API nova;
  3. no antigo, o /api de revendas.brpdv.com.br passa a ir para o servidor novo (quem ainda tiver o DNS antigo
     em cache continua funcionando) e o login do portal de downloads tambem;
  4. confere a API nova.
  Depois: trocar no DNS do brpdv.com.br o registro "revendas" para 76.13.236.246 e rodar
  .\Virada.ps1 -Certificado (HTTPS do revendas.brpdv.com.br no servidor novo).

  Volta (se algo der errado antes de trocar o DNS): .\Virada.ps1 -Voltar (religa a API antiga e o nginx de antes).

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

$ErrorActionPreference = "Stop"
$ssh = "$env:WINDIR\System32\OpenSSH\ssh.exe"
if (-not (Test-Path $ssh)) { $ssh = "ssh" }
$opcoes = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15")

function Em([string] $servidor, [string] $comando) {
    & $ssh @opcoes $servidor ($comando -replace "`r", "")
    if ($LASTEXITCODE -ne 0) { throw "Falha em ${servidor}: $comando" }
}

if ($Voltar) {
    Write-Host "=== Voltando o servidor antigo" -ForegroundColor Yellow
    Em $Antigo @'
set -e
for f in revendas update; do b=$(ls -t /root/nginx-$f.conf.virada-* 2>/dev/null | head -1); [ -n "$b" ] && cp -p "$b" /etc/nginx/conf.d/$f.conf; done
nginx -t && systemctl reload nginx
systemctl start kestrel-site
systemctl is-active kestrel-site
'@
    return
}

if ($Certificado) {
    Write-Host "=== Certificado de revendas.brpdv.com.br no servidor novo" -ForegroundColor Cyan
    Em $Novo @'
set -e
ip=$(getent ahostsv4 revendas.brpdv.com.br | awk 'NR==1{print $1}')
[ "$ip" = "76.13.236.246" ] || { echo "o DNS de revendas.brpdv.com.br ainda aponta para $ip"; exit 1; }
certbot --nginx -d revendas.brpdv.com.br --non-interactive --agree-tos --keep-until-expiring --no-redirect
nginx -t && systemctl reload nginx
'@
    $codigo = curl.exe -s -o NUL -w "%{http_code}" "https://revendas.brpdv.com.br/api/Licencas/GetLicenca/0/0/1"
    Write-Host "  https://revendas.brpdv.com.br/api -> $codigo (esperado 400: filial nao cadastrada)"
    return
}

Write-Host "=== 1. Parando a API no servidor antigo" -ForegroundColor Cyan
Em $Antigo "systemctl stop kestrel-site; systemctl is-active kestrel-site || true"

Write-Host "=== 2. Copiando o banco brpdv para o servidor novo" -ForegroundColor Cyan
# o dump vai em bytes pelo pipe do cmd (o PowerShell recodificaria o texto e estragaria os acentos)
$dump = Join-Path $env:TEMP "brpdv-virada.sql"
$o = $opcoes -join " "
cmd /c "`"$ssh`" $o $Antigo `"mysqldump --single-transaction --routines --triggers --events --hex-blob --databases brpdv`" > `"$dump`""
if ($LASTEXITCODE -ne 0 -or (Get-Item $dump).Length -lt 10000) { throw "Falha no mysqldump (a API antiga esta parada: rode .\Virada.ps1 -Voltar)." }
Em $Novo "systemctl stop kestrel-site; mysql -e 'DROP DATABASE IF EXISTS brpdv'"
cmd /c "`"$ssh`" $o $Novo mysql < `"$dump`""
if ($LASTEXITCODE -ne 0) { throw "Falha ao restaurar o banco no servidor novo (rode .\Virada.ps1 -Voltar)." }
Remove-Item $dump -Force
Em $Novo "mysql -e `"GRANT ALL PRIVILEGES ON brpdv.* TO 'brpdv'@'%', 'brpdv'@'localhost'; FLUSH PRIVILEGES;`"; systemctl start kestrel-site; sleep 8; systemctl is-active kestrel-site"

Write-Host "=== 3. Servidor antigo: /api e login do portal para o servidor novo" -ForegroundColor Cyan
Em $Antigo @'
set -e
d=$(date +%Y%m%d%H%M%S)
cp -p /etc/nginx/conf.d/revendas.conf /root/nginx-revendas.conf.virada-$d
cp -p /etc/nginx/conf.d/update.conf /root/nginx-update.conf.virada-$d
# o proxy_pass local vira o servidor novo (com o Host certo para o nginx de la)
sed -i -E 's#proxy_pass http://localhost:8000;#proxy_pass http://76.13.236.246; proxy_set_header Host revendas.brpdv.com.br;#' /etc/nginx/conf.d/revendas.conf
sed -i -E '/location = \/api\/Accounts\/Login/,/}/ s#proxy_pass http://localhost:8000;#proxy_pass http://76.13.236.246;#' /etc/nginx/conf.d/update.conf
# o revendas.conf ja tinha "proxy_set_header Host $host": fica so o novo
sed -i -E 's#proxy_set_header Host \$host;##' /etc/nginx/conf.d/revendas.conf
if nginx -t 2>/dev/null; then systemctl reload nginx; else
  cp -p /root/nginx-revendas.conf.virada-$d /etc/nginx/conf.d/revendas.conf; cp -p /root/nginx-update.conf.virada-$d /etc/nginx/conf.d/update.conf; nginx -t; exit 1
fi
systemctl disable kestrel-site >/dev/null 2>&1 || true
'@

Write-Host "=== 4. Conferindo" -ForegroundColor Cyan
$pelaAntiga = curl.exe -s -m 15 -w " [%{http_code}]" "http://revendas.brpdv.com.br/api/Licencas/GetLicenca/00000000000000/0000-TESTE/1"
$pelaNova   = curl.exe -s -m 15 -w " [%{http_code}]" --resolve "revendas.brpdv.com.br:80:76.13.236.246" "http://revendas.brpdv.com.br/api/Licencas/GetLicenca/00000000000000/0000-TESTE/1"
Write-Host "  pelo endereco atual: $pelaAntiga"
Write-Host "  direto no novo:      $pelaNova"
Write-Host "Pronto. Agora troque no DNS o 'revendas' do brpdv.com.br para 76.13.236.246 e, depois que propagar, rode .\Virada.ps1 -Certificado." -ForegroundColor Green
