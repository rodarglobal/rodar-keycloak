# avisai-keycloak

Keycloak (OIDC/SSO) do AvisAI: realm `avisai`, clientes e ambiente local em Docker.

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

## Ainda não feito

- Produção: `start` com HTTPS, hostname fixo, admin fora do bootstrap, segredos fora do `.env`.
- Backend validando o JWT (JWKS em `/realms/avisai/protocol/openid-connect/certs`, `aud=avisai-api`).
- Tema de login com a identidade visual do AvisAI.
