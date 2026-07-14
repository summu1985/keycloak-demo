#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-keycloak-demo}"
REALM="${REALM:-customer-iam}"
FLOW_ALIAS="${FLOW_ALIAS:-minimal-jit-browser}"
FORMS_ALIAS="${FORMS_ALIAS:-minimal-jit-forms}"

DOMAIN="$(oc get ingress.config.openshift.io cluster \
  -o jsonpath='{.spec.domain}')"

KC_URL="${KC_URL:-https://customer-iam-${NAMESPACE}.${DOMAIN}}"

ADMIN_USER="${ADMIN_USER:-$(
  oc get secret customer-iam-initial-admin \
    -n "$NAMESPACE" \
    -o jsonpath='{.data.username}' |
  base64 -d
)}"

ADMIN_PASS="${ADMIN_PASS:-$(
  oc get secret customer-iam-initial-admin \
    -n "$NAMESPACE" \
    -o jsonpath='{.data.password}' |
  base64 -d
)}"

urlencode() {
  python3 -c \
    'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' \
    "$1"
}

TOKEN="$(
  curl -skS -X POST \
    "$KC_URL/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=admin-cli" \
    -d "grant_type=password" \
    --data-urlencode "username=$ADMIN_USER" \
    --data-urlencode "password=$ADMIN_PASS" |
  jq -r '.access_token // empty'
)"

if [[ -z "$TOKEN" ]]; then
  echo "ERROR: Unable to obtain Keycloak admin token." >&2
  exit 1
fi

api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local output
  local status

  output="$(mktemp)"

  if [[ -n "$body" ]]; then
    status="$(
      curl -skS \
        -o "$output" \
        -w '%{http_code}' \
        -X "$method" \
        "$KC_URL/admin/realms/$REALM/$path" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        --data-binary "$body"
    )"
  else
    status="$(
      curl -skS \
        -o "$output" \
        -w '%{http_code}' \
        -X "$method" \
        "$KC_URL/admin/realms/$REALM/$path" \
        -H "Authorization: Bearer $TOKEN"
    )"
  fi

  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    echo "ERROR: $method $path returned HTTP $status" >&2
    cat "$output" >&2
    echo >&2
    rm -f "$output"
    exit 1
  fi

  cat "$output"
  rm -f "$output"
}

get_execution() {
  local flow_alias="$1"
  local provider_id="$2"
  local encoded

  encoded="$(urlencode "$flow_alias")"

  api GET "authentication/flows/$encoded/executions" |
    jq -c --arg provider "$provider_id" \
      '[.[] | select(.providerId == $provider)] | last'
}

update_requirement() {
  local execution_json="$1"
  local requirement="$2"
  local execution_id
  local update_body

  execution_id="$(jq -r '.id // empty' <<<"$execution_json")"

  if [[ -z "$execution_id" ]]; then
    echo "ERROR: Execution ID was not found." >&2
    echo "$execution_json" >&2
    exit 1
  fi

  update_body="$(
    jq --arg requirement "$requirement" \
      '.requirement = $requirement' <<<"$execution_json"
  )"

  api PUT \
    "authentication/executions/$execution_id" \
    "$update_body" >/dev/null
}

echo "Keycloak URL: $KC_URL"
echo "Realm:        $REALM"
echo "Flow:         $FLOW_ALIAS"

# Confirm custom authenticator is available.
echo "Checking JIT provider..."

api GET \
  "authentication/config-description/jit-customer-username-form" \
  >/dev/null

# Remove an earlier flow with the same alias.
OLD_FLOW_ID="$(
  api GET "authentication/flows" |
    jq -r --arg alias "$FLOW_ALIAS" \
      '.[] | select(.alias == $alias) | .id' |
    head -1
)"

if [[ -n "$OLD_FLOW_ID" ]]; then
  echo "Deleting existing flow: $FLOW_ALIAS"
  api DELETE "authentication/flows/$OLD_FLOW_ID" >/dev/null
fi

