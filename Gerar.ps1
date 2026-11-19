<#
.SYNOPSIS
  Compila em Release os programas do OfficeManager e o Caixa (modo OfficeManager), gera os instaladores e os
  pacotes de atualizacao (AutoUpdater) em .\publicar, pronto para enviar ao servidor (Enviar.ps1).

.EXAMPLE
  .\Gerar.ps1                       # todos
  .\Gerar.ps1 -Programas troca,gateway
  .\Gerar.ps1 -SemCompilar          # reaproveita a ultima compilacao (so empacota)
  .\Gerar.ps1 -Enviar               # gera e envia ao servidor
  .\Gerar.ps1 -SoCatalogo           # so o instaladores.json do portal
#>
param(
    [string[]] $Programas,
    [switch] $SemCompilar,
    [switch] $Enviar,
    # so refaz o instaladores.json (catalogo do portal) com os instaladores que ja estao em publicar\instaladores
    [switch] $SoCatalogo,
    # endereco publico da pasta /var/www/update (usado nos AutoUpdater.xml)
    [string] $UrlBase = "https://update.gestaoagil.com.br",
    # instalador do JDK 21 que vai nos instaladores do OfficeManager e do PreVenda (o mesmo do instalador do Caixa)
    [string] $Jdk = "D:\Desenv\IA\Caixa\setup\Externos\Utils\JDK\jdk-21_windows-x64_bin.exe"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

# ---------------------------------------------------------------------------------------------------------------
# Configuracao
# ---------------------------------------------------------------------------------------------------------------
$Raiz      = $PSScriptRoot
$OM        = "D:\Desenv\IA\OfficeManager"          # Source\ (fontes) e Release\ (saida das compilacoes)
$CaixaRepo = "D:\Desenv\IA\Caixa"                  # repositorio do Caixa (setup\GerarInstalador.cmd)
$CaixaNetRepo = "D:\Desenv\IA\CaixaNet"            # o caixa em .NET 10 (branch dotnet-moderno), em teste
$Publicar  = Join-Path $Raiz "publicar"            # espelho de /var/www/update
$Preparo   = Join-Path $Raiz "preparo"             # copia limpa de cada programa antes de empacotar
$Logs      = Join-Path $Raiz "logs"
# calculadora da reforma tributaria (java -jar api-regime-geral.jar), a mesma no OfficeManager e no PreVenda: vai so no
# instalador dos programas com CalcRT = $true, em {app}\CalcRT, junto com o JDK 21; nunca no pacote de atualizacao
$CalcRT    = "$OM\Release\OfficeManager\CalcRT"

# Id: nome da pasta em atualizacoes\ (officemanager, officemanagerbi e gateway sao os nomes que os programas ja usam)
# Release: pasta em $OM\Release; Projetos: compilados nessa ordem (todos AnyCPU); Destino: pasta padrao da instalacao
$Lista = @(
    @{ Id = "officemanager";   Nome = "OfficeManager";      Release = "OfficeManager";       Exe = "OfficeManager.exe";
       Projetos = "OfficeManager\OfficeManager.csproj", "Configurador\Configurador.csproj";
       Icone = "OfficeManager\charts-colors-3d.ico";    Destino = "C:\OfficeManager";              AppId = "5F714C58-8F3C-4312-B21C-826CAA686FA4"; CalcRT = $true },
    @{ Id = "gateway";         Nome = "OfficeManager Gateway"; Release = "OfficeManagerGw";   Exe = "OfficeManagerGw.exe";
       Projetos = @("OfficeManagerGw\OfficeManagerGw.csproj");
       Icone = "OfficeManagerGw\database_access.ico";   Destino = "C:\OfficeManager\Gateway";      AppId = "E0985E35-CCD7-4702-889E-5B39CCE697C8"; IniciarComWindows = $true },
    @{ Id = "officemanagerbi"; Nome = "OfficeManager BI";   Release = "OfficeManagerBI";     Exe = "OfficeManagerBI.exe";
       Projetos = @("OfficeManagerBI\OfficeManagerBI.csproj");
       Icone = "OfficeManagerBI\graph_sales.ico";       Destino = "C:\OfficeManager\BI";           AppId = "CB82BCB8-727D-4F24-87C5-048A1FB1D33C" },
    @{ Id = "prevenda";        Nome = "PreVenda";           Release = "PreVenda";            Exe = "PreVenda.exe";
       Projetos = "PreVenda\PreVenda\PreVenda.csproj", "PreVenda\Configurador\Configurador.csproj";
       Icone = "PreVenda\PreVenda\contract-employee.ico"; Destino = "C:\OfficeManager\PreVenda";   AppId = "1CFA9F99-A202-4C28-80DF-D36406E61B84"; CalcRT = $true },
    @{ Id = "backup";          Nome = "OfficeManager Backup"; Release = "OfficeManagerBackup"; Exe = "OfficeManagerBackup.exe";
       Projetos = @("OfficeManagerBackup\OfficeManagerBackup.csproj");
       Icone = "OfficeManagerBackup\logo.ico";          Destino = "C:\OfficeManager\Backup";       AppId = "7A74BAC9-8243-4352-8E37-2105A784BDDC" },
    @{ Id = "troca";           Nome = "Trocas";             Release = "Troca";               Exe = "Trocas.exe";
       Projetos = "Trocas\Troca\Trocas.csproj", "Trocas\Configurador\Configurador.csproj";
       Icone = "Trocas\Troca\quote-shipment.ico";       Destino = "C:\OfficeManager\Trocas";       AppId = "A91E686D-3ACD-41E8-8681-EE56F7B516F9" },
    @{ Id = "caixacentral";    Nome = "Caixa Central";      Release = "CaixaCentral";        Exe = "CaixaCentral.exe";
       Projetos = @("CaixaCentral\CaixaCentral.csproj");
       Icone = "CaixaCentral\bank-stats.ico";           Destino = "C:\OfficeManager\CaixaCentral"; AppId = "0EF31119-25BF-4EC3-AF31-AFEE93FDF332" },
    # o Caixa tem o proprio instalador (com o MariaDB), gerado pelo repositorio do Caixa; aqui sai tambem o pacote de atualizacao
    # (o caixa completo busca em atualizacoes/caixa e o so do Gestao em atualizacoes/caixagestao: os dois geram Caixa.exe)
    @{ Id = "caixa";           Nome = "Caixa NFCe (OfficeManager)"; Caixa = $true;
       Script = "setup\GerarInstalador.cmd";       Setup = "Setup Caixa NFCe.exe";        Release = "saida\Release\Caixa";
       Icone = "src\Caixa\icon_app.ico" },
    @{ Id = "caixagestao";     Nome = "Caixa NFCe (Gestao)";        Caixa = $true;
       Script = "setup\GerarInstaladorGestao.cmd"; Setup = "Setup Caixa NFCe Gestao.exe"; Release = "saida\Release\CaixaGestao";
       Icone = "src\Caixa\icon_app.ico" },
    # o caixa em .NET 10 (D:\Desenv\IA\CaixaNet, branch dotnet-moderno), EM TESTE: canal proprio (atualizacoes/caixanet e
    # caixanetgestao), para os caixas de producao nunca receberem esta versao. Nao entra em "todos": so com -Programas.
    @{ Id = "caixanet";        Nome = "Caixa NFCe .NET 10 (TESTE)"; Caixa = $true; Repo = $CaixaNetRepo; Teste = $true;
       Script = "setup\GerarInstalador.cmd";       Setup = "Setup Caixa NFCe NET10 teste.exe";        Release = "saida\Release\Caixa";
       Icone = "src\Caixa\icon_app.ico" },
    @{ Id = "caixanetgestao";  Nome = "Caixa NFCe Gestao .NET 10 (TESTE)"; Caixa = $true; Repo = $CaixaNetRepo; Teste = $true;
       Script = "setup\GerarInstaladorGestao.cmd"; Setup = "Setup Caixa NFCe Gestao NET10 teste.exe"; Release = "saida\Release\CaixaGestao";
       Icone = "src\Caixa\icon_app.ico" }
)

# AssemblyInfo de cada programa: recebe a versao do deploy antes de compilar e volta ao original depois
# (o AutoUpdater compara a AssemblyVersion do exe instalado com a do AutoUpdater.xml)
$ArquivoVersao = @{
    officemanager   = "$OM\Source\OfficeManager\Properties\AssemblyInfo.cs"
    gateway         = "$OM\Source\OfficeManagerGw\Properties\AssemblyInfo.cs"
    officemanagerbi = "$OM\Source\OfficeManagerBI\Properties\AssemblyInfo.cs"
    prevenda        = "$OM\Source\PreVenda\PreVenda\Properties\AssemblyInfo.cs"
    backup          = "$OM\Source\OfficeManagerBackup\Properties\AssemblyInfo.cs"
    troca           = "$OM\Source\Trocas\Troca\Properties\AssemblyInfo.cs"
    caixacentral    = "$OM\Source\CaixaCentral\Properties\AssemblyInfo.cs"
    caixa           = "$CaixaRepo\src\Caixa\Properties\AssemblyInfo.cs"
    caixagestao     = "$CaixaRepo\src\Caixa.Gestao\Properties\AssemblyInfo.cs"
    caixanet        = "$CaixaNetRepo\src\Caixa\Properties\AssemblyInfo.cs"
    caixanetgestao  = "$CaixaNetRepo\src\Caixa.Gestao\Properties\AssemblyInfo.cs"
}

# pastas de idioma que nao vao no pacote (so pt-BR fica), como no Build\Clean.CMD
$Idiomas = "ar","cs","da","de","es","fr","it","ja","ja-JP","ko","lv","nl","pl","pt","ru","sk","sv","th","tr","uk","zh","zh-CN","zh-Hans","zh-Hant","zh-TW","en","en-US"

# ---------------------------------------------------------------------------------------------------------------
function Passo($texto) { Write-Host ""; Write-Host "=== $texto" -ForegroundColor Cyan }

function Ferramenta($nome, [string[]] $caminhos) {
    foreach ($c in $caminhos) { if ($c -and (Test-Path $c)) { return $c } }
    throw "$nome nao encontrado."
}

$MSBuild = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -prerelease -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
if (-not $MSBuild) { throw "MSBuild nao encontrado (Visual Studio com .NET desktop)." }
$ISCC = Ferramenta "Inno Setup 6 (ISCC.exe)" @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe")

function Compilar($projeto) {
    $log = Join-Path $Logs ("build-" + ($projeto -replace '\.csproj$', '' -replace '[\\/: ]', '_') + ".log")
    $saida = & $MSBuild (Join-Path "$OM\Source" $projeto) /restore /p:Configuration=Release /p:Platform=AnyCPU /m /v:m /nologo 2>&1
    $saida | Out-File $log -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
        $saida | Select-String " error " | Select-Object -First 10 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        throw "Falha ao compilar $projeto (log: $log)"
    }
    Write-Host "  compilado: $projeto"
}

