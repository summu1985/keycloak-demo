#!/usr/bin/env bash
set -euo pipefail
NS=${NS:-keycloak-demo}
POD=${POD:-customer-iam-0}

echo '== Pods =='
oc get pods -n "$NS"

echo '== Custom image =='
oc get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].image}'; echo

echo '== Provider JAR =='
oc exec "$POD" -n "$NS" -c keycloak -- ls -l /opt/keycloak/providers

echo '== Authenticator factories =='
oc exec "$POD" -n "$NS" -c keycloak -- sh -c \
  'unzip -p /opt/keycloak/providers/keycloak-demo-extensions.jar META-INF/services/org.keycloak.authentication.AuthenticatorFactory'

echo '== Protocol mappers =='
oc exec "$POD" -n "$NS" -c keycloak -- sh -c \
  'unzip -p /opt/keycloak/providers/keycloak-demo-extensions.jar META-INF/services/org.keycloak.protocol.ProtocolMapper'

echo '== Mock customer registry =='
oc run registry-check -n "$NS" --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s http://mock-customer-registry:8080/customers/by-mobile/9876543210; echo

echo '== Services =='
oc get svc -n "$NS" | grep -E 'openldap|mock-sms-api|mock-customer-registry|customer-iam'
