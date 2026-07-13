# Just-in-time customer provisioning

The demo does not pre-create mobile customer users in Keycloak.

## Customer registry test data

| Mobile | Registry state | Expected result |
|---|---|---|
| `9876543210` | Registered and active | User is created/refreshed, OTP is sent, login succeeds |
| `9876500000` | Registered but inactive | Login is rejected and no Keycloak user is created |
| `9999999999` | Unknown | Login is rejected and no Keycloak user is created |

## Required browser flow

Duplicate the Browser flow and configure the Forms subflow as follows:

```text
Forms
├── JIT Customer Username Form             REQUIRED
├── Authentication Method                  REQUIRED
│   ├── Mobile Number Passwordless OTP     ALTERNATIVE
│   └── Password Form                      ALTERNATIVE
└── Username Pattern / Backend Guard       REQUIRED
```

Configure **JIT Customer Username Form**:

```text
Customer registry base URL:
http://mock-customer-registry:8080/customers/by-mobile
```

Configure **Mobile Number Passwordless OTP**:

```text
SMS API URL: http://mock-sms-api:8080/send
OTP validity: 120 seconds
Maximum attempts: 3
```

Do not use Keycloak's standard Username Form in this flow. It rejects an unknown
mobile number before the JIT provider can validate and create the customer.

## Validation

Before first login:

```bash
oc logs -f deployment/mock-customer-registry -n keycloak-demo
oc logs -f deployment/mock-sms-api -n keycloak-demo
```

Confirm the user is absent:

```bash
# Run through Admin Console or Admin REST API; no 9876543210 user should exist.
```

Login with `9876543210`, read the OTP from the mock SMS log, and submit it.
After successful login, the Keycloak user has these attributes:

```text
customer_id=CUST-100245
user_type=customer
mobile_number=9876543210
registry_status=ACTIVE
```

and these realm roles:

```text
customer_user
policy_viewer
claim_submitter
```

The registry is checked on every login and the attributes/returned roles are
refreshed. This demo grants returned roles but does not remove stale roles; a
production implementation should use a clearly owned role namespace and perform
full reconciliation.
