#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${NAMESPACE:-keycloak-demo}"
KEYCLOAK_POD="$(
  oc get pods \
    -n "$NAMESPACE" \
    -l app=keycloak \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
)"

if [[ -z "$KEYCLOAK_POD" ]]; then
  KEYCLOAK_POD="$(
    oc get pods \
      -n "$NAMESPACE" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
      | grep '^customer-iam-' \
      | grep -v 'realm' \
      | head -1
  )"
fi

if [[ -z "$KEYCLOAK_POD" ]]; then
  echo "Unable to locate the Keycloak pod."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
JAR_FILE="$TMP_DIR/keycloak-demo-extensions.jar"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "== Pods =="
oc get pods -n "$NAMESPACE"

echo
echo "== Custom image =="
oc get pod "$KEYCLOAK_POD" \
  -n "$NAMESPACE" \
  -o jsonpath='{.spec.containers[?(@.name=="keycloak")].image}'
echo

echo
echo "== Provider JAR in pod =="
oc exec "$KEYCLOAK_POD" \
  -n "$NAMESPACE" \
  -c keycloak \
  -- ls -l /opt/keycloak/providers

echo
echo "== Copying provider JAR locally =="
oc cp \
  "$NAMESPACE/$KEYCLOAK_POD:/opt/keycloak/providers/keycloak-demo-extensions.jar" \
  "$JAR_FILE" \
  -c keycloak

echo
echo "== Authenticator factories =="
unzip -p "$JAR_FILE" \
  META-INF/services/org.keycloak.authentication.AuthenticatorFactory

echo
echo "== Protocol mappers =="
unzip -p "$JAR_FILE" \
  META-INF/services/org.keycloak.protocol.ProtocolMapper

echo
echo "== Compiled custom provider classes =="
unzip -l "$JAR_FILE" \
  | grep 'com/example/keycloak/.*class' \
  | awk '{print $4}'

echo
echo "Provider verification completed successfully."