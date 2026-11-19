# office.brpdv.com.br no servidor novo

OfficeManager web (página + API que os Gateways das lojas usam) e o banco `om`, do servidor antigo
(166.0.186.213) para o do gestaoagil (76.13.236.246). Virada feita em 19/11/2026 (03:04 às 04:07; a API ficou
fora ~63 min e os Gateways reenviaram o que acumularam).

| Arquivo | O que é |
|---|---|
| `office.conf` | nginx (`/etc/nginx/conf.d/office.conf`): página em `/var/www/officev2/app`, `/api` para a API |
| `kestrel-officemanager.service` | API (`/var/www/officev2/api`, .NET 10, `127.0.0.1:3000`) |
| `Virada.ps1` | a virada (para a API antiga, backup, transferência, restauração, repasse no antigo); `-Certificado`, `-Voltar` |

## No servidor novo

- **Postgres 18** (pacotes do PGDG) na porta **5433**, só local, ao lado do Postgres 16 do Gestão (5432);
  `conf.d/90-office.conf` (memória). Banco `om` em `pt_BR.UTF-8` (o mesmo do antigo), dono `office`: a API usa
  esse usuário, não mais o superusuário `postgres`. A senha fica só no `appsettings.json` do servidor.
- API e página copiadas do antigo sem mudança; no `appsettings.json` só a conexão (`Port=5433`, usuário `office`).
- `client_max_body_size 20m` (o antigo usava o padrão de 1 MB).
- Certificado do certbot (webroot em `/var/www/officev2/app`).

## No servidor antigo

- API do office parada e desligada. O repasse do `/api` para o servidor novo ficou ligado até os Gateways
  renovarem o DNS (com `keepalive_requests 50; keepalive_timeout 10s;` para forçar novas conexões); zerou às
  07:51 e foi desligado em 19/11/2026 às 09:36 (`officev2.conf` e `revendas.conf` guardados em
  `/root/nginx-*.conf.desligado-20261119093619`; para religar, copiar de volta para `/etc/nginx/conf.d/`).
- Postgres fechado para a internet (só `localhost`); o banco `om` de lá fica como cópia de segurança.

## Problema que já existia (não é da mudança)

~93% dos envios dos Gateways voltam 400 e são reenviados sem parar:

- estoques de produtos que não existem no web (FK `produtosestoques` → `produtos`, empresas 15 e 18 principalmente);
  um produto faltando derruba o lote de 100;
- notas das empresas 7, 29 e 47, que não estão em `companies`.
