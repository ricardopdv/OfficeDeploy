# Licenças e revendas no servidor novo

Mudança da API do site (licenças, login das revendas, cotações) e do banco `brpdv` do servidor antigo
(166.0.186.213) para o servidor do gestaoagil.com.br (76.13.236.246), **mantendo os nomes `*.brpdv.com.br`**:
os Caixas e os OfficeManager instalados chamam `http://revendas.brpdv.com.br/api/` (fixo no código) e não precisam
de atualização; só o DNS muda.

| Arquivo | O que é |
|---|---|
| `revendas.conf`, `cotacoes.conf` | nginx do servidor novo (`/etc/nginx/conf.d/`): página estática + `/api` para a API |
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

O código-fonte da API (`Web Legacy\DotNet\ASP\Site\site`) já está em .NET 10, mas o publicado é .NET 8 (sem
suporte da Microsoft desde 10/11/2026). Publicar a versão .NET 10 é um passo separado (muda o programa em produção).

## Passo 2: a virada

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

- Endereço novo com HTTPS (ex.: `licencas.gestaoagil.com.br`) nas próximas versões do Caixa e do OfficeManager; o
  `revendas.brpdv.com.br` continua para quem não atualizou.
- Desligar no antigo o MariaDB exposto (o banco `brpdv` fica sem uso lá) depois de algumas semanas.
