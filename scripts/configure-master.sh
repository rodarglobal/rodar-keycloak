#!/usr/bin/env bash
# Roda no serviço kc-setup do docker-compose, depois que o Keycloak fica pronto.
# O realm master não vem do realm/*.json, então os temas RODAR dele são aplicados aqui (idempotente).
set -euo pipefail
KCADM=/opt/keycloak/bin/kcadm.sh
"$KCADM" config credentials --server http://keycloak:8080 --realm master \
  --user "$KC_ADMIN_USER" --password "$KC_ADMIN_PASSWORD" >/dev/null

# Tela de login do console e o próprio console com a marca RODAR, em pt-BR e en.
"$KCADM" update realms/master \
  -s loginTheme=rodar -s adminTheme=rodar \
  -s internationalizationEnabled=true \
  -s 'supportedLocales=["pt-BR","en"]' -s defaultLocale=pt-BR

# Realm avisai já importado antes do campo existir no JSON: e-mail como usuário (rótulo "E-mail" no login).
"$KCADM" update realms/avisai -s registrationEmailAsUsername=true -s loginTheme=rodar

echo "kc-setup: temas RODAR aplicados nos realms master e avisai"
