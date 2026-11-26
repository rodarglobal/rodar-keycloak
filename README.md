# rodar-keycloak

Keycloak (OIDC/SSO) do RODAR: realm `avisai`, clientes e ambiente local em Docker.

## Subir

```bash
cp .env.example .env
docker compose up -d
./scripts/smoke.sh          # fluxo Authorization Code + PKCE do app, só com curl
```

- Admin: http://localhost:8180/admin (credenciais do `.env`)
- Issuer: `http://<host>:8180/realms/avisai`. Em `start-dev` o hostname é dinâmico: o issuer segue o host
  pelo qual o Keycloak é acessado. Para o celular, use o IP da máquina na rede local (ex.: `http://192.168.0.10:8180/realms/avisai`).

O realm é importado de `realm/avisai-realm.json` só na **primeira** subida (banco vazio). Para reimportar
depois de mudar o JSON: `docker compose down -v && docker compose up -d`.

## Realm `avisai`

| Cliente | Tipo | Uso |
|---|---|---|
| `avisai-mobile` | público, Authorization Code + PKCE (S256), sem password grant | app do motorista. Redirects `avisai://*` (dev client) e `exp://*` (Expo Go) |
| `avisai-api` | só audience | o access token do app sai com `aud: avisai-api` para o backend validar |

Claims extras no ID/access token: `driver_id` (número), `trip_id`, `plate`, `company`, `roles` (`driver` | `cco`).

Usuários de teste (senha local `avisai-demo`, só ambiente de desenvolvimento):

| Usuário | Papel | driver_id / trip_id |
|---|---|---|
| carlos@rotasul.test | driver | 1 |
| marina@rotasul.test | driver | 2 |
| joao@rotasul.test | driver | 3 |
| cco@rotasul.test | cco | – |

Os e-mails batem com os perfis de demo do app (`avisai-mobile`, `src/features/auth/api/profiles.ts`).

## Tema de login `rodar`

`themes/rodar/login` herda as páginas do `keycloak.v2` (senha, OTP, erro, sessão expirada) e troca só o
layout (`template.ftl`) e o visual (`resources/css/rodar.css`), com os mesmos tokens e fontes do
[rodar-web](https://github.com/rodarglobal/rodar-web) (`src/index.css`) e do rodar-mobile (`tailwind.config.js`):

- Celular: tela cheia como o app, assinatura RODAR + "com AvisAI, seu copiloto de voz", seletor PT/EN, campos e botão de 56px.
- Tela larga: card `ink-900` centralizado sobre o degradê do login do painel web.
- Textos em `messages/messages_{pt_BR,en}.properties`. Fontes Inter, Space Grotesk e Kumbh Sans (OFL) em `resources/fonts`.

O tema é montado no container e o realm já usa `loginTheme: rodar`. Em `start-dev` o cache de tema fica
desligado: editar o CSS e recarregar a página basta.

## Console de administração

- **Login do console** (realm `master`): mesmo tema `rodar`, com textos de administração ("Administração de acesso").
- **Console** (`themes/rodar/admin`): o app do Keycloak com logo RODAR no topo, ícone e título da aba
  ("RODAR · Administração"), sempre escuro, cores da marca e Space Grotesk nos títulos
  (`resources/css/rodar-admin.css`, só variáveis e poucos seletores do PatternFly 5). O layout das telas é o do Keycloak.
- `resources/img/rodar-logo.svg` é o símbolo + "RODAR" com a palavra em contorno (Kumbh Sans 750), porque SVG em `<img>` não usa as fontes da página.

O realm `master` não vem do JSON: o serviço `kc-setup` do compose roda `scripts/configure-master.sh` depois que o
Keycloak fica pronto e aplica os temas (idempotente). Ao atualizar a versão do Keycloak, confira o console: o CSS
depende das classes do PatternFly e pode precisar de ajuste.

## Ainda não feito

- Produção: `start` com HTTPS, hostname fixo, admin permanente no lugar do admin temporário do bootstrap, segredos fora do `.env`.
- Backend validando o JWT (JWKS em `/realms/avisai/protocol/openid-connect/certs`, `aud=avisai-api`).
