# Implementation and demo procedure

## Why the custom steps appear in Add step

The extension contains implementations of `Authenticator` and `AuthenticatorFactory`, and registers every factory in:

`META-INF/services/org.keycloak.authentication.AuthenticatorFactory`

After the JAR is copied to `/opt/keycloak/providers` and `kc.sh build` is run, the following exact display names are available as flow executions:

- `JIT Customer Username Form`
- `Mobile Number Passwordless OTP`
- `Username Pattern / Backend Guard`

The included `scripts/configure-auth-flow.sh` uses their provider IDs and creates the complete flow through the Admin REST API, so manual UI construction is optional.

## 1. Build and push the custom image

```bash
podman login registry.redhat.io
podman login quay.io

podman build --platform linux/amd64 \
  -t quay.io/summu85/customer-keycloak:demo-final \
  -f extensions/Containerfile extensions

podman push quay.io/summu85/customer-keycloak:demo-final
```

## 2. Deploy prerequisites

```bash
chmod +x scripts/*.sh
./scripts/deploy.sh
oc get pods -n keycloak-demo
```

Wait for PostgreSQL, OpenLDAP, the RHBK Operator, mock SMS API, and mock customer registry to be Running.

## 3. Deploy Keycloak and the realm

```bash
KEYCLOAK_IMAGE=quay.io/summu85/customer-keycloak:demo-final \
  ./scripts/deploy-keycloak.sh
```

Verify providers:

```bash
./scripts/verify-demo.sh
```

## 4. Configure LDAP

In realm `customer-iam`, open **User federation -> Add LDAP provider** and use:

- Connection URL: `ldap://openldap:389`
- Bind DN: `cn=admin,dc=demo,dc=local`
- Bind credential: `adminpass`
- Users DN: `ou=people,dc=demo,dc=local`
- Username LDAP attribute: `uid`
- RDN LDAP attribute: `uid`
- UUID LDAP attribute: `entryUUID`
- User object classes: `inetOrgPerson, organizationalPerson`
- Edit mode: `READ_ONLY`
- Import users: enabled

Test connection, test authentication, and synchronize all users. Assign `employee_user` to `sp001` and `p001`.

## 5. Create and bind the custom flow

```bash
./scripts/configure-auth-flow.sh
```

The flow is created as:

```text
Cookie                                           ALTERNATIVE
demo-browser-forms                               ALTERNATIVE
  JIT Customer Username Form                     REQUIRED
  demo-authentication-method                     REQUIRED
    Mobile Number Passwordless OTP               ALTERNATIVE
    Password Form                                ALTERNATIVE
  Username Pattern / Backend Guard               REQUIRED
```

You can verify it in **Authentication -> Flows -> demo-browser-passwordless-otp**.

## 6. Demo URL

```bash
DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
KC_URL="https://customer-iam-keycloak-demo.${DOMAIN}"
echo "${KC_URL}/realms/customer-iam/protocol/openid-connect/auth?client_id=employee-app&response_type=code&scope=openid&redirect_uri=https%3A%2F%2Foauthdebugger.com%2Fdebug"
```

## 7. Demonstration scenarios

### LDAP employee

Log in with `sp001 / Password@123` or `p001 / Password@123`.

Expected: JIT username step resolves the federated user, mobile OTP skips, Password Form validates against LDAP, and the backend guard verifies that the employee is federated.

### Local Keycloak user

Log in with `agent001 / Password@123`.

Expected: mobile OTP skips and Password Form validates against Keycloak's local database.

### Active mobile customer, created just in time

Before login, confirm `9876543210` does not exist. Watch:

```bash
oc logs -f deployment/mock-customer-registry -n keycloak-demo
oc logs -f deployment/mock-sms-api -n keycloak-demo
```

Enter `9876543210`. The registry validates the customer and Keycloak creates the local user. Read the generated OTP from the mock SMS log and enter it into the dedicated OTP form. No password is used.

After login, verify attributes `customer_id`, `user_type`, `mobile_number`, and `registry_status`, plus roles `customer_user`, `policy_viewer`, and `claim_submitter`.

### Inactive customer

Enter `9876500000`. Expected: rejected before an OTP is generated.

### Unknown customer

Enter `9999999999`. Expected: rejected before an OTP is generated.

### Backend enforcement

Create a local Keycloak user beginning with `sp`, such as `sp-local`, and attempt password login. Expected: the backend guard rejects it because `sp*` must come from LDAP.

### Role formats

After obtaining and exchanging an authorization code, decode the access token. Show standard role arrays and the custom `roles_csv` claim.

## 8. Troubleshooting

```bash
oc exec customer-iam-0 -n keycloak-demo -- ls -l /opt/keycloak/providers
oc logs customer-iam-0 -n keycloak-demo | grep -Ei 'jit-customer|mobile-passwordless|username-pattern'
./scripts/verify-demo.sh
```

If the provider JAR and service file are present, the authenticators are eligible flow executions. Rebuild under a new immutable image tag and update the Keycloak CR if the Admin Console is showing an older cached image.
