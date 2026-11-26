#!/usr/bin/env bash
# Smoke test: faz o fluxo Authorization Code + PKCE do app (cliente avisai-mobile) só com curl
# e imprime as claims do ID token. Uso: ./scripts/smoke.sh [usuario] [senha]
set -euo pipefail
BASE="${KC_URL:-http://localhost:${KC_PORT:-8180}}/realms/avisai"
USER_NAME="${1:-carlos@rotasul.test}"
PASS="${2:-avisai-demo}"
CLIENT=avisai-mobile
REDIRECT="avisai://oauthredirect"
JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
VERIFIER="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)"
CHALLENGE="$(printf '%s' "$VERIFIER" | openssl dgst -sha256 -binary | b64url)"

curl -fsS "$BASE/.well-known/openid-configuration" >/dev/null && echo "✓ discovery"

LOGIN_HTML="$(curl -fsS -c "$JAR" -b "$JAR" -G "$BASE/protocol/openid-connect/auth" \
  --data-urlencode "client_id=$CLIENT" --data-urlencode "redirect_uri=$REDIRECT" \
  --data-urlencode "response_type=code" --data-urlencode "scope=openid profile email" \
  --data-urlencode "code_challenge=$CHALLENGE" --data-urlencode "code_challenge_method=S256" \
  --data-urlencode "state=smoke")"
ACTION="$(printf '%s' "$LOGIN_HTML" | grep -o 'action="[^"]*"' | head -1 | sed 's/action="//;s/"$//;s/&amp;/\&/g')"
[ -n "$ACTION" ] || { echo "✗ formulário de login não encontrado"; exit 1; }
echo "✓ tela de login"

LOCATION="$(curl -sS -o /dev/null -w '%{redirect_url}' -c "$JAR" -b "$JAR" \
  --data-urlencode "username=$USER_NAME" --data-urlencode "password=$PASS" "$ACTION")"
CODE="$(printf '%s' "$LOCATION" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')"
[ -n "$CODE" ] || { echo "✗ login falhou (redirect: $LOCATION)"; exit 1; }
echo "✓ código de autorização em $REDIRECT"

TOKENS="$(curl -fsS "$BASE/protocol/openid-connect/token" \
  --data-urlencode "grant_type=authorization_code" --data-urlencode "client_id=$CLIENT" \
  --data-urlencode "code=$CODE" --data-urlencode "redirect_uri=$REDIRECT" \
  --data-urlencode "code_verifier=$VERIFIER")"
echo "✓ troca do código por tokens (PKCE)"

ID_TOKEN="$(printf '%s' "$TOKENS" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id_token"])')"
ACCESS="$(printf '%s' "$TOKENS" | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')"
decode() { python3 -c 'import sys,json,base64;p=sys.argv[1].split(".")[1];p+="="*(-len(p)%4);print(json.dumps(json.loads(base64.urlsafe_b64decode(p)),ensure_ascii=False,indent=2))' "$1"; }
echo "--- ID token"; decode "$ID_TOKEN" | grep -E '"(iss|name|email|driver_id|trip_id|plate|company|roles)"|^\s+"(driver|cco)"'
echo "--- access token aud"; decode "$ACCESS" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("aud"))'