# copia a pasta Release do programa sem o que nao vai para o cliente (simbolos, documentacao XML das DLLs, backups, outros idiomas).
# A CalcRT fica de fora: vai so no instalador (PrepararCalcRT), nunca no pacote de atualizacao (o java em execucao prende o jar)
function Preparar($origem, $destino) {
    if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
    New-Item -ItemType Directory $destino | Out-Null
    robocopy $origem $destino /E /NFL /NDL /NJH /NJS /NP /XF *.pdb *.bak *.vshost.* *.user /XD obj (Join-Path $origem "CalcRT") | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Falha ao copiar $origem" }

    foreach ($idioma in $Idiomas) {
        $p = Join-Path $destino $idioma
        if (Test-Path $p) { Remove-Item $p -Recurse -Force }
    }
    # documentacao XML das DLLs (Nome.xml ao lado de Nome.dll) so na raiz; os XML de layout/relatorio ficam
    Get-ChildItem $destino -Filter *.xml -File | Where-Object {
        (Test-Path (Join-Path $destino ($_.BaseName + ".dll"))) -or (Test-Path (Join-Path $destino ($_.BaseName + ".exe")))
    } | Remove-Item -Force
}

# copia da CalcRT para os instaladores (uma vez por execucao), sem a copia antiga (Old\) e sem os arquivos temporarios do
# SQLite (*.db-shm, *.db-wal) que ficam quando a calculadora roda aqui
$script:CalcRTPreparada = $null
function PrepararCalcRT {
    if ($script:CalcRTPreparada) { return $script:CalcRTPreparada }
    if (-not (Test-Path (Join-Path $CalcRT "api-regime-geral.jar"))) { throw "Calculadora da reforma nao encontrada: $CalcRT\api-regime-geral.jar" }
    if (-not (Test-Path $Jdk)) { throw "Instalador do JDK 21 nao encontrado: $Jdk (parametro -Jdk)" }
    $destino = Join-Path $Preparo "_calcrt"
    if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
    robocopy $CalcRT $destino /E /NFL /NDL /NJH /NJS /NP /XF *.db-shm *.db-wal /XD (Join-Path $CalcRT "Old") | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Falha ao copiar $CalcRT" }
    $script:CalcRTPreparada = $destino
    return $destino
}

