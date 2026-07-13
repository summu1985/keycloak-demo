#!/usr/bin/env bash
set -euo pipefail

NS=${NS:-keycloak-demo}
REALM=${REALM:-customer-iam}
FLOW_ALIAS=${FLOW_ALIAS:-demo-browser-passwordless-otp}
FORMS_ALIAS=${FORMS_ALIAS:-demo-browser-forms}
METHOD_ALIAS=${METHOD_ALIAS:-demo-authentication-method}

DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
KC_URL=${KC_URL:-https://customer-iam-${NS}.${DOMAIN}}
ADMIN_USER=${ADMIN_USER:-$(oc get secret customer-iam-initial-admin -n "$NS" -o jsonpath='{.data.username}' | base64 -d)}
ADMIN_PASS=${ADMIN_PASS:-$(oc get secret customer-iam-initial-admin -n "$NS" -o jsonpath='{.data.password}' | base64 -d)}

urlencode() {
  python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

api() {
  local method=$1 path=$2 body=${3:-}
  if [[ -n "$body" ]]; then
    curl -skS -X "$method" "$KC_URL/admin/realms/$REALM/$path" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      --data-binary "$body"
  else
    curl -skS -X "$method" "$KC_URL/admin/realms/$REALM/$path" \
      -H "Authorization: Bearer $TOKEN"
  fi
}

TOKEN=$(curl -skS -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'client_id=admin-cli' \
  -d 'grant_type=password' \
  --data-urlencode "username=$ADMIN_USER" \
  --data-urlencode "password=$ADMIN_PASS" | jq -r '.access_token // empty')

if [[ -z "$TOKEN" ]]; then
  echo "Unable to obtain the master-realm admin token." >&2
  exit 1
fi

echo "Configuring $FLOW_ALIAS in realm $REALM at $KC_URL"

# Remove an earlier demo flow so the script is repeatable.
OLD_ID=$(api GET 'authentication/flows' | jq -r --arg alias "$FLOW_ALIAS" '.[] | select(.alias==$alias) | .id' | head -1)
if [[ -n "$OLD_ID" ]]; then
  api DELETE "authentication/flows/$OLD_ID" >/dev/null
fi

api POST 'authentication/flows' "$(jq -nc --arg a "$FLOW_ALIAS" '{alias:$a,description:"Username-first LDAP/local/passwordless-mobile demo",providerId:"basic-flow",topLevel:true,builtIn:false}')" >/dev/null

add_execution() {
  local flow_alias=$1 provider=$2 requirement=$3
  local encoded
  encoded=$(urlencode "$flow_alias")
  api POST "authentication/flows/$encoded/executions/execution" "$(jq -nc --arg p "$provider" '{provider:$p}')" >/dev/null
  local execution
  execution=$(api GET "authentication/flows/$encoded/executions" | jq -c --arg p "$provider" '[.[] | select(.providerId==$p)] | last')
  local id
  id=$(jq -r '.id' <<<"$execution")
  jq --arg r "$requirement" '.requirement=$r' <<<"$execution" | api PUT "authentication/executions/$id" "$(cat)" >/dev/null
  echo "$id"
}

add_subflow() {
  local parent_alias=$1 alias=$2 requirement=$3
  local parent_encoded
  parent_encoded=$(urlencode "$parent_alias")
  api POST "authentication/flows/$parent_encoded/executions/flow" \
    "$(jq -nc --arg a "$alias" '{alias:$a,description:"",provider:"basic-flow",type:"basic-flow"}')" >/dev/null
  local execution
  execution=$(api GET "authentication/flows/$parent_encoded/executions" | jq -c --arg a "$alias" '[.[] | select(.displayName==$a)] | last')
  local id
  id=$(jq -r '.id' <<<"$execution")
  jq --arg r "$requirement" '.requirement=$r' <<<"$execution" | api PUT "authentication/executions/$id" "$(cat)" >/dev/null
}

add_config() {
  local execution_id=$1 alias=$2 config_json=$3
  api POST "authentication/executions/$execution_id/config" \
    "$(jq -nc --arg a "$alias" --argjson c "$config_json" '{alias:$a,config:$c}')" >/dev/null
}

# Mirror the built-in browser semantics: Cookie OR the forms subflow.
add_execution "$FLOW_ALIAS" 'auth-cookie' 'ALTERNATIVE' >/dev/null
add_subflow "$FLOW_ALIAS" "$FORMS_ALIAS" 'ALTERNATIVE'

JIT_ID=$(add_execution "$FORMS_ALIAS" 'jit-customer-username-form' 'REQUIRED')
add_config "$JIT_ID" 'jit-customer-registry' \
  '{"customer.registry.url":"http://mock-customer-registry:8080/customers/by-mobile"}'

add_subflow "$FORMS_ALIAS" "$METHOD_ALIAS" 'REQUIRED'
OTP_ID=$(add_execution "$METHOD_ALIAS" 'mobile-passwordless-otp' 'ALTERNATIVE')
add_config "$OTP_ID" 'mobile-otp' \
  '{"sms.api.url":"http://mock-sms-api:8080/send","otp.ttl.seconds":"120","otp.max.attempts":"3"}'
add_execution "$METHOD_ALIAS" 'auth-password-form' 'ALTERNATIVE' >/dev/null
add_execution "$FORMS_ALIAS" 'username-pattern-backend-guard' 'REQUIRED' >/dev/null

# Bind the new flow as the realm browser flow.
REALM_JSON=$(curl -skS "$KC_URL/admin/realms/$REALM" -H "Authorization: Bearer $TOKEN")
jq --arg flow "$FLOW_ALIAS" '.browserFlow=$flow' <<<"$REALM_JSON" | \
  curl -skS -X PUT "$KC_URL/admin/realms/$REALM" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary @- >/dev/null

echo
echo "Authentication flow created and bound: $FLOW_ALIAS"
echo "Expected structure:"
echo "  Cookie                                      ALTERNATIVE"
echo "  $FORMS_ALIAS                                ALTERNATIVE"
echo "    JIT Customer Username Form                REQUIRED"
echo "    $METHOD_ALIAS                             REQUIRED"
echo "      Mobile Number Passwordless OTP          ALTERNATIVE"
echo "      Password Form                           ALTERNATIVE"
echo "    Username Pattern / Backend Guard          REQUIRED"
echo
echo "Verify in Admin Console: Authentication -> Flows -> $FLOW_ALIAS"
