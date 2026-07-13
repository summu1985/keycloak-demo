#!/usr/bin/env bash
set -euo pipefail
NS=${NS:-keycloak-demo}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
export KEYCLOAK_HOSTNAME=${KEYCLOAK_HOSTNAME:-customer-iam-${NS}.${DOMAIN}}
export KEYCLOAK_IMAGE=${KEYCLOAK_IMAGE:-quay.io/summu85/customer-keycloak:demo-no-enrichment-v3}

envsubst < "$ROOT/05-keycloak-cr.yaml.tpl" | oc apply -f -
oc wait --for=condition=Ready keycloak/customer-iam -n "$NS" --timeout=600s

oc delete keycloakrealmimport customer-iam-realm -n "$NS" --ignore-not-found
oc apply -f "$ROOT/06-realm-import.yaml"
oc wait --for=condition=Done keycloakrealmimport/customer-iam-realm -n "$NS" --timeout=600s || true

# The import runs in a separate process. Restart once so the long-running server
# immediately refreshes realm metadata in this demo topology.
oc delete pod customer-iam-0 -n "$NS" --ignore-not-found
oc wait --for=condition=Ready pod/customer-iam-0 -n "$NS" --timeout=600s

echo "Keycloak URL: https://${KEYCLOAK_HOSTNAME}"
echo "Image: ${KEYCLOAK_IMAGE}"
echo "Admin username: $(oc get secret customer-iam-initial-admin -n "$NS" -o jsonpath='{.data.username}' | base64 -d)"
echo "Admin password: $(oc get secret customer-iam-initial-admin -n "$NS" -o jsonpath='{.data.password}' | base64 -d)"
