# Licenças e revendas no servidor novo

Mudança da API do site (licenças, login das revendas, cotações) e do banco `brpdv` do servidor antigo
(166.0.186.213) para o servidor do gestaoagil.com.br (76.13.236.246), **mantendo os nomes `*.brpdv.com.br`**:
os Caixas e os OfficeManager instalados chamam `http://revendas.brpdv.com.br/api/` (fixo no código) e não precisam
de atualização; só o DNS muda.

| Arquivo | O que é |
|---|---|
| `revendas.conf`, `cotacoes.conf` | nginx do servidor novo (`/etc/nginx/conf.d/`): página estática + `/api` para a API |
| `licencas.conf` | nginx de `licencas.gestaoagil.com.br`: só a API, por HTTPS (o endereço dos programas novos) |
| `kestrel-site.service` | serviço da API no servidor novo (`/etc/systemd/system/`) |
| `Virada.ps1` | a virada (banco, servidor antigo redirecionando) e depois o certificado |

## Passo 1 (feito em 19/11/2026): montado no servidor novo, sem tirar nada do antigo

- MariaDB 10.11 (a mesma versão do antigo), **só em 127.0.0.1** (no antigo a 3306 está aberta na internet).
- Banco `brpdv` copiado (cópia de teste; a virada copia de novo). Usuário `brpdv` com a mesma senha (copiada pelo
  hash), mas **só com acesso ao banco `brpdv`** (no antigo ele tem acesso a todos os bancos).
- API: a mesma publicada no antigo (`/var/www/site`, .NET 8: instalado o `aspnetcore-runtime-8.0`), serviço
  `kestrel-site` em `127.0.0.1:8000`; no `appsettings.json` só o servidor do banco mudou (`127.0.0.1`).
- Páginas `/var/www/revendas` e `/var/www/cotacoes` copiadas; nginx com os mesmos sites (HTTP, como no antigo).
- Conferido: as mesmas respostas da API nos dois servidores (licença, login, consultas) e a mesma página.

**API em .NET 10 (19/11/2026):** publicada a partir do código-fonte (`D:\Desenv\IA\Site\site`), que só
diferia do publicado em .NET 8 pelo `site.csproj` (framework e pacotes). O FastReport 2026 exigiu
`services.AddFastReport()` no `Startup.cs`. Antes da troca rodou lado a lado (porta 8002, mesmo banco) com as mesmas
respostas da versão .NET 8 (licença real, login, consultas, formato das datas). A versão .NET 8 ficou em
`/var/www/site.net8` (voltar: parar o `kestrel-site`, trocar as pastas e iniciar); o `aspnetcore-runtime-8.0` pode
sair do servidor quando ela não for mais necessária. O relatório `api/Reports/PedidoFornecedor` já não funcionava
(a pasta `Reports` não é publicada) e não exige login.

## Passo 2: a virada (feita em 19/11/2026, 01:17)

1. `.\Virada.ps1`: para a API antiga, copia o banco de novo, religa a nova e faz o nginx antigo mandar o `/api`
   (e o login do portal de downloads) para o servidor novo. A partir daqui tudo grava no banco novo, mesmo quem
   ainda resolve o DNS antigo.
2. No DNS do brpdv.com.br: `revendas` → `76.13.236.246` (A). `cotacoes.brpdv.com.br` não tem DNS hoje.
3. Depois de propagar: `.\Virada.ps1 -Certificado` (HTTPS de `revendas.brpdv.com.br` no servidor novo, sem
   obrigar: os programas seguem em HTTP até ganharem o endereço novo).
4. Portal de downloads: em `portal\appsettings.json`, `ApiLogin` = `http://127.0.0.1:8000/api/Accounts/Login`
   (a API passa a estar no mesmo servidor) e `PublicarPortal.ps1`.

Volta, antes de trocar o DNS: `.\Virada.ps1 -Voltar` (religa a API antiga com o nginx de antes; o que for gravado
no banco novo nesse meio tempo fica só lá).

## Passo 3 (depois)

- **Endereço novo com HTTPS (19/11/2026):** `https://licencas.gestaoagil.com.br/api/` (`licencas.conf`, só a API,
  certificado do certbot). O Caixa e o OfficeManager (`Startup.exe`) tentam esse endereço primeiro e, se não
  conseguirem (Windows sem TLS 1.2, DNS), `http://revendas.brpdv.com.br/api/` (`Processos.ServidoresLicenca`, no
  `BrPDV.Lib` dos dois repositórios). O `revendas.brpdv.com.br` continua para quem não atualizou.
- Desligar no antigo o MariaDB exposto (o banco `brpdv` fica sem uso lá) depois de algumas semanas.