# versao do deploy no formato que os projetos ja usam: ano.mes.dia-do-ano.contador; o contador e o segundo do dia / 2
# (sempre cresce entre deploys). Se o AssemblyInfo ja tiver versao igual ou maior, soma 1 na dela.
$Agora = Get-Date
$VersaoDeploy = [version]::new($Agora.Year, $Agora.Month, $Agora.DayOfYear, [int][math]::Floor($Agora.TimeOfDay.TotalSeconds / 2))
$RegexVersao = '(\[assembly:\s*Assembly(?:File|Informational)?Version\(")([^"]*)("\)\])'

function Carimbar($arquivo) {
    $bytes = [IO.File]::ReadAllBytes($arquivo)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    # sem BOM: Latin-1 (le e grava cada byte como esta; nao estraga acentos de arquivo ANSI)
    $enc = if ($bom) { New-Object Text.UTF8Encoding $true } else { [Text.Encoding]::GetEncoding(28591) }
    $texto = [IO.File]::ReadAllText($arquivo, $enc)
    $atual = [regex]::Match($texto, '\[assembly:\s*AssemblyVersion\("([0-9.]+)"\)\]')
    $versao = $VersaoDeploy
    if ($atual.Success) {
        $v = [version]$atual.Groups[1].Value
        if ($v -ge $versao) { $versao = [version]::new($v.Major, $v.Minor, [math]::Max($v.Build, 0), [math]::Max($v.Revision, 0) + 1) }
    }
    $novo = [regex]::Replace($texto, $RegexVersao, { param($m) $m.Groups[1].Value + $versao.ToString() + $m.Groups[3].Value })
    [IO.File]::WriteAllText($arquivo, $novo, $enc)
    Write-Host "  versao: $versao"
    return $bytes
}

function Restaurar($arquivo, $bytes) { if ($bytes) { [IO.File]::WriteAllBytes($arquivo, $bytes) } }

function VersaoDoExe($exe) {
    # o AutoUpdater compara com a versao do assembly; o instalador usa a versao do arquivo
    # no .NET 10 o exe e so o lancador nativo (apphost): a versao do assembly fica na dll de mesmo nome
    $dll = [IO.Path]::ChangeExtension($exe, ".dll")
    $alvo = if (Test-Path $dll) { $dll } else { $exe }
    $asm = [Reflection.AssemblyName]::GetAssemblyName($alvo).Version.ToString()
    $arq = (Get-Item $exe).VersionInfo.FileVersion
    return @{ Assembly = $asm; Arquivo = $arq }
}

# o checksum (SHA-256 do zip) e conferido pelo atualizador do Caixa e pelo AutoUpdater.NET dos outros programas
# antes de instalar: um download pela metade ou trocado no caminho nao e instalado
function AutoUpdaterXml($id, $versao, $zip, $zipPath) {
    $url = "$UrlBase/atualizacoes/$id/$zip"
    $sha256 = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<item>
  <version>$versao</version>
  <url>$url</url>
  <mandatory>false</mandatory>
  <checksum algorithm="SHA256">$sha256</checksum>
</item>
"@
}

# ---------------------------------------------------------------------------------------------------------------
# sem -Programas: todos os de producao (os de teste so quando pedidos pelo Id)
$escolhidos = if ($Programas) { $Lista | Where-Object { $Programas -contains $_.Id } } else { $Lista | Where-Object { -not $_.ContainsKey("Teste") } }
if (-not $escolhidos) { throw "Nenhum programa com esses nomes. Disponiveis: $(($Lista | ForEach-Object { $_.Id }) -join ', ')" }

$Instaladores = Join-Path $Publicar "instaladores"
$Atualizacoes = Join-Path $Publicar "atualizacoes"
foreach ($p in $Publicar, $Instaladores, $Atualizacoes, $Preparo, $Logs) { if (-not (Test-Path $p)) { New-Item -ItemType Directory $p | Out-Null } }

$inicio = Get-Date
$resumo = @()

