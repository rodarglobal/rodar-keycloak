# rodar-keycloak

Keycloak (OIDC/SSO) do RODAR: realm `rodar`, clients por produto, empresas como Organizations, temas da marca e
ambiente local em Docker.

- **Guia da estrutura** (o que existe, token, integração, operações): [docs/ESTRUTURA.md](docs/ESTRUTURA.md)
- **Decisão e alternativas** (por que realm único, clients e Organizations): [docs/adr/0001](docs/adr/0001-estrutura-realm-clients-organizations.md)

## Subir

```bash
cp .env.example .env
docker compose up -d        # Keycloak + Postgres; o kc-setup aplica temas e empresas e sai
./scripts/smoke.sh          # login Authorization Code + PKCE do app, só com curl (aceita: usuário senha)
```

- Admin: http://localhost:8180/admin (credenciais do `.env`)
- Issuer: `http://<host>:8180/realms/rodar`. Em `start-dev` o hostname é dinâmico: o issuer segue o host pelo qual
  o Keycloak é acessado. No celular, use o IP da máquina na rede local ou `localhost` com `adb reverse tcp:8180 tcp:8180`.

## Estrutura

```text
master   só administração (temas RODAR no login e no console)
rodar    realm do produto
├── clients        rodar-mobile · rodar-web · rodar-api
├── organizations  rota-sul · translog-demo           (realm/organizations.conf)
├── papéis         driver · cco-operator · cco-admin
└── tema           rodar
```

| Client | Tipo | Uso |
|---|---|---|
| `rodar-mobile` | público, Authorization Code + PKCE (S256), sem password grant | app do motorista. Redirects `avisai://*` (scheme atual do app), `rodar://*` e `exp://*` (Expo Go) |
| `rodar-web` | público, Authorization Code + PKCE (S256) | painel do CCO (`http://localhost:5173` no Vite) |
| `rodar-api` | só audiência | o access token sai com `aud: rodar-api` para o backend validar |

**Token:** identidade (`sub`, `name`, `email`), `roles` e `organization` (aliases das empresas da pessoa). Os apps
pedem o escopo `organization:*`. Nada de viagem, motorista ou veículo no token: isso fica no backend.

**Login em duas etapas:** com Organizations ligado, o Keycloak pede o e-mail e depois a senha. Com `login_hint`
(o app manda o e-mail do perfil escolhido) ele vai direto para a senha.

### Onde cada coisa é configurada

| O quê | Arquivo | Quando é aplicado |
|---|---|---|
| Realm `rodar` (clients, papéis, usuários de teste, tema) | `realm/rodar-realm.json` | só na **primeira** subida (banco vazio) |
| Empresas e membros | `realm/organizations.conf` | a cada `docker compose up` (`scripts/configure.sh`, cria o que falta) |
| Temas do realm `master` | `scripts/configure.sh` | a cada `docker compose up` |

Mudou o `rodar-realm.json`? Recrie o banco local: `docker compose down -v && docker compose up -d`.

**Cadastrar uma transportadora:** acrescente uma linha em `realm/organizations.conf` e rode
`docker compose up -d kc-setup`.

### Usuários de teste

Senha local `avisai-demo` para todos (só desenvolvimento, dados fictícios).

| Usuário | Papéis | Empresas |
|---|---|---|
| carlos@rotasul.test | driver | rota-sul |
| marina@rotasul.test | driver | rota-sul |
| joao@rotasul.test | driver | rota-sul, translog-demo (agregado) |
| cco@rotasul.test | cco-operator | rota-sul |
| gestor@rotasul.test | cco-operator, cco-admin | rota-sul |
| ana@translog.test | driver | translog-demo |

Os motoristas batem com os perfis de demo do rodar-mobile (`src/features/auth/api/profiles.ts`).

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

O realm `master` não vem do JSON: o serviço `kc-setup` do compose roda `scripts/configure.sh` depois que o
Keycloak fica pronto e aplica os temas (idempotente). Ao atualizar a versão do Keycloak, confira o console: o CSS
depende das classes do PatternFly e pode precisar de ajuste.

## Ainda não feito

- Produção: `start` com HTTPS, hostname fixo, admin permanente no lugar do admin temporário do bootstrap, segredos fora do `.env`.
- Backend validando o JWT (JWKS em `/realms/rodar/protocol/openid-connect/certs`, `iss` do realm, `aud=rodar-api`) e filtrando pela `organization`.
- Painel web (`rodar-web`) entrando pelo client `rodar-web`.
- Login do motorista por celular + código (o mockup prevê SMS; ver pendências da ADR).
- Configuração como código para staging/prod (`keycloak-config-cli` ou Terraform).
