#!/usr/bin/env bash
set -euo pipefail
NS=${NS:-keycloak-demo}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
export KEYCLOAK_HOSTNAME=${KEYCLOAK_HOSTNAME:-customer-iam-${NS}.${DOMAIN}}
envsubst < "$ROOT/05-keycloak-cr.yaml.tpl" | oc apply -f -
oc wait --for=condition=Ready keycloak/customer-iam -n "$NS" --timeout=600s
oc apply -f "$ROOT/06-realm-import.yaml"
echo "Keycloak URL: https://${KEYCLOAK_HOSTNAME}"
echo "Admin username: $(oc get secret customer-iam-initial-admin -n "$NS" -o jsonpath='{.data.username}' | base64 -d)"
echo "Admin password: $(oc get secret customer-iam-initial-admin -n "$NS" -o jsonpath='{.data.password}' | base64 -d)"
