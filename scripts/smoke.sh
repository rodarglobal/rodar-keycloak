#!/usr/bin/env bash
# Smoke test: faz o fluxo Authorization Code + PKCE do app (cliente rodar-mobile) só com curl
# e imprime as claims do ID token. Uso: ./scripts/smoke.sh [usuario] [senha]
set -euo pipefail
BASE="${KC_URL:-http://localhost:${KC_PORT:-8180}}/realms/rodar"
USER_NAME="${1:-carlos@rotasul.test}"
PASS="${2:-avisai-demo}"
CLIENT=rodar-mobile
REDIRECT="avisai://oauthredirect"
JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
VERIFIER="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)"
CHALLENGE="$(printf '%s' "$VERIFIER" | openssl dgst -sha256 -binary | b64url)"

curl -fsS "$BASE/.well-known/openid-configuration" >/dev/null && echo "✓ discovery"

LOGIN_HTML="$(curl -fsS -c "$JAR" -b "$JAR" -G "$BASE/protocol/openid-connect/auth" \
  --data-urlencode "client_id=$CLIENT" --data-urlencode "redirect_uri=$REDIRECT" \
  --data-urlencode "response_type=code" --data-urlencode "scope=${SCOPE:-openid profile email organization:*}" \
  --data-urlencode "code_challenge=$CHALLENGE" --data-urlencode "code_challenge_method=S256" \
  --data-urlencode "state=smoke")"
ACTION="$(printf '%s' "$LOGIN_HTML" | grep -o 'action="[^"]*"' | head -1 | sed 's/action="//;s/"$//;s/&amp;/\&/g')"
[ -n "$ACTION" ] || { echo "✗ formulário de login não encontrado"; exit 1; }
echo "✓ tela de login"

form_action() { grep -o 'action="[^"]*"' | head -1 | sed 's/action="//;s/"$//;s/&amp;/\&/g'; }
# Com Organizations ligado o login é em duas etapas (e-mail, depois senha); sem ele, uma só.
BODY="$(mktemp)"; trap 'rm -f "$JAR" "$BODY"' EXIT
LOCATION="$(curl -sS -o "$BODY" -w '%{redirect_url}' -c "$JAR" -b "$JAR" \
  --data-urlencode "username=$USER_NAME" --data-urlencode "password=$PASS" "$ACTION")"
if [ -z "$LOCATION" ] && grep -q 'name="password"' "$BODY"; then
  echo "✓ etapa do e-mail (organização)"
  ACTION="$(form_action < "$BODY")"
  LOCATION="$(curl -sS -o "$BODY" -w '%{redirect_url}' -c "$JAR" -b "$JAR" \
    --data-urlencode "password=$PASS" "$ACTION")"
fi
CODE="$(printf '%s' "$LOCATION" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')"
[ -n "$CODE" ] || { echo "✗ login falhou (redirect: $LOCATION)"; grep -oE "data-page-id=\"[^\"]*\"|kc-page-title\"[^<]*<[^>]*>[^<]*|pf-v5-c-alert__title[^>]*>[^<]*" "$BODY" | head -3; exit 1; }
echo "✓ código de autorização em $REDIRECT"

TOKENS="$(curl -fsS "$BASE/protocol/openid-connect/token" \
  --data-urlencode "grant_type=authorization_code" --data-urlencode "client_id=$CLIENT" \
  --data-urlencode "code=$CODE" --data-urlencode "redirect_uri=$REDIRECT" \
  --data-urlencode "code_verifier=$VERIFIER")"
echo "✓ troca do código por tokens (PKCE)"

ID_TOKEN="$(printf '%s' "$TOKENS" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id_token"])')"
ACCESS="$(printf '%s' "$TOKENS" | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')"
decode() { python3 -c 'import sys,json,base64;p=sys.argv[1].split(".")[1];p+="="*(-len(p)%4);print(json.dumps(json.loads(base64.urlsafe_b64decode(p)),ensure_ascii=False,indent=2))' "$1"; }
echo "--- claims"
decode "$ID_TOKEN" | python3 -c 'import json,sys;c=json.load(sys.stdin);[print(f"  {k}: {c.get(k)}") for k in ("iss","name","email","roles","organization")]'
decode "$ACCESS" | python3 -c 'import json,sys;c=json.load(sys.stdin);print("  aud (access):", c.get("aud"));print("  trip_id/driver_id no token:", any(k in c for k in ("trip_id","driver_id")))'
