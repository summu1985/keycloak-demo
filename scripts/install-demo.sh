#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
NS="${NS:-keycloak-demo}"
KEYCLOAK_IMAGE="${KEYCLOAK_IMAGE:-quay.io/summu85/customer-keycloak:demo-final-v2}"
DELETE_EXISTING="${DELETE_EXISTING:-false}"
if [[ "$DELETE_EXISTING" == true ]] && oc get namespace "$NS" >/dev/null 2>&1; then
  oc delete namespace "$NS"
  until ! oc get namespace "$NS" >/dev/null 2>&1; do sleep 3; done
fi
cd "$ROOT"
chmod +x scripts/*.sh
./scripts/deploy.sh
KEYCLOAK_IMAGE="$KEYCLOAK_IMAGE" ./scripts/deploy-keycloak.sh
./scripts/verify-demo.sh
./scripts/configure-ldap.sh
./scripts/configure-demo.sh
cat <<MSG
Installation complete.
Admin URL: ${KC_URL:-https://customer-iam-${NS}.$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')}/admin/
Next: synchronize LDAP users from the Admin Console (User federation -> demo-openldap -> Synchronize all users), then assign employee_user to sp001 and p001.
MSG
