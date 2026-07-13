# Customer-facing RHBK / Keycloak demo on OpenShift

This branch is the customer-facing demonstration variant. It intentionally excludes external API-based token enrichment while retaining all other requested authentication and token-format use cases.

## Demonstrated capabilities

| Use case | Implementation |
|---|---|
| LDAP authentication | OpenLDAP simulator for `sp*` and `p*` employee users |
| Normal Keycloak login | Local users such as `agent001` and `banca001` |
| Passwordless customer OTP | JIT customer validation, local user provisioning, mock SMS OTP generation and verification |
| Backend enforcement by username | Custom backend guard for LDAP, mobile customer and local users |
| Multiple roles in token | `roles_array` through a built-in role mapper and `roles_csv` through a custom mapper |

## Deliberately excluded from this branch

External token enrichment through a third-party API is not deployed or configured here. The capability can be positioned as technically feasible through a custom Keycloak protocol mapper, but it requires solution design, security review, resilience policy, testing and lifecycle ownership. Use the separate `consulting-enrichment` branch as an engineering accelerator if that work is commissioned.

## Mobile customer flow

```text
10-digit mobile number
  -> authoritative customer-registry lookup
  -> reject unknown/inactive customer
  -> create or refresh local Keycloak user just in time
  -> request OTP from mock SMS API
  -> validate OTP
  -> issue token
```

## Repository layout

- `00`–`07`, `09`–`11` YAML: OpenShift infrastructure and mock services
- `extensions/`: custom authenticators and comma-separated role mapper
- `scripts/`: staged deployment helpers
- `docs/`: LDAP, JIT provisioning, OTP and authentication-flow instructions
- `BRANCH-README.md`: branch-specific positioning

## Deploy this branch

```bash
GIT_REF=demo-no-enrichment ./scripts/deploy.sh
oc start-build customer-keycloak -n keycloak-demo --follow
./scripts/deploy-keycloak.sh
```

Then configure LDAP and the browser authentication flow using the files under `docs/`.

## Test identities

| Username | Source | Credential | Expected result |
|---|---|---|---|
| `sp001` | LDAP | `Password@123` | Employee LDAP authentication |
| `p001` | LDAP | `Password@123` | Employee LDAP authentication |
| `9876543210` | JIT customer | OTP only | Active customer is provisioned and authenticated |
| `9876500000` | Registry only | None | Registered but inactive; rejected |
| `9999999999` | Unknown | None | Unknown customer; rejected |
| `agent001` | Keycloak DB | `Password@123` | Local login |
| `banca001` | Keycloak DB | `Password@123` | Local login |

## Expected custom role claims

```json
{
  "roles_array": ["claim_submitter", "customer_user", "policy_viewer"],
  "roles_csv": "claim_submitter,customer_user,policy_viewer"
}
```

Keycloak's conventional `realm_access.roles` claim remains available unless client-scope configuration removes it.

## OpenLDAP note

The demo LDAP image requires a dedicated `openldap-sa` service account with the OpenShift `anyuid` SCC. The manifest copies bootstrap LDIF files from a read-only ConfigMap into a writable `emptyDir` through an init container.

```bash
oc adm policy add-scc-to-user anyuid -z openldap-sa -n keycloak-demo
```

This is only for the temporary simulator and is not a production LDAP design.

## Demo-only warning

The repository contains demonstration passwords, a mock SMS API that exposes OTP values in logs, non-TLS LDAP, and a single-instance demo database. Do not use these settings in production.
