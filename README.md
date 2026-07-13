# Consulting accelerator: RHBK / Keycloak demo with external token enrichment

This branch contains the complete customer demo plus an external API token-enrichment protocol mapper. Treat it as a consulting accelerator or technical feasibility reference rather than the default customer-facing demonstration.

## Feasibility

| Use case | Verdict | Implementation |
|---|---|---|
| LDAP, local login and passwordless mobile OTP | Feasible with extension | LDAP federation, local Keycloak users, JIT customer validation, and custom SMS-style OTP authenticator |
| Select authentication backend from username pattern | Feasible with extension | Native user lookup/password validation plus a custom authentication-flow guard that rejects a user resolved from the wrong storage provider |
| Call an API after authentication and add response values to access token | Feasible with extension | Custom OIDC protocol mapper; invoked during token creation for employee usernames |
| Roles as JSON array and CSV string | Feasible | Built-in realm-role mapper for `roles_array`; custom mapper for `roles_csv` |

## Important interpretation

The mobile case is implemented as **passwordless SMS-style OTP**. A 10-digit mobile number is first validated against a mock customer registry. Only registered and active customers are provisioned just in time, after which a custom authenticator sends and validates a one-time code through a mock SMS API.

## Repository layout

- `00`–`11` YAML: OpenShift infrastructure, mock APIs, and realm resources
- `extensions/`: custom authenticator and protocol mappers
- `mock-api/` / `08-token-enrichment-api.yaml`: employee enrichment API simulation
- `scripts/`: staged deployment helpers
- `docs/`: console configuration steps

## Deploy

1. Replace the demonstration DB password in `04-keycloak-db-secret.yaml`.
2. Check this repository into GitHub, because the BuildConfig builds `extensions/` from Git.
3. Run:

```bash
./scripts/deploy.sh
oc start-build customer-keycloak -n keycloak-demo --follow
./scripts/deploy-keycloak.sh
```

4. Configure LDAP using `docs/LDAP-SETUP.md`.
5. Configure and bind the browser flow using `docs/AUTHENTICATION-FLOW.md`.

## Test accounts

| Username | Storage | Password | Expected flow |
|---|---|---|---|
| `sp001` | LDAP | `Password@123` | LDAP password; employee enrichment |
| `p001` | LDAP | `Password@123` | LDAP password; employee enrichment |
| `9876543210` | JIT-provisioned Keycloak user | None | Registry validation followed by passwordless OTP |
| `agent001` | Keycloak DB | `Password@123` | Normal local login |
| `banca001` | Keycloak DB | `Password@123` | Normal local login |

## Test authorization code flow

Open:

```text
https://<keycloak-host>/realms/customer-iam/protocol/openid-connect/auth?client_id=employee-app&response_type=code&scope=openid&redirect_uri=https%3A%2F%2Foauthdebugger.com%2Fdebug
```

Immediately exchange the returned one-time code:

```bash
curl -sk -X POST "https://<keycloak-host>/realms/customer-iam/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d grant_type=authorization_code \
  -d client_id=employee-app \
  -d client_secret=employee-app-demo-secret \
  -d code='<fresh-code>' \
  -d redirect_uri=https://oauthdebugger.com/debug | jq
```

For `sp001`, the access token should contain values similar to:

```json
{
  "roles_array": ["employee_user"],
  "roles_csv": "employee_user",
  "user_id": "EMP-SP001",
  "user_type": "employee",
  "enriched_roles": ["employee_user", "employee_portal_access"]
}
```

## Design details

### Backend selection

Keycloak first resolves the user and validates the password using the provider that owns the user. LDAP passwords remain in LDAP. The custom `Username Pattern / Backend Guard`, placed immediately after the username/password execution, verifies:

- `sp*` or `p*`: the resolved user must have a federation link (LDAP), and derives `employee`.
- exactly 10 digits: the user must be validated by the customer registry and is then created/refreshed locally as `customer`.
- all others: the user must be local, and derives `internal`.

This is enforcement/validation rather than dynamically replacing Keycloak’s user-storage lookup algorithm.

### Token enrichment

`ExternalEnrichmentProtocolMapper` runs while the access token is being built. For employees it calls:

```text
http://token-enrichment-api:8080/enrich?username=<username>
```

The demo mapper has a 2-second connection timeout and 3-second request timeout. `fail.closed=true` prevents token issuance when enrichment fails. Production implementations should use TLS, service authentication, strict response validation, connection pooling, bounded retries/circuit breaking, and explicit availability behavior.

### Custom roles

- `roles_array` uses the built-in realm-role protocol mapper.
- `roles_csv` uses `CommaSeparatedRolesProtocolMapper`.
- Keycloak’s normal `realm_access.roles` claim remains available unless removed by client-scope configuration.

## Changes from the original repository

- The literal `<cluster-domain>` hostname was replaced by a rendered CR template.
- PostgreSQL now uses a PVC and reads credentials from the Secret.
- A custom Keycloak image BuildConfig and ImageStream were added.
- Realm roles, JIT mobile-customer provisioning, passwordless OTP, token mappers and enrichment APIs were added.
- LDAP simulator and two employee users were added.
- Deployment is staged so the Operator CRD, custom image, Keycloak instance and realm import are created in a safe order.

## Demo-only warnings

The sample contains plaintext demonstration secrets and uses non-TLS LDAP. Do not use those settings in production. Use External Secrets/Sealed Secrets or a vault, LDAPS, a supported HA database, network policies, admin MFA, external audit/SIEM integration, and pinned/signed images.

## OpenLDAP on OpenShift

The demo OpenLDAP image performs ownership changes during startup. OpenShift also mounts ConfigMaps read-only. Therefore, `09-openldap.yaml` uses this pattern:

```text
ConfigMap (read-only) -> init container -> writable emptyDir -> OpenLDAP bootstrap directory
```

The Deployment uses the dedicated service account `openldap-sa`. For this demo image, a cluster administrator must grant it the `anyuid` SCC:

```bash
oc adm policy add-scc-to-user anyuid \
  -z openldap-sa \
  -n keycloak-demo
```

`scripts/deploy.sh` performs this automatically when the logged-in user has permission. If not, it prints the exact command for a cluster administrator.

Verify OpenLDAP after deployment:

```bash
oc rollout status deployment/openldap -n keycloak-demo --timeout=180s
oc logs deployment/openldap -n keycloak-demo

oc exec deployment/openldap -n keycloak-demo -- \
  ldapsearch -x \
  -H ldap://localhost:389 \
  -D 'cn=admin,dc=demo,dc=local' \
  -w adminpass \
  -b 'ou=people,dc=demo,dc=local' \
  '(objectClass=inetOrgPerson)' uid cn mail
```

The `anyuid` SCC is for the temporary LDAP simulator only. Do not use this LDAP deployment as a production design.

## Passwordless mobile OTP clarification

The mobile customer flow no longer uses Keycloak TOTP or a local password. It uses the custom `Mobile Number Passwordless OTP` authenticator and the mock SMS API in `10-mock-sms-api.yaml`. See `docs/MOBILE-OTP-SETUP.md` for the flow configuration and demonstration steps.

## Just-in-time mobile customer provisioning

Mobile customers are no longer pre-created in the realm import. The custom
`JIT Customer Username Form` validates 10-digit usernames against
`mock-customer-registry`, creates only registered and active customers, refreshes
attributes/roles, and then passes the user to passwordless OTP authentication.

See `docs/JIT-CUSTOMER-PROVISIONING.md`.