foreach ($prog in $(if ($SoCatalogo) { @() } else { $escolhidos })) {
    Passo $prog.Nome

    if ($prog.ContainsKey("Caixa")) {
        $repo = if ($prog.ContainsKey("Repo")) { $prog.Repo } else { $CaixaRepo }
        $cmd = Join-Path $repo $prog.Script
        $log = Join-Path $Logs "$($prog.Id).log"
        if (-not $SemCompilar) {
            $original = Carimbar $ArquivoVersao[$prog.Id]
            try {
                & cmd /c "`"$cmd`"" 2>&1 | Out-File $log -Encoding utf8
                if ($LASTEXITCODE -ne 0) { throw "Falha ao gerar o instalador do $($prog.Nome) (log: $log)" }
            }
            finally { Restaurar $ArquivoVersao[$prog.Id] $original }
        }
        $setup = Join-Path $repo "setup\Output\$($prog.Setup)"
        if (-not (Test-Path $setup)) { throw "Instalador nao encontrado: $setup" }
        Copy-Item $setup (Join-Path $Instaladores $prog.Setup) -Force
        $release = Join-Path $repo $prog.Release
        $versao = VersaoDoExe (Join-Path $release "Caixa.exe")
        Write-Host "  instalador: $($prog.Setup) ($($versao.Arquivo))"

        # pacote de atualizacao: so o programa (como o antigo Build\!Deploy.CMD): exe, dll, .config e as pastas Schemas, Fonts e pt-BR.
        # Ficam de fora a configuracao do cliente (CliSiTef.ini, ACBrLib.ini, Logocli.png), os modelos *.new e a CalcRT (vem no instalador)
        $pasta = Join-Path $Preparo $prog.Id
        if (Test-Path $pasta) { Remove-Item $pasta -Recurse -Force }
        New-Item -ItemType Directory $pasta | Out-Null
        # *.runtimeconfig.json e *.deps.json: os do caixa em .NET 10 (no .NET Framework nao existem)
        robocopy $release $pasta *.exe *.dll *.exe.config *.dll.config *.runtimeconfig.json *.deps.json /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Falha ao copiar $release" }
        foreach ($sub in "Schemas", "Fonts", "pt-BR") {
            if (Test-Path (Join-Path $release $sub)) {
                robocopy (Join-Path $release $sub) (Join-Path $pasta $sub) /E /NFL /NDL /NJH /NJS /NP | Out-Null
                if ($LASTEXITCODE -ge 8) { throw "Falha ao copiar $release\$sub" }
            }
        }
        $dirAtu = Join-Path $Atualizacoes $prog.Id
        if (-not (Test-Path $dirAtu)) { New-Item -ItemType Directory $dirAtu | Out-Null }
        $zip = "$($prog.Id).zip"
        $zipPath = Join-Path $dirAtu $zip
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($pasta, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
        [IO.File]::WriteAllText((Join-Path $dirAtu "AutoUpdater.xml"), (AutoUpdaterXml $prog.Id $versao.Assembly $zip $zipPath), (New-Object Text.UTF8Encoding $false))
        Write-Host "  atualizacao: atualizacoes/$($prog.Id)/$zip ($($versao.Assembly))"

        $resumo += [pscustomobject]@{ Programa = $prog.Nome; Versao = $versao.Arquivo; Instalador = $prog.Setup; Atualizacao = "atualizacoes/$($prog.Id)/" }
        continue
    }

    if (-not $SemCompilar) {
        $original = Carimbar $ArquivoVersao[$prog.Id]
        try { foreach ($p in $prog.Projetos) { Compilar $p } }
        finally { Restaurar $ArquivoVersao[$prog.Id] $original }
    }

    $release = Join-Path "$OM\Release" $prog.Release
    $exe = Join-Path $release $prog.Exe
    if (-not (Test-Path $exe)) { throw "$($prog.Exe) nao encontrado em $release" }

    $pasta = Join-Path $Preparo $prog.Id
    Preparar $release $pasta
    $versao = VersaoDoExe (Join-Path $pasta $prog.Exe)

    # instalador
    $arquivo = "Setup " + ($prog.Nome -replace '[^A-Za-z0-9 ]', '')
    $defs = @("/DAppId={{$($prog.AppId)}", "/DNome=$($prog.Nome)", "/DExe=$($prog.Exe)", "/DOrigem=$pasta", "/DPasta=$($prog.Destino)",
              "/DIcone=$(Join-Path "$OM\Source" $prog.Icone)", "/DSaida=$Instaladores", "/DArquivo=$arquivo")
    if ($prog.ContainsKey("IniciarComWindows")) { $defs += "/DIniciarComWindows=1" }
    if ($prog.ContainsKey("CalcRT")) { $defs += "/DCalcRT=$(PrepararCalcRT)", "/DJdk=$Jdk" }
    $log = Join-Path $Logs "inno-$($prog.Id).log"
    & $ISCC /Q @defs (Join-Path $Raiz "iss\App.iss") 2>&1 | Out-File $log -Encoding utf8
    if ($LASTEXITCODE -ne 0) { Get-Content $log | Select-Object -Last 10 | ForEach-Object { Write-Host $_ -ForegroundColor Red }; throw "Falha no instalador de $($prog.Nome) (log: $log)" }
    Write-Host "  instalador: $arquivo.exe ($($versao.Arquivo))"

    # pacote de atualizacao no formato do AutoUpdater.NET (zip com o conteudo da pasta + AutoUpdater.xml)
    $dirAtu = Join-Path $Atualizacoes $prog.Id
    if (-not (Test-Path $dirAtu)) { New-Item -ItemType Directory $dirAtu | Out-Null }
    $zip = "$($prog.Id).zip"
    $zipPath = Join-Path $dirAtu $zip
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($pasta, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
    [IO.File]::WriteAllText((Join-Path $dirAtu "AutoUpdater.xml"), (AutoUpdaterXml $prog.Id $versao.Assembly $zip $zipPath), (New-Object Text.UTF8Encoding $false))
    Write-Host "  atualizacao: atualizacoes/$($prog.Id)/$zip ($($versao.Assembly))"

    $resumo += [pscustomobject]@{ Programa = $prog.Nome; Versao = $versao.Arquivo; Instalador = "$arquivo.exe"; Atualizacao = "atualizacoes/$($prog.Id)/" }
}

# catalogo dos instaladores para o portal de downloads (portal\): nome do programa, versao, tamanho, data, SHA-256 e icone.
# Inclui os instaladores de rodadas anteriores que continuam na pasta (rodando so alguns programas com -Programas).
# O icone de cada programa (o .ico do projeto) vai como PNG em instaladores\icones\<id>.png para a lista do portal.
$nomes = @{}
$icones = @{}
$pastaIcones = Join-Path $Instaladores "icones"
if (Test-Path $pastaIcones) { Remove-Item $pastaIcones -Recurse -Force }
New-Item -ItemType Directory -Force $pastaIcones | Out-Null
Add-Type -AssemblyName System.Drawing
foreach ($p in $Lista) {
    $setup = if ($p.ContainsKey("Setup")) { $p.Setup } else { "Setup " + ($p.Nome -replace '[^A-Za-z0-9 ]', '') + ".exe" }
    $nomes[$setup] = $p.Nome
    if (-not $p.ContainsKey("Icone")) { continue }
    $ico = if ($p.ContainsKey("Repo")) { Join-Path $p.Repo $p.Icone } elseif ($p.ContainsKey("Caixa")) { Join-Path $CaixaRepo $p.Icone } else { Join-Path "$OM\Source" $p.Icone }
    try {
        # o tamanho mais proximo de 64 px que o .ico tiver (a pagina mostra em 32 px; 64 fica nitido em tela de alta densidade)
        $icone = New-Object System.Drawing.Icon($ico, 64, 64)
        $bmp = $icone.ToBitmap()
        try { $bmp.Save((Join-Path $pastaIcones "$($p.Id).png"), [System.Drawing.Imaging.ImageFormat]::Png) }
        finally { $bmp.Dispose(); $icone.Dispose() }
        $icones[$setup] = "icones/$($p.Id).png"
    }
    catch { Write-Warning "Icone de $($p.Nome) ($ico): $($_.Exception.Message)" }
}
$catalogo = @(Get-ChildItem $Instaladores -Filter *.exe | Sort-Object Name | ForEach-Object {
    [ordered]@{
        arquivo  = $_.Name
        programa = if ($nomes.ContainsKey($_.Name)) { $nomes[$_.Name] } else { $_.BaseName -replace '^Setup ', '' }
        versao   = "$($_.VersionInfo.ProductVersion)".Trim()
        tamanho  = $_.Length
        data     = $_.LastWriteTime.ToString("s")
        sha256   = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
        icone    = if ($icones.ContainsKey($_.Name)) { $icones[$_.Name] } else { "" }
    }
})
[IO.File]::WriteAllText((Join-Path $Instaladores "instaladores.json"), (ConvertTo-Json $catalogo -Depth 3), (New-Object Text.UTF8Encoding $false))
# o portal substitui a antiga pagina publica (index.html)
$antigo = Join-Path $Publicar "index.html"
if (Test-Path $antigo) { Remove-Item $antigo -Force }

Passo "Pronto em $([int]((Get-Date) - $inicio).TotalMinutes) min: $Publicar"
$resumo | Format-Table -AutoSize

if ($Enviar) { & (Join-Path $Raiz "Enviar.ps1") }
