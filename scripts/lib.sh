#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-keycloak-demo}"
REALM="${REALM:-customer-iam}"
DOMAIN="${DOMAIN:-$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')}"
KC_URL="${KC_URL:-https://customer-iam-${NS}.${DOMAIN}}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

load_admin_credentials() {
  ADMIN_USER="$(
    oc get secret customer-iam-initial-admin \
      -n "$NS" \
      -o jsonpath='{.data.username}' |
    base64 -d
  )"

  ADMIN_PASS="$(
    oc get secret customer-iam-initial-admin \
      -n "$NS" \
      -o jsonpath='{.data.password}' |
    base64 -d
  )"

  export ADMIN_USER ADMIN_PASS
}

refresh_token() {
  load_admin_credentials
  TOKEN=$(curl -skS -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d 'client_id=admin-cli' -d 'grant_type=password' \
    --data-urlencode "username=$ADMIN_USER" --data-urlencode "password=$ADMIN_PASS" | jq -r '.access_token // empty')
  [[ -n "$TOKEN" ]] || { echo "Unable to obtain Keycloak admin token" >&2; exit 1; }
  export TOKEN
}

api() {
  local method="$1" path="$2" body="${3:-}" tmp status
  tmp=$(mktemp)
  if [[ -n "$body" ]]; then
    status=$(curl -skS -o "$tmp" -w '%{http_code}' -X "$method" \
      "$KC_URL/admin/realms/$REALM/$path" \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data-binary "$body")
  else
    status=$(curl -skS -o "$tmp" -w '%{http_code}' -X "$method" \
      "$KC_URL/admin/realms/$REALM/$path" -H "Authorization: Bearer $TOKEN")
  fi
  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    echo "API failure: $method $path returned HTTP $status" >&2
    cat "$tmp" >&2; echo >&2; rm -f "$tmp"; return 1
  fi
  cat "$tmp"; rm -f "$tmp"
}

urlencode() {
  python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

update_execution_requirement() {
  local flow_alias="$1" execution_json="$2" requirement="$3" encoded body
  encoded=$(urlencode "$flow_alias")
  body=$(jq --arg r "$requirement" '.requirement=$r' <<<"$execution_json")
  api PUT "authentication/flows/$encoded/executions" "$body" >/dev/null
}
