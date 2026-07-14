# RHBK Authentication and External Enrichment Demo on OpenShift

Reusable Red Hat build of Keycloak demo for:

- LDAP employee authentication (`sp*`, `p*`)
- Local Keycloak DB authentication for Agent and Banca users
- Registered mobile-customer validation through a mock customer registry
- Just-in-time mobile-user provisioning
- Passwordless SMS OTP through a mock OTP/SMS API
- Username-pattern backend enforcement
- Realm roles in JSON-array and comma-separated token claims
- SSO between two OIDC clients
- Forced password change for migrated users
- User and administrative audit events
- Synchronous external access-token enrichment through a mock API

This consulting-enrichment variant adds a synchronous protocol mapper that calls a mock enrichment API during access-token creation. The validated customer-facing branch should remain separate as `demo-no-enrichment`.

## Prerequisites

`oc`, `curl`, `jq`, `python3`, `podman`, and access to an OpenShift cluster and Quay repository.

## Build and push

```bash
podman build --platform linux/amd64 \
  -t quay.io/summu85/customer-keycloak:consulting-enrichment-v1 \
  -f extensions/Containerfile extensions
podman push quay.io/summu85/customer-keycloak:consulting-enrichment-v1
```

## Clean installation

```bash
DELETE_EXISTING=true \
KEYCLOAK_IMAGE=quay.io/summu85/customer-keycloak:consulting-enrichment-v1 \
./scripts/install-demo.sh
```

After installation, synchronize LDAP users in the Admin Console and assign `employee_user` to `sp001` and `p001`. See `docs/EXTERNAL-TOKEN-ENRICHMENT.md` for enrichment behavior and validation.

## Verify

```bash
./scripts/verify-demo.sh
```

## Reset demo-generated data

```bash
./scripts/reset-demo.sh
```

## Production note

The mock SMS endpoint represents an enterprise OTP orchestration service. A production integration should use separate challenge-generation and challenge-verification APIs, avoid returning the plain OTP to Keycloak, and implement rate limits, expiry, retries, replay prevention, audit controls, and secure service authentication.

## Enrichment quick test

```bash
./scripts/test-enrichment.sh
oc logs deployment/mock-enrichment-api -n keycloak-demo --since=5m
```

After a fresh OIDC login and code exchange, decode the access token and inspect `external_enrichment`.