echo "Creating top-level flow..."

api POST "authentication/flows" "$(
  jq -nc --arg alias "$FLOW_ALIAS" '{
    alias: $alias,
    description: "Minimal JIT username and password browser flow",
    providerId: "basic-flow",
    topLevel: true,
    builtIn: false
  }'
)" >/dev/null

FLOW_ENCODED="$(urlencode "$FLOW_ALIAS")"

echo "Adding Cookie execution..."

api POST \
  "authentication/flows/$FLOW_ENCODED/executions/execution" \
  '{"provider":"auth-cookie"}' >/dev/null

COOKIE_EXECUTION="$(get_execution "$FLOW_ALIAS" "auth-cookie")"
update_requirement "$COOKIE_EXECUTION" "ALTERNATIVE"

echo "Adding Forms subflow..."

api POST \
  "authentication/flows/$FLOW_ENCODED/executions/flow" \
  "$(
    jq -nc --arg alias "$FORMS_ALIAS" '{
      alias: $alias,
      description: "JIT username followed by password validation",
      provider: "basic-flow",
      type: "basic-flow"
    }'
  )" >/dev/null

FORMS_EXECUTION="$(
  api GET "authentication/flows/$FLOW_ENCODED/executions" |
    jq -c --arg alias "$FORMS_ALIAS" \
      '[.[] | select(.displayName == $alias)] | last'
)"

update_requirement "$FORMS_EXECUTION" "ALTERNATIVE"

FORMS_ENCODED="$(urlencode "$FORMS_ALIAS")"

echo "Adding JIT Customer Username Form..."

api POST \
  "authentication/flows/$FORMS_ENCODED/executions/execution" \
  '{"provider":"jit-customer-username-form"}' >/dev/null

JIT_EXECUTION="$(get_execution "$FORMS_ALIAS" "jit-customer-username-form")"
update_requirement "$JIT_EXECUTION" "REQUIRED"

JIT_ID="$(jq -r '.id' <<<"$JIT_EXECUTION")"

echo "Configuring customer registry..."

api POST \
  "authentication/executions/$JIT_ID/config" \
  "$(
    jq -nc '{
      alias: "jit-customer-registry",
      config: {
        "customer.registry.url":
          "http://mock-customer-registry:8080/customers/by-mobile"
      }
    }'
  )" >/dev/null

echo "Adding Password Form..."

api POST \
  "authentication/flows/$FORMS_ENCODED/executions/execution" \
  '{"provider":"auth-password-form"}' >/dev/null

PASSWORD_EXECUTION="$(get_execution "$FORMS_ALIAS" "auth-password-form")"
update_requirement "$PASSWORD_EXECUTION" "REQUIRED"

echo "Binding flow to the realm..."

REALM_JSON="$(
  curl -skS \
    "$KC_URL/admin/realms/$REALM" \
    -H "Authorization: Bearer $TOKEN"
)"

UPDATED_REALM="$(
  jq \
    --arg flow "$FLOW_ALIAS" \
    '.browserFlow = $flow |
     .registrationFlow = "registration" |
     .registrationAllowed = false' \
    <<<"$REALM_JSON"
)"

STATUS="$(
  curl -skS \
    -o /tmp/keycloak-bind-response.txt \
    -w '%{http_code}' \
    -X PUT \
    "$KC_URL/admin/realms/$REALM" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary "$UPDATED_REALM"
)"

if [[ "$STATUS" != "204" ]]; then
  echo "ERROR: Binding the flow returned HTTP $STATUS" >&2
  cat /tmp/keycloak-bind-response.txt >&2
  exit 1
fi

echo
echo "Minimal authentication flow created and bound:"
echo
echo "$FLOW_ALIAS"
echo "├── Cookie                           ALTERNATIVE"
echo "└── $FORMS_ALIAS                    ALTERNATIVE"
echo "    ├── JIT Customer Username Form  REQUIRED"
echo "    └── Password Form               REQUIRED"
echo
