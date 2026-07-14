#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

FLOW_ALIAS="${FLOW_ALIAS:-demo-browser-passwordless-otp}"
FORMS_ALIAS="${FORMS_ALIAS:-demo-browser-forms}"
METHOD_ALIAS="${METHOD_ALIAS:-demo-authentication-method}"

for c in oc curl jq python3; do require_cmd "$c"; done
refresh_token

echo "Configuring realm $REALM at $KC_URL"

# Disable Verify Profile for JIT mobile users with no name/email attributes.
VERIFY=$(api GET 'authentication/required-actions/VERIFY_PROFILE')
api PUT 'authentication/required-actions/VERIFY_PROFILE' "$(jq '.enabled=false | .defaultAction=false' <<<"$VERIFY")" >/dev/null

# Remove previous flow with same alias.
OLD_ID=$(api GET 'authentication/flows' | jq -r --arg a "$FLOW_ALIAS" '.[]|select(.alias==$a)|.id' | head -1)
[[ -z "$OLD_ID" ]] || api DELETE "authentication/flows/$OLD_ID" >/dev/null

api POST 'authentication/flows' "$(jq -nc --arg a "$FLOW_ALIAS" '{alias:$a,description:"LDAP/local/passwordless mobile OTP demo",providerId:"basic-flow",topLevel:true,builtIn:false}')" >/dev/null

add_execution() {
  local flow="$1" provider="$2" requirement="$3" encoded execution
  encoded=$(urlencode "$flow")
  api POST "authentication/flows/$encoded/executions/execution" "$(jq -nc --arg p "$provider" '{provider:$p}')" >/dev/null
  execution=$(api GET "authentication/flows/$encoded/executions" | jq -c --arg p "$provider" '[.[]|select(.providerId==$p)]|last')
  update_execution_requirement "$flow" "$execution" "$requirement"
  jq -r '.id' <<<"$execution"
}

add_subflow() {
  local parent="$1" alias="$2" requirement="$3" encoded execution
  encoded=$(urlencode "$parent")
  api POST "authentication/flows/$encoded/executions/flow" \
    "$(jq -nc --arg a "$alias" '{alias:$a,description:"",provider:"basic-flow",type:"basic-flow"}')" >/dev/null
  execution=$(api GET "authentication/flows/$encoded/executions" | jq -c --arg a "$alias" '[.[]|select(.displayName==$a)]|last')
  update_execution_requirement "$parent" "$execution" "$requirement"
}

add_config() {
  local id="$1" alias="$2" config="$3"
  api POST "authentication/executions/$id/config" "$(jq -nc --arg a "$alias" --argjson c "$config" '{alias:$a,config:$c}')" >/dev/null
}

add_execution "$FLOW_ALIAS" auth-cookie ALTERNATIVE >/dev/null
add_subflow "$FLOW_ALIAS" "$FORMS_ALIAS" ALTERNATIVE
JIT_ID=$(add_execution "$FORMS_ALIAS" jit-customer-username-form REQUIRED)
add_config "$JIT_ID" jit-customer-registry '{"customer.registry.url":"http://mock-customer-registry:8080/customers/by-mobile"}'
add_subflow "$FORMS_ALIAS" "$METHOD_ALIAS" REQUIRED
OTP_ID=$(add_execution "$METHOD_ALIAS" mobile-passwordless-otp ALTERNATIVE)
add_config "$OTP_ID" mobile-otp-config '{"sms.api.url":"http://mock-sms-api:8080/send","otp.ttl.seconds":"120","otp.max.attempts":"3"}'
add_execution "$METHOD_ALIAS" auth-password-form ALTERNATIVE >/dev/null
add_execution "$FORMS_ALIAS" username-pattern-backend-guard REQUIRED >/dev/null

# Bind flow and disable registration.
REALM_JSON=$(api GET '')
api PUT '' "$(jq --arg f "$FLOW_ALIAS" '.browserFlow=$f | .registrationFlow="registration" | .registrationAllowed=false' <<<"$REALM_JSON")" >/dev/null

# Ensure CSV mapper is fully configured.
CLIENT_UUID=$(api GET 'clients?clientId=employee-app' | jq -r '.[0].id')
CSV=$(api GET "clients/$CLIENT_UUID/protocol-mappers/models" | jq -c '.[]|select(.name=="roles-csv")' | head -1)
CSV_CFG='{"claim.name":"roles_csv","access.token.claim":"true","id.token.claim":"true","userinfo.token.claim":"true"}'
if [[ -n "$CSV" ]]; then
  CSV_ID=$(jq -r '.id' <<<"$CSV")
  api PUT "clients/$CLIENT_UUID/protocol-mappers/models/$CSV_ID" "$(jq --argjson c "$CSV_CFG" '.config=$c' <<<"$CSV")" >/dev/null
else
  api POST "clients/$CLIENT_UUID/protocol-mappers/models" "$(jq -nc --argjson c "$CSV_CFG" '{name:"roles-csv",protocol:"openid-connect",protocolMapper:"comma-separated-roles-mapper",consentRequired:false,config:$c}')" >/dev/null
fi

# Create second client for SSO demonstration if absent.
CLAIMS_COUNT=$(api GET 'clients?clientId=claims-app' | jq 'length')
if [[ "$CLAIMS_COUNT" == 0 ]]; then
  api POST 'clients' '{"clientId":"claims-app","name":"Claims Demo App","enabled":true,"protocol":"openid-connect","publicClient":true,"standardFlowEnabled":true,"directAccessGrantsEnabled":false,"redirectUris":["https://oauthdebugger.com/debug"],"webOrigins":["https://oauthdebugger.com"]}' >/dev/null
fi

# Enable useful user/admin events.
api PUT 'events/config' '{"eventsEnabled":true,"eventsExpiration":86400,"eventsListeners":["jboss-logging"],"enabledEventTypes":["LOGIN","LOGIN_ERROR","LOGOUT","CODE_TO_TOKEN","CODE_TO_TOKEN_ERROR","UPDATE_PASSWORD","UPDATE_PASSWORD_ERROR"],"adminEventsEnabled":true,"adminEventsDetailsEnabled":true}' >/dev/null

echo "Configured and bound flow: $FLOW_ALIAS"
