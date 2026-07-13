apiVersion: k8s.keycloak.org/v2alpha1
kind: Keycloak
metadata:
  name: customer-iam
  namespace: keycloak-demo
spec:
  instances: 2

  image: quay.io/summu85/customer-keycloak:demo-no-enrichment

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

  http:
    httpEnabled: true

  additionalOptions:
    - name: proxy-headers
      value: xforwarded
    - name: hostname-strict
      value: "false"