#!/usr/bin/env bash
# Roda no serviço kc-setup do docker-compose, depois que o Keycloak fica pronto. Idempotente.
# A imagem do Keycloak não tem awk/jq/python: só bash, grep e coreutils.
#  1. Temas RODAR no realm master (login e console de administração), que não vem do realm/*.json.
#  2. Organizations (empresas) do realm rodar e seus membros, a partir de realm/organizations.conf.
set -euo pipefail
KCADM=/opt/keycloak/bin/kcadm.sh
REALM=rodar
ORGS_FILE=${ORGS_FILE:-/config/organizations.conf}

"$KCADM" config credentials --server http://keycloak:8080 --realm master \
  --user "$KC_ADMIN_USER" --password "$KC_ADMIN_PASSWORD" >/dev/null

"$KCADM" update realms/master \
  -s loginTheme=rodar -s adminTheme=rodar \
  -s internationalizationEnabled=true \
  -s 'supportedLocales=["pt-BR","en"]' -s defaultLocale=pt-BR
echo "kc-setup: temas RODAR no realm master"

trim() { local s="$*"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

org_id() {  # id da organização pelo alias (vazio se não existe)
  # A busca do Keycloak (search) olha nome e domínio, não o alias: lista todas e compara o alias.
  "$KCADM" get organizations -r "$REALM" -q first=0 -q max=1000 --fields id,alias --format csv --noquotes \
    | while IFS=, read -r id al; do [[ "$al" == "$1" ]] && printf '%s\n' "$id"; done || true
}

user_id() {  # id do usuário pelo e-mail (vazio se não existe)
  "$KCADM" get users -r "$REALM" -q email="$1" -q exact=true --fields id --format csv --noquotes | head -n1
}

while IFS='|' read -r alias name domain members; do
  alias=$(trim "$alias")
  [[ -z "$alias" || "$alias" == \#* ]] && continue
  name=$(trim "$name"); domain=$(trim "$domain"); members=$(trim "$members")

  oid=$(org_id "$alias")
  if [[ -z "$oid" ]]; then
    oid=$("$KCADM" create organizations -r "$REALM" -i \
      -s name="$name" -s alias="$alias" -s enabled=true \
      -s "domains=[{\"name\":\"$domain\",\"verified\":false}]")
    echo "kc-setup: organização $alias criada"
  fi

  current=$("$KCADM" get "organizations/$oid/members" -r "$REALM" --fields id --format csv --noquotes || true)
  for email in $members; do
    uid=$(user_id "$email")
    if [[ -z "$uid" ]]; then echo "kc-setup: AVISO usuário $email não existe (org $alias)"; continue; fi
    grep -qx "$uid" <<<"$current" && continue
    "$KCADM" create "organizations/$oid/members" -r "$REALM" -b "\"$uid\"" >/dev/null 2>&1 2>&1
    echo "kc-setup: $email entrou em $alias"
  done
done < "$ORGS_FILE"

echo "kc-setup: concluído"
