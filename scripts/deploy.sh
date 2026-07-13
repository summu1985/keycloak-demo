#!/usr/bin/env bash
set -euo pipefail

NS=${NS:-keycloak-demo}
GIT_REPO=${GIT_REPO:-https://github.com/summu1985/keycloak-demo.git}
GIT_REF=${GIT_REF:-main}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

oc apply -f "$ROOT/00-namespace.yaml"
oc apply -f "$ROOT/01-operatorgroup.yaml" -f "$ROOT/02-subscription.yaml"

echo "Waiting for RHBK CRDs..."
until oc get crd keycloaks.k8s.keycloak.org >/dev/null 2>&1; do
  sleep 5
done

oc apply \
  -f "$ROOT/03-postgres.yaml" \
  -f "$ROOT/04-keycloak-db-secret.yaml" \
  -f "$ROOT/08-token-enrichment-api.yaml" \
  -f "$ROOT/09-openldap.yaml" \
  -f "$ROOT/10-mock-sms-api.yaml" \
  -f "$ROOT/11-mock-customer-registry.yaml"

if oc auth can-i use scc/anyuid >/dev/null 2>&1 && \
   [[ "$(oc auth can-i use scc/anyuid)" == "yes" ]]; then
  echo "Granting anyuid SCC to openldap-sa (demo only)..."
  oc adm policy add-scc-to-user anyuid -z openldap-sa -n "$NS"
else
  cat <<MSG
WARNING: The current user cannot grant the anyuid SCC.
A cluster administrator must run:

  oc adm policy add-scc-to-user anyuid -z openldap-sa -n $NS

Then restart OpenLDAP:

  oc rollout restart deployment/openldap -n $NS
MSG
fi

oc rollout restart deployment/openldap -n "$NS" || true

echo "Waiting for OpenLDAP rollout..."
if ! oc rollout status deployment/openldap -n "$NS" --timeout=180s; then
  echo "OpenLDAP did not become ready. Check:"
  echo "  oc logs deployment/openldap -n $NS --all-containers"
  echo "  oc describe pod -l app=openldap -n $NS"
  exit 1
fi


echo "Waiting for mock APIs..."
oc rollout status deployment/token-enrichment-api -n "$NS" --timeout=180s
oc rollout status deployment/mock-sms-api -n "$NS" --timeout=180s
oc rollout status deployment/mock-customer-registry -n "$NS" --timeout=180s

oc apply -f "$ROOT/07-custom-image-build.yaml"

echo "Configuring BuildConfig source: $GIT_REPO @ $GIT_REF"
oc patch buildconfig customer-keycloak -n "$NS" --type=merge -p "{\"spec\":{\"source\":{\"git\":{\"uri\":\"$GIT_REPO\",\"ref\":\"$GIT_REF\"}}}}"

echo "Infrastructure deployment complete."
echo "Start the custom image build after this repository/branch contains extensions/:"
echo "  oc start-build customer-keycloak -n $NS --follow"
echo "Build source configured from GIT_REPO=$GIT_REPO GIT_REF=$GIT_REF"
echo "Then run:"
echo "  ./scripts/deploy-keycloak.sh"
