#!/usr/bin/env bash
set -euo pipefail
NS="${NS:-keycloak-demo}"
POD=$(oc get pods -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep '^customer-iam-' | grep -v realm | head -1)
[[ -n "$POD" ]] || { echo "Keycloak pod not found" >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
JAR="$TMP/keycloak-demo-extensions.jar"
echo '== Pods =='; oc get pods -n "$NS"
echo '== Custom image =='; oc get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[?(@.name=="keycloak")].image}'; echo
echo '== Provider JAR =='; oc exec "$POD" -n "$NS" -c keycloak -- ls -l /opt/keycloak/providers
oc exec "$POD" -n "$NS" -c keycloak -- cat /opt/keycloak/providers/keycloak-demo-extensions.jar > "$JAR"
echo '== Authenticator factories =='; unzip -p "$JAR" META-INF/services/org.keycloak.authentication.AuthenticatorFactory
echo '== Protocol mappers =='; unzip -p "$JAR" META-INF/services/org.keycloak.protocol.ProtocolMapper
echo '== Templates =='; unzip -l "$JAR" | awk '/theme-resources\/templates\//{print $4}'

echo '== Enrichment API =='
oc get \
  deployment/mock-enrichment-api \
  service/mock-enrichment-api \
  -n "$NS"
oc exec deployment/mock-enrichment-api -n "$NS" -- python3 -c 'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:8080/health").read().decode())'
