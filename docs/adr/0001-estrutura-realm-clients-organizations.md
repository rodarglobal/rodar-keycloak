# ADR 0001 · Um realm por ambiente, produtos como clients, empresas como Organizations

- **Status:** aceito
- **Data:** 2026-11-26
- **Escopo:** identidade e acesso do RODAR (app do motorista, painel do CCO, backend)

## Contexto

O RODAR atende transportadoras. Cada uma tem motoristas (app `rodar-mobile`) e operadores da central (painel
`rodar-web`), e o backend (`rodar-backend`) serve os dois. O AvisAI é o agente de voz dentro do RODAR, não um
produto separado.

Precisávamos decidir como organizar o Keycloak: um realm por empresa, um realm por produto ou outra forma.
Três fatos do domínio pesaram:

1. **Motorista agregado roda para mais de uma transportadora.** Precisa de uma conta só.
2. **O operador do CCO usa mais de um produto** (painel hoje, outros depois) e deve entrar uma vez só (SSO).
3. **Clientes novos entram com frequência.** Cadastrar uma empresa não pode exigir configurar um realm inteiro.

## Decisão

```text
Keycloak por ambiente (dev, staging e prod são instalações separadas)
├── master   só administração do Keycloak; nenhum app usa
└── rodar    o realm do produto
    ├── Clients ............ um por produto/superfície
    │   ├── rodar-mobile    público, Authorization Code + PKCE (S256)
    │   ├── rodar-web       público, Authorization Code + PKCE (S256)
    │   └── rodar-api       só audiência: o backend aceita tokens com aud=rodar-api
    ├── Organizations ...... uma por empresa cliente (transportadora)
    │   └── domínio do e-mail + provedor de identidade próprio (opcional, SSO com o AD/Google da empresa)
    ├── Papéis de realm .... driver · cco-operator · cco-admin
    └── Temas .............. rodar (login, console de administração)
```

### Regras

- **Um realm por ambiente, chamado `rodar`.** Ambientes diferentes são instalações diferentes do Keycloak, nunca
  realms lado a lado no mesmo servidor.
- **Produto = client.** Produto novo ganha um client no realm `rodar`, não um realm. Clients de app (mobile, web)
  são públicos com PKCE e sem password grant.
- **Empresa = Organization.** O token traz a claim `organization` com o alias das empresas da pessoa
  (`["rota-sul"]`). Uma pessoa pode estar em várias organizações.
- **Os apps pedem o escopo `organization:*`.** Assim o token traz todas as empresas da pessoa, sem tela extra.
  No Keycloak 26, sem pedir o escopo o token não traz a claim, e pedindo só `organization` quem está em mais de uma
  empresa precisa escolher uma no login. O agregado não escolhe: o backend sabe de qual transportadora é a viagem.
- **Login em duas etapas.** Com Organizations ligado, o Keycloak pede primeiro o e-mail (para achar a empresa e,
  se ela tiver, mandar para o SSO dela) e depois a senha.
- **Papel diz o que a pessoa é; a empresa diz para quem.** Os papéis de realm são globais ao usuário. A
  autorização por empresa (o que essa pessoa pode ver e fazer na empresa X) é do backend, que sempre filtra os
  dados pela `organization` do token.
- **O token carrega identidade, não estado do negócio.** Ficam `sub`, nome, e-mail, papéis e organização. Viagem,
  motorista, veículo e rota ficam no backend, ligados ao `sub` (ou ao e-mail). Nada que muda durante o dia
  (`trip_id`) entra no token.
- **O backend valida:** assinatura pelo JWKS do realm, `iss` do realm `rodar` do ambiente, `aud` contendo
  `rodar-api` e expiração.
- **`master` só para administrar o Keycloak.** Os temas RODAR também valem para ele (login e console).

## Alternativas descartadas

**Realm por produto.** Quebraria o SSO entre produtos e duplicaria usuários, senhas, políticas e temas.
No Keycloak, a separação natural de produto é o client.

**Realm por empresa.** Isolamento total, mas:

- o motorista agregado teria uma conta por transportadora;
- o app precisaria descobrir o realm antes do login (tela "qual sua empresa?" ou um endereço por cliente);
- o backend teria de aceitar N emissores;
- cada cliente novo exigiria configurar e manter um realm inteiro;
- o Keycloak perde desempenho com centenas de realms.

**Exceção prevista:** um cliente grande que exija por contrato isolamento total, admin próprio ou marca própria
pode ganhar um realm dedicado. É exceção, não o padrão.

## Consequências

- Cadastrar transportadora = criar uma Organization (nome, alias, domínio) e adicionar os membros.
- O backend precisa da claim `organization` em toda consulta multiempresa e não pode confiar em dados que o
  cliente mande sobre a empresa.
- Pessoa com papéis diferentes em empresas diferentes (motorista na A, CCO na B) não é modelável só no Keycloak 26:
  fica a cargo do backend se aparecer.
- Os apps descobrem viagem e motorista pelo backend a partir do usuário logado, não pelo token.

## Pendências

- **Como o motorista entra:** o mockup prevê celular + código por SMS. O Keycloak não tem SMS pronto: extensão da
  comunidade, autenticador próprio, código por e-mail ou senha.
- **Configuração como código em todos os ambientes:** hoje o realm vem de `realm/rodar-realm.json` (importado só
  na primeira subida) mais `scripts/configure.sh` (idempotente, a cada subida). Para staging e prod, avaliar
  `keycloak-config-cli` ou o provider Terraform do Keycloak.
- **Painel web** (`rodar-web`) entrar pelo client `rodar-web`.
- **Backend** validar o JWT conforme as regras acima.
