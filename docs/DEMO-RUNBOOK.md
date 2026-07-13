# Demo runbook

## Preparation

```bash
oc get pods -n keycloak-demo
./scripts/verify-demo.sh
```

Configure LDAP using `docs/LDAP-SETUP.md`, then configure the browser flow using `docs/EXACT-FLOW-CONFIGURATION.md`.

Set the authorization URL:

```bash
DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
KC_URL="https://customer-iam-keycloak-demo.${DOMAIN}"
echo "${KC_URL}/realms/customer-iam/protocol/openid-connect/auth?client_id=employee-app&response_type=code&scope=openid&redirect_uri=https%3A%2F%2Foauthdebugger.com%2Fdebug"
```

Use a private/incognito browser window between identities or log out from the realm session.

## Demo 1: LDAP employee

Login as `sp001` / `Password@123`.

Expected:
- password is validated by OpenLDAP;
- backend guard accepts the federated user;
- login succeeds.

Repeat with `p001` if desired.

## Demo 2: local Keycloak user

Login as `agent001` / `Password@123`.

Expected:
- mobile OTP step skips the user;
- Password Form validates Keycloak local credentials;
- backend guard accepts the local user.

## Demo 3: active customer, JIT provisioning and OTP

Before login, search Users for `9876543210`; it should not exist on a fresh deployment.

Watch the services:

```bash
oc logs -f deployment/mock-customer-registry -n keycloak-demo
```

In another terminal:

```bash
oc logs -f deployment/mock-sms-api -n keycloak-demo
```

Enter username `9876543210`.

Expected registry log:

```text
CUSTOMER LOOKUP -> mobile=9876543210 registered=True active=True
```

Expected SMS log:

```text
MOCK SMS -> mobile=9876543210 otp=123456
```

Enter the displayed OTP in the Keycloak OTP form. No password is used.

After login, the user exists in Keycloak with:
- `customer_id=CUST-100245`
- `user_type=customer`
- `mobile_number=9876543210`
- roles `customer_user`, `policy_viewer`, `claim_submitter`

## Demo 4: negative customer cases

- `9876500000`: registered but inactive; rejected before an OTP is sent.
- `9999999999`: unknown customer; rejected before an OTP is sent.
- Incorrect OTP: rejected; three attempts maximum.
- OTP older than 120 seconds: rejected as expired.

## Demo 5: role formats in the token

Obtain a fresh authorization code from OAuth Debugger and immediately exchange it:

```bash
CODE='<fresh-code>'
curl -sk -X POST \
  "$KC_URL/realms/customer-iam/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d grant_type=authorization_code \
  -d client_id=employee-app \
  -d client_secret=employee-app-demo-secret \
  -d "code=$CODE" \
  -d redirect_uri=https://oauthdebugger.com/debug | tee /tmp/tokens.json | jq
```

Decode the access token:

```bash
export ACCESS_TOKEN=$(jq -r .access_token /tmp/tokens.json)
python3 - <<'PY'
import os, json, base64
p=os.environ['ACCESS_TOKEN'].split('.')[1]
p += '=' * (-len(p) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=2))
PY
```

Show:
- `realm_access.roles`
- `roles_array`
- `roles_csv`

## Customer explanation

The demo proves standard federation, local authentication, conditional backend enforcement, JIT customer onboarding and passwordless mobile OTP. External API-based token enrichment is technically possible through a custom protocol mapper but is intentionally excluded from this customer-facing branch and should be designed and delivered as a services engagement.
