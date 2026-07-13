# Passwordless mobile-number OTP demo

## Intended behavior

- A customer enters an existing 10-digit mobile number as the username.
- No Keycloak password is requested.
- `Mobile Number Passwordless OTP` calls `http://mock-sms-api:8080/send`.
- The mock service creates a random six-digit OTP, prints it in its pod log, and returns it to Keycloak.
- Keycloak stores only a SHA-256 hash in the short-lived authentication session.
- The customer enters the code in the Keycloak OTP form.
- Non-mobile users continue to the normal Password Form.

This mock service returns the OTP to Keycloak because there is no real SMS gateway. A production SMS API should accept a generated challenge or return only an opaque transaction ID; it must never expose the OTP in logs or API responses.

## Build and deploy

After checking the changed extension code into Git:

```bash
oc apply -f 10-mock-sms-api.yaml
oc rollout status deployment/mock-sms-api -n keycloak-demo
oc start-build customer-keycloak -n keycloak-demo --follow
oc rollout restart statefulset/customer-iam -n keycloak-demo 2>/dev/null || true
```

If the Operator manages Keycloak using a Deployment rather than a StatefulSet, update the Keycloak CR image tag or delete the Keycloak pods so that the rebuilt image is pulled.

## Browser flow

Duplicate the built-in `browser` flow as `demo-browser-passwordless-otp`.

Inside the copied `Forms` subflow:

1. Delete or disable `Username Password Form`.
2. Add `JIT Customer Username Form` as `REQUIRED`.
3. Add a subflow named `Authentication Method` as `REQUIRED`.
4. Under `Authentication Method`, add `Mobile Number Passwordless OTP` as `ALTERNATIVE`.
5. Configure it with:
   - SMS API URL: `http://mock-sms-api:8080/send`
   - OTP validity: `120`
   - Maximum attempts: `3`
6. Under the same subflow, add `Password Form` as `ALTERNATIVE`.
7. After `Authentication Method`, add `Username Pattern / Backend Guard` as `REQUIRED`.
8. Disable the original conditional OTP/TOTP subflow for this demo.
9. Bind `demo-browser-passwordless-otp` as the realm Browser Flow.

Conceptual layout:

```text
Forms (REQUIRED)
├── JIT Customer Username Form (REQUIRED)
├── Authentication Method (REQUIRED)
│   ├── Mobile Number Passwordless OTP (ALTERNATIVE)
│   └── Password Form (ALTERNATIVE)
└── Username Pattern / Backend Guard (REQUIRED)
```

The two mechanisms are alternatives: mobile users are successfully authenticated by OTP, while non-mobile users are skipped by the OTP authenticator and handled by Password Form.

## Demonstration

Watch the mock SMS log:

```bash
oc logs -f deployment/mock-sms-api -n keycloak-demo
```

Open the OIDC authorization URL and enter:

```text
9876543210
```

The log displays something similar to:

```text
MOCK SMS -> mobile=9876543210 otp=284913
```

Enter `284913` in the Keycloak OTP screen. Authentication succeeds without a password.

Validate the negative paths:

- Wrong OTP: rejected, with at most three attempts.
- OTP after 120 seconds: rejected as expired.
- `agent001`: Password Form is shown.
- `sp001`/`p001`: Password Form is shown and LDAP validates the password.

## Just-in-time user requirement

The mobile user is not pre-created. `JIT Customer Username Form` validates the number against `mock-customer-registry` and creates or refreshes the Keycloak user only when the registry returns `registered=true` and `active=true`. See `JIT-CUSTOMER-PROVISIONING.md`.
