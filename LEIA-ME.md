# OfficeDeploy

Gera os instaladores e os pacotes de atualização de todos os programas do OfficeManager e do Caixa (modo OfficeManager),
e publica no servidor de atualizações.

| Arquivo | O que faz |
|---|---|
| `Gerar.cmd` / `Gerar.ps1` | Compila em Release, prepara cada programa e gera tudo em `publicar\` |
| `Enviar.cmd` / `Enviar.ps1` | Envia `publicar\` para `root@76.13.236.246:/var/www/update` |
| `GerarEEnviar.cmd` | Os dois em seguida |
| `iss\App.iss` | Modelo do instalador (Inno Setup 6), o mesmo para todos os programas |
| `portal\` | Portal de downloads com login (ASP.NET Core 10) em `https://update.gestaoagil.com.br` |
| `PublicarPortal.ps1` | Publica o portal, o serviço `update-portal` e o nginx no servidor |

## Programas

| Id | Programa | Origem (`D:\Desenv\IA\OfficeManager\Release\…`) | Instala em |
|---|---|---|---|
| `officemanager` | OfficeManager (+ Configurador e Startup) | `OfficeManager` | `C:\OfficeManager` |
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
- os caixas pelo `Inicializacao.UrlAtualizacao` (janela padrão do AutoUpdater: atualizar, lembrar depois ou pular).

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
portal chama `http://127.0.0.1:8000/api/Accounts/Login`, sem a senha sair da máquina. No servidor antigo, o nginx
`portal\deploy\brpdv-antigo.conf` (em `/etc/nginx/conf.d/update.conf` de lá) só redireciona `update.brpdv.com.br`
para `update.gestaoagil.com.br` (programas que ainda tenham o endereço antigo continuam recebendo as atualizações).

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
o pacote parte dela. Ficam de fora: `*.pdb`, `*.bak`, `*.vshost.*`, as pastas de idioma (só `pt-BR` fica) e a
documentação XML das DLLs (`Nome.xml` ao lado de `Nome.dll`). O resultado fica em `preparo\<id>`.

## Envio (SSH)

Só vão os arquivos novos ou alterados (comparação por SHA-256 com o publicado; `-Tudo` manda tudo). O servidor
copia o publicado para `/var/www/update.envio`, recebe ali as mudanças e só no fim troca as pastas; a versão
anterior fica em `/var/www/update.anterior`. No fim o publicado é conferido arquivo a arquivo com o local.
A conexão daqui sobe a ~100 KB/s: o primeiro envio (~2 GB) leva horas; os seguintes, só o que mudou.

A chave SSH (no PowerShell, uma vez; pede a senha do root):

```
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@76.13.236.246 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

## Requisitos

Visual Studio (MSBuild, .NET Framework 4.8 e DevExpress 24.1), Inno Setup 6, OpenSSH do Windows.
Os logs de compilação e do Inno Setup ficam em `logs\`.
