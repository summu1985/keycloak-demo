#!/usr/bin/env bash
set -euo pipefail
NS=${NS:-keycloak-demo}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
oc apply -f "$ROOT/00-namespace.yaml"
oc apply -f "$ROOT/01-operatorgroup.yaml" -f "$ROOT/02-subscription.yaml"
echo "Waiting for RHBK CRDs..."
until oc get crd keycloaks.k8s.keycloak.org >/dev/null 2>&1; do sleep 5; done
oc apply -f "$ROOT/03-postgres.yaml" -f "$ROOT/04-keycloak-db-secret.yaml" -f "$ROOT/08-token-enrichment-api.yaml" -f "$ROOT/09-openldap.yaml"
oc apply -f "$ROOT/07-custom-image-build.yaml"
echo "Start the custom image build after this repository/branch contains extensions/:"
echo "  oc start-build customer-keycloak -n $NS --follow"
echo "Then run scripts/deploy-keycloak.sh"
