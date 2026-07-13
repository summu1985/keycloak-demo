apiVersion: k8s.keycloak.org/v2alpha1
kind: Keycloak
metadata:
  name: customer-iam
  namespace: keycloak-demo
spec:
  instances: 1
  image: ${KEYCLOAK_IMAGE}
  db:
    vendor: postgres
    host: keycloak-db
    database: keycloak
    usernameSecret:
      name: keycloak-db-secret
      key: username
    passwordSecret:
      name: keycloak-db-secret
      key: password
  hostname:
    hostname: ${KEYCLOAK_HOSTNAME}
    strict: false
  proxy:
    headers: xforwarded
  http:
    httpEnabled: true
