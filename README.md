# RHBK customer authentication demo on OpenShift

This package implements one coherent browser flow for:

- LDAP employees (`sp*`, `p*`)
- local Keycloak users
- registered customers using 10-digit mobile numbers and passwordless OTP
- JIT creation of eligible customer users
- backend-source enforcement
- realm roles in JSON-array and comma-separated token claims

External API token enrichment is intentionally excluded from this customer-facing package.

## Custom providers

- `JIT Customer Username Form`: username-first resolution and customer-registry validation/JIT provisioning
- `Mobile Number Passwordless OTP`: mock SMS OTP generation and verification
- `Username Pattern / Backend Guard`: LDAP/local source enforcement and user-type derivation
- `Comma-separated realm roles`: adds `roles_csv`

## Build locally

```bash
git switch demo-no-enrichment
podman login registry.redhat.io
podman build --platform linux/amd64 \
  -t quay.io/summu85/customer-keycloak:demo-no-enrichment-v3 \
  -f extensions/Containerfile extensions
podman login quay.io
podman push quay.io/summu85/customer-keycloak:demo-no-enrichment-v3
```

## Deploy

```bash
./scripts/deploy.sh
KEYCLOAK_IMAGE=quay.io/summu85/customer-keycloak:demo-no-enrichment-v3 \
  ./scripts/deploy-keycloak.sh
./scripts/verify-demo.sh
```

Then complete:

1. `docs/LDAP-SETUP.md`
2. `docs/EXACT-FLOW-CONFIGURATION.md`
3. `docs/DEMO-RUNBOOK.md`

## Demo identities

| Identity | Source | Credential |
|---|---|---|
| `sp001` | LDAP | `Password@123` |
| `p001` | LDAP | `Password@123` |
| `agent001` | Keycloak DB | `Password@123` |
| `banca001` | Keycloak DB | `Password@123` |
| `9876543210` | Customer registry + JIT | OTP only |
| `9876500000` | Inactive registry record | rejected |
| `9999999999` | Unknown | rejected |

## Demo-only warning

The mock SMS API exposes OTP values in logs, LDAP uses plain LDAP, and sample secrets/passwords are committed for repeatability. These resources are not production-ready.

## Definitive authentication-flow setup

Use `scripts/configure-auth-flow.sh` to create and bind the complete flow through the Keycloak Admin REST API. See `docs/IMPLEMENTATION-AND-DEMO.md` for deployment and demonstration steps.
