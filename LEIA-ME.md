# OfficeDeploy

Gera os instaladores e os pacotes de atualização de todos os programas do OfficeManager e do Caixa (modo OfficeManager),
e publica no servidor de atualizações.

| Arquivo | O que faz |
|---|---|
| `Gerar.cmd` / `Gerar.ps1` | Compila em Release, prepara cada programa e gera tudo em `publicar\` |
| `Enviar.cmd` / `Enviar.ps1` | Envia `publicar\` para `root@166.0.186.213:/var/www/officeupdate` |
| `GerarEEnviar.cmd` | Os dois em seguida |
| `iss\App.iss` | Modelo do instalador (Inno Setup 6), o mesmo para todos os programas |

## Programas

| Id | Programa | Origem (`D:\Desenv\C#\OfficeManager\Release\…`) | Instala em |
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

## O que sai em `publicar\` (espelho de `/var/www/officeupdate`)

```
index.html                                  lista dos instaladores (para abrir no navegador)
instaladores\Setup <Programa>.exe           um instalador por programa
atualizacoes\<id>\<id>.zip                  pacote no formato do AutoUpdater.NET
atualizacoes\<id>\AutoUpdater.xml           versão e endereço do zip
```

## Atualização automática

Todos os programas buscam `https://update.brpdv.com.br/atualizacoes/<id>/AutoUpdater.xml`:

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
O endereço usado nos XML é o parâmetro `-UrlBase` do `Gerar.ps1` (padrão `https://update.brpdv.com.br`).

## Servidor (nginx)

- `https://update.brpdv.com.br` (e `http://`, para Windows antigos sem TLS 1.2): `/etc/nginx/conf.d/update.conf`,
  raiz `/var/www/officeupdate`, sem listagem de pastas, `AutoUpdater.xml` sem cache. Certificado do Let's Encrypt
  (certbot, renovação automática).
- Também por IP: `http://166.0.186.213/officeupdate/` (bloco `location /officeupdate/` no `sites-available/default`).

## Preparação de cada programa

A origem é a pasta `Release` do programa, depois de compilar os seus projetos. Essa pasta também tem arquivos
que não saem da compilação (DFe, SQLUpdate, ReportsBI, CalcRT, Layouts, Dashboards, OfficeManagerAc.dll), por isso
o pacote parte dela. Ficam de fora: `*.pdb`, `*.bak`, `*.vshost.*`, as pastas de idioma (só `pt-BR` fica) e a
documentação XML das DLLs (`Nome.xml` ao lado de `Nome.dll`). O resultado fica em `preparo\<id>`.

## Envio (SSH)

Só vão os arquivos novos ou alterados (comparação por SHA-256 com o publicado; `-Tudo` manda tudo). O servidor
copia o publicado para `/var/www/officeupdate.envio`, recebe ali as mudanças e só no fim troca as pastas; a versão
anterior fica em `/var/www/officeupdate.anterior`. No fim o publicado é conferido arquivo a arquivo com o local.
A conexão daqui sobe a ~100 KB/s: o primeiro envio (~2 GB) leva horas; os seguintes, só o que mudou.

A chave SSH (no PowerShell, uma vez; pede a senha do root):

```
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@166.0.186.213 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

## Requisitos

Visual Studio (MSBuild, .NET Framework 4.8 e DevExpress 24.1), Inno Setup 6, OpenSSH do Windows.
Os logs de compilação e do Inno Setup ficam em `logs\`.
