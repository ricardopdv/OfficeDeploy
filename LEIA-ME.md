# OfficeDeploy

Gera os instaladores e os pacotes de atualização de todos os programas do OfficeManager e do Caixa (modo OfficeManager),
e publica no servidor de atualizações.

| Arquivo | O que faz |
|---|---|
| `Gerar.cmd` / `Gerar.ps1` | Compila em Release, prepara cada programa e gera tudo em `publicar\` |
| `Enviar.cmd` / `Enviar.ps1` | Envia `publicar\` para `root@166.0.186.213:/var/www/update` |
| `GerarEEnviar.cmd` | Os dois em seguida |
| `iss\App.iss` | Modelo do instalador (Inno Setup 6), o mesmo para todos os programas |
| `portal\` | Portal de downloads com login (ASP.NET Core 10) em `https://update.gestaoagil.com.br` |
| `PublicarPortal.ps1` | Publica o portal, o serviço `update-portal` e o nginx no servidor |

## Programas

| Id | Programa | Origem (`D:\Desenv\IA\OfficeManager\Release\…`) | Instala em |
|---|---|---|---|
| `officemanager` | OfficeManager (+ Configurador) | `OfficeManager` | `C:\OfficeManager` |
| `gateway` | OfficeManager Gateway | `OfficeManagerGw` | `C:\OfficeManager\Gateway` |
| `officemanagerbi` | OfficeManager BI | `OfficeManagerBI` | `C:\OfficeManager\BI` |
| `prevenda` | PreVenda (+ Configurador) | `PreVenda` | `C:\OfficeManager\PreVenda` |
| `backup` | OfficeManager Backup | `OfficeManagerBackup` | `C:\OfficeManager\Backup` |
| `troca` | Trocas (+ Configurador) | `Troca` | `C:\OfficeManager\Trocas` |
| `caixacentral` | Caixa Central | `CaixaCentral` | `C:\OfficeManager\CaixaCentral` |
| `caixa` | Caixa NFCe (modo OfficeManager) | repositório do Caixa (`setup\GerarInstalador.cmd`, `saida\Release\Caixa`) | `D:\Caixa` |
| `caixagestao` | Caixa NFCe só do Gestão | repositório do Caixa (`setup\GerarInstaladorGestao.cmd`, `saida\Release\CaixaGestao`) | `D:\Caixa` |

Os dois caixas geram `Caixa.exe`, por isso cada um busca a atualização na sua pasta (`atualizacoes/caixa` e
`atualizacoes/caixagestao`, em `Inicializacao.UrlAtualizacao`). O pacote de atualização do caixa leva só o programa
(exe, dll, .config, `Schemas`, `Fonts`, `pt-BR`); a configuração do cliente (`CliSiTef.ini`, `ACBrLib.ini`,
`Logocli.png`) e a `CalcRT` ficam de fora (vêm no instalador).

### Caixa em .NET 10 (teste)

| Id | Programa | Origem | Pasta no cliente |
|---|---|---|---|
| `caixanet` | Caixa NFCe .NET 10 (TESTE) | `D:\Desenv\IA\CaixaNet` (`setup\GerarInstalador.cmd`, `saida\Release\Caixa`) | `D:\Caixa` |
| `caixanetgestao` | Caixa NFCe Gestão .NET 10 (TESTE) | `D:\Desenv\IA\CaixaNet` (`setup\GerarInstaladorGestao.cmd`, `saida\Release\CaixaGestao`) | `D:\Caixa` |
| `caixanetlinux` | Caixa NFCe .NET 10 Linux (TESTE) | `D:\Desenv\IA\CaixaNet` (`setup\GerarDeb.ps1`, `saida\Release\linux-x64\Caixa`) | `/opt/caixa` |
| `caixanetgestaolinux` | Caixa NFCe Gestão .NET 10 Linux (TESTE) | `D:\Desenv\IA\CaixaNet` (`setup\GerarDeb.ps1`, `saida\Release\linux-x64\CaixaGestao`) | `/opt/caixa` |

Esses ficam **fora** da geração padrão e só são gerados com `-Programas` (ex.: `-Programas caixanet,caixanetgestao,caixanetlinux,caixanetgestaolinux`).
- **Linux:** o instalador é o pacote `.deb` (`caixa-nfce-teste_amd64.deb`, `caixa-nfce-gestao-teste_amd64.deb`; instalar com `sudo apt install ./caixa-nfce-teste_amd64.deb`, que traz o .NET 10, o MariaDB e o Java 21). O caixa no Linux busca a atualização no canal com `linux` no fim; o pacote de atualização leva a pasta inteira do programa (executáveis sem extensão e as `.so`), sem a configuração do cliente.
- **Canal de atualização próprio:** o caixa convertido busca a atualização em `atualizacoes/caixanet` e `atualizacoes/caixanetgestao`, então os caixas de produção nunca recebem esta versão.
- **Runtime:** o instalador de teste instala o runtime .NET 10 Desktop x86 quando ele não está na máquina.
- **Pacote:** leva também os `*.runtimeconfig.json` e `*.deps.json`.
- **Versão:** no .NET 10 o `Caixa.exe` é só o lançador nativo, por isso a versão é lida do `Caixa.dll`.

## Calculadora da reforma tributária (CalcRT) e Java 21

O OfficeManager e o PreVenda rodam ao abrir `java -jar api-regime-geral.jar` na pasta `.\CalcRT` do programa
(`OfficeManagerDFe\Reforma\VerificarCalculadoraReforma.cs`), com o `java` do PATH. Por isso os instaladores dos dois
(`CalcRT = $true` na `$Lista`) levam:

- a `CalcRT` em `{app}\CalcRT`, a mesma para os dois, copiada de `OfficeManager\Release\OfficeManager\CalcRT` sem a
  cópia antiga (`Old\`) e sem os temporários do SQLite (`*.db-shm`, `*.db-wal`). Só troca arquivos mais novos que os
  instalados; o que estiver preso pela calculadora em execução é trocado no próximo reinício do Windows;
- o JDK 21 (`-Jdk`, padrão: o mesmo do instalador do Caixa, `Caixa\setup\Externos\Utils\JDK\jdk-21_windows-x64_bin.exe`),
  instalado em modo silencioso só se a máquina não tiver Java 21 ou maior registrado e um `java.exe` no PATH. Quando o
  JDK é instalado, o instalador não oferece abrir o programa no fim (ele ainda tem o PATH de antes); pelo atalho abre normal.

O PreVenda usa a calculadora do OfficeManager: só um java com o `api-regime-geral.jar` roda na máquina, e quem abrir
primeiro inicia. A cópia na pasta do PreVenda serve para quando ele abre antes do OfficeManager ou numa máquina sem ele;
sem ela, o programa procura a `CalcRT` da pasta de cima (`C:\OfficeManager\CalcRT` para `C:\OfficeManager\PreVenda`).
Se a calculadora não iniciar (sem Java, Java antigo, pasta faltando), o programa avisa uma vez e segue.

A `CalcRT` nunca vai no pacote de atualização (`atualizacoes\<id>\<id>.zip`): são ~100 MB que quase nunca mudam e o
jar fica preso pela calculadora em execução. Uma `CalcRT` nova chega aos clientes pelo instalador.

A pasta de instalação pode ser trocada na instalação; numa atualização o instalador usa a pasta da instalação anterior.
Pastas padrão, ícones e quais projetos entram em cada programa ficam na lista `$Lista`, no início do `Gerar.ps1`.

## Uso

```
Gerar.cmd                                   todos
Gerar.cmd -Programas troca,gateway          só alguns (pelo Id)
Gerar.cmd -SemCompilar                      só empacota (usa a última compilação)
GerarEEnviar.cmd                            gera tudo e publica
Enviar.cmd                                  publica o que já está em publicar\
```

## O que sai em `publicar\` (espelho de `/var/www/update`)

```
instaladores\Setup <Programa>.exe           um instalador por programa (baixado só pelo portal, com login)
instaladores\instaladores.json              catálogo para o portal: programa, versão, tamanho, data e SHA-256
atualizacoes\<id>\<id>.zip                  pacote no formato do AutoUpdater.NET
atualizacoes\<id>\AutoUpdater.xml           versão e endereço do zip
```

## Atualização automática

Todos os programas buscam `https://update.gestaoagil.com.br/atualizacoes/<id>/AutoUpdater.xml`:

- os do OfficeManager pela rotina única `OfficeManagerDb\Helpers\Atualizacao.cs` (`VerificarAoAbrir` na abertura;
  o Gateway, que fica aberto, `Monitorar` a cada 30 minutos);
- os caixas pelo `Inicializacao.UrlAtualizacao`, com as telas do próprio caixa e o `Caixa.Atualizador.exe` (que vai no
  pacote; veja "Atualização automática" no `LEIA-ME.md` do Caixa). Os caixas instalados antes dele recebem a primeira
  atualização pela janela antiga do AutoUpdater.

Cada `AutoUpdater.xml` leva o SHA-256 do zip (`<checksum algorithm="SHA256">`): o atualizador do Caixa e o AutoUpdater.NET
dos outros programas não instalam um pacote baixado pela metade ou diferente do publicado.

A atualização **não é obrigatória** (`<mandatory>false</mandatory>`): a cada versão nova o usuário é avisado (versão
instalada e nova) e escolhe se atualiza agora. Recusada, a mesma versão não é oferecida de novo enquanto o programa
estiver aberto. Aceita, o programa fecha, o AutoUpdater instala o zip na pasta do programa e abre de novo.

**Versão a cada deploy:** antes de compilar, o `Gerar.ps1` grava no `AssemblyInfo.cs` de cada programa a versão do
deploy (`ano.mês.dia-do-ano.(segundo do dia / 2)`, o formato que os projetos já usam; se o arquivo já tiver uma maior,
soma 1 nela) e, depois de compilar, devolve o arquivo como estava (o repositório não muda). Assim todo deploy publica
uma versão maior que a anterior e os programas instalados oferecem a atualização.

As versões já instaladas antes desta mudança continuam olhando o servidor antigo (`www.brpdv.com.br/sistemas/atualizacoes/om/…`)
até receberem uma versão com o endereço novo (pelo instalador ou por uma última atualização publicada no servidor antigo).
O endereço usado nos XML é o parâmetro `-UrlBase` do `Gerar.ps1` (padrão `https://update.gestaoagil.com.br`).

## Portal de downloads (`portal\`)

Os técnicos entram em `https://update.gestaoagil.com.br` com o **mesmo e-mail e senha do portal das revendas**: o portal
faz o mesmo login do `RevendasRazor` (`POST api/Accounts/Login` do site) e só deixa entrar quem tem o papel
**Admin** ou **Revenda** (os mesmos do portal das revendas).

A API das revendas (`kestrel-site`) está no mesmo servidor desde a virada das revendas (`revendas\LEIA-ME.md`): o
portal chama `http://127.0.0.1:8000/api/Accounts/Login`, sem a senha sair da máquina. O redirecionamento de
`update.brpdv.com.br` para `update.gestaoagil.com.br` no servidor antigo foi removido em 19/11/2026 (guardado em
`/root/nginx-update.conf.desligado-20261119094310` de lá): programas com o endereço antigo não se atualizam mais
sozinhos e precisam ser reinstalados pelo portal.

- Lista os instaladores do `instaladores.json`; o download exige login e é entregue pelo nginx (`X-Accel-Redirect`
  para a location interna `/_instaladores/`); `/instaladores/` direto não abre.
- Cada download fica no log do serviço com o e-mail do técnico: `journalctl -u update-portal`.
- Login: 10 tentativas por minuto por IP; sessão de 8 horas (cookie); só por HTTPS.
- Configuração em `portal\appsettings.json` (endereço do login, papéis, pasta publicada).
- Publicar: `PublicarPortal.ps1` (dotnet publish, `/var/www/update-portal`, serviço `update-portal` em
  `127.0.0.1:8010`, chaves do cookie em `/var/lib/update-portal`, nginx `portal\deploy\update.conf`).
- Rodar local: `dotnet run --project portal` (ambiente Development: login na API pública das revendas, instaladores de `publicar\`).

## Servidor (nginx)

`/etc/nginx/conf.d/update.conf` (cópia em `portal\deploy\update.conf`), raiz `/var/www/update`:

- `https://update.gestaoagil.com.br/atualizacoes/…` público (o AutoUpdater dos programas baixa sem login),
  `AutoUpdater.xml` sem cache; também por `http://` (Windows antigos sem TLS 1.2);
- todo o resto vai para o portal; em `http://` redireciona para `https://`;
- certificado do Let's Encrypt (certbot, renovação automática).

## Preparação de cada programa

A origem é a pasta `Release` do programa, depois de compilar os seus projetos. Essa pasta também tem arquivos
que não saem da compilação (DFe, SQLUpdate, ReportsBI, CalcRT, Layouts, Dashboards, OfficeManagerAc.dll), por isso
o pacote parte dela. Ficam de fora: `*.pdb`, `*.bak`, `*.vshost.*`, as pastas de idioma (só `pt-BR` fica), a
documentação XML das DLLs (`Nome.xml` ao lado de `Nome.dll`) e a `CalcRT` (vai à parte no instalador, de
`preparo\_calcrt`). O resultado fica em `preparo\<id>`.

## Envio (SSH)

Só vão os arquivos novos ou alterados (comparação por SHA-256 com o publicado; `-Tudo` manda tudo). O servidor
copia o publicado para `/var/www/update.envio`, recebe ali as mudanças e só no fim troca as pastas; a versão
anterior fica em `/var/www/update.anterior`. No fim o publicado é conferido arquivo a arquivo com o local.
A conexão daqui sobe a ~100 KB/s: o primeiro envio (~2 GB) leva horas; os seguintes, só o que mudou.

A chave SSH (no PowerShell, uma vez; pede a senha do root):

```
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@166.0.186.213 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

## Servidor

Desde 19/11/2026 (à tarde) tudo roda em **166.0.186.213** (`vps.brpdv.com.br`): update, portal, revendas,
licenças, office, Gestão e BrZap, com um PostgreSQL 18 só (porta 5432) e o MariaDB, os dois só locais. O
76.13.236.246 ficou só repassando para o novo enquanto o DNS propaga. As pastas `office\` e `revendas\` contam as
viradas anteriores do mesmo dia (do 166.0.186.213 antigo para o 76.13.236.246); os `Virada.ps1` delas não servem
mais. As configurações de nginx e systemd do repositório são as que estão no servidor.

## Requisitos

Visual Studio (MSBuild, .NET Framework 4.8 e DevExpress 24.1), Inno Setup 6, OpenSSH do Windows e o instalador do
JDK 21 (veja "Calculadora da reforma tributária").
Os logs de compilação e do Inno Setup ficam em `logs\`.
