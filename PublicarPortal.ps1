<#
.SYNOPSIS
  Publica o portal de downloads (portal\) em update.gestaoagil.com.br.

  1. dotnet publish (Release, dependente do .NET 10 que o servidor ja tem);
  2. envia para /var/www/update-portal.novo e troca com a versao no ar (a anterior fica em .anterior);
  3. instala/atualiza o servico update-portal (systemd, usuario www-data, 127.0.0.1:8010), o certificado (certbot,
     na primeira vez; o DNS ja precisa apontar para o servidor) e o nginx
     (/etc/nginx/conf.d/update.conf; com backup e volta automatica se o nginx -t falhar);
  4. confere: o servico responde e o nginx entrega a pagina de login.

.EXAMPLE
  .\PublicarPortal.ps1
#>
param(
    [string] $Servidor       = "root@76.13.236.246",
    [string] $Destino        = "/var/www/update-portal",
    [string] $Dominio        = "update.gestaoagil.com.br"
)

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
$Projeto = Join-Path $Raiz "portal\Downloads.csproj"
$Saida = Join-Path $Raiz "portal\publish"

$ssh = "$env:WINDIR\System32\OpenSSH\ssh.exe"
$scp = "$env:WINDIR\System32\OpenSSH\scp.exe"
if (-not (Test-Path $scp)) { $ssh = "ssh"; $scp = "scp" }
$opcoes = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15")

function Remoto([string] $comando) {
    & $ssh @opcoes $Servidor $comando
    if ($LASTEXITCODE -ne 0) { throw "Falha no servidor: $comando" }
}

Write-Host "=== Compilando o portal" -ForegroundColor Cyan
if (Test-Path $Saida) { Remove-Item $Saida -Recurse -Force }
dotnet publish $Projeto -c Release -o $Saida --nologo -v q
if ($LASTEXITCODE -ne 0) { throw "Falha no dotnet publish." }
Get-ChildItem $Saida -Filter "appsettings.Development.json" | Remove-Item -Force

Write-Host "=== Enviando" -ForegroundColor Cyan
Remoto "rm -rf '$Destino.novo' && mkdir -p '$Destino.novo'"
Push-Location $Saida
try {
    & $scp @opcoes -q -r @(Get-ChildItem -Name) "${Servidor}:$Destino.novo/"
    if ($LASTEXITCODE -ne 0) { throw "Falha no envio (scp)." }
}
finally { Pop-Location }
& $scp @opcoes -q (Join-Path $Raiz "portal\deploy\update-portal.service") "${Servidor}:/tmp/update-portal.service"
& $scp @opcoes -q (Join-Path $Raiz "portal\deploy\update.conf") "${Servidor}:/tmp/update.conf"
if ($LASTEXITCODE -ne 0) { throw "Falha no envio da configuracao." }

Write-Host "=== Instalando" -ForegroundColor Cyan
$instalar = @"
set -e
mkdir -p /var/lib/update-portal/chaves
chown -R www-data:www-data /var/lib/update-portal
chmod 700 /var/lib/update-portal/chaves
if [ -d '$Destino' ]; then rm -rf '$Destino.anterior'; mv '$Destino' '$Destino.anterior'; fi
mv '$Destino.novo' '$Destino'
chown -R root:root '$Destino'; find '$Destino' -type d -exec chmod 755 {} +; find '$Destino' -type f -exec chmod 644 {} +
install -m 644 /tmp/update-portal.service /etc/systemd/system/update-portal.service
systemctl daemon-reload
systemctl enable update-portal >/dev/null 2>&1
systemctl restart update-portal
mkdir -p /var/www/update
# certificado: na primeira vez, um site so de HTTP para o certbot validar (webroot; renova sozinho pelo certbot.timer)
if [ ! -f /etc/letsencrypt/live/$Dominio/fullchain.pem ]; then
  tmp=/etc/nginx/conf.d/update-certbot.conf
  printf 'server {\n\tlisten 80;\n\tserver_name %s;\n\troot /var/www/update;\n}\n' '$Dominio' > `$tmp
  nginx -t 2>/dev/null && systemctl reload nginx
  if ! certbot certonly --webroot -w /var/www/update -d '$Dominio' --non-interactive --agree-tos --keep-until-expiring; then
    rm -f `$tmp; systemctl reload nginx
    echo 'certbot falhou: o DNS de $Dominio ja aponta para este servidor?'; exit 1
  fi
  rm -f `$tmp
fi
# nginx: backup, troca e teste; se falhar volta o anterior (ou tira o arquivo, se nao havia)
conf=/etc/nginx/conf.d/update.conf
b=''
if [ -f `$conf ]; then b=/root/nginx-update.conf.bak-`$(date +%Y%m%d%H%M%S); cp -p `$conf `$b; fi
cp /tmp/update.conf `$conf
if nginx -t 2>/dev/null; then systemctl reload nginx; else
  echo 'nginx -t falhou: voltando a configuracao anterior'; if [ -n "`$b" ]; then cp -p "`$b" `$conf; else rm -f `$conf; fi; nginx -t; exit 1
fi
rm -f /tmp/update.conf /tmp/update-portal.service
for i in 1 2 3 4 5 6 7 8 9 10; do curl -fs -o /dev/null http://127.0.0.1:8010/entrar && break; sleep 1; done
systemctl is-active update-portal
"@
Remoto ($instalar -replace "`r", "")

Write-Host "=== Conferindo" -ForegroundColor Cyan
$codigo = curl.exe -s -o NUL -w "%{http_code}" "https://$Dominio/entrar"
$redir  = curl.exe -s -o NUL -w "%{http_code}" "https://$Dominio/instaladores/"
Write-Host "  https://$Dominio/entrar -> $codigo (esperado 200)"
Write-Host "  https://$Dominio/instaladores/ -> $redir (esperado 302: so pelo portal)"
if ($codigo -ne "200") { throw "O portal nao respondeu em https://$Dominio/entrar." }
Write-Host "Portal publicado em https://$Dominio" -ForegroundColor Green
