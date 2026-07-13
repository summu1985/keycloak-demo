# Exact browser-flow configuration

The custom providers are **steps** in a Keycloak authentication flow. They are not automatically inserted after the JAR is installed.

## Target structure

```text
demo-browser-passwordless-otp
├── Cookie                                      ALTERNATIVE
├── Kerberos                                    DISABLED
├── Identity Provider Redirector                ALTERNATIVE
└── Forms                                       ALTERNATIVE
    ├── JIT Customer Username Form              REQUIRED
    ├── Authentication Method                   REQUIRED (subflow)
    │   ├── Mobile Number Passwordless OTP      ALTERNATIVE
    │   └── Password Form                       ALTERNATIVE
    └── Username Pattern / Backend Guard        REQUIRED
```

Disable the copied `Username Password Form` and the copied `Conditional 2FA` subflow.

## Console steps

1. Select realm **customer-iam**.
2. Open **Authentication > Flows**.
3. On the built-in **browser** flow, choose **Duplicate**.
4. Name it `demo-browser-passwordless-otp`.
5. Expand/open the copied **Forms** subflow.
6. Disable `Username Password Form`.
7. Disable `Conditional 2FA`.
8. Click **Add step** inside Forms.
9. Search for `JIT Customer Username Form`; add it and set **Required**.
10. Open its gear/configuration and set:
    - Alias: `jit-customer-registry`
    - Customer registry base URL: `http://mock-customer-registry:8080/customers/by-mobile`
11. Inside Forms, click **Add sub-flow**.
12. Name it `Authentication Method`, choose generic/basic flow, and set the subflow **Required**.
13. Inside `Authentication Method`, click **Add step**.
14. Add `Mobile Number Passwordless OTP` and set **Alternative**.
15. Configure it:
    - Alias: `mobile-otp`
    - Mock/real SMS API URL: `http://mock-sms-api:8080/send`
    - OTP validity in seconds: `120`
    - Maximum OTP attempts: `3`
16. Inside the same subflow, click **Add step**.
17. Add built-in `Password Form` and set **Alternative**.
18. Return to Forms and add `Username Pattern / Backend Guard` after the Authentication Method subflow. Set **Required**.
19. Use the up/down controls so the order is exactly:
    1. JIT Customer Username Form
    2. Authentication Method
    3. Username Pattern / Backend Guard
20. Open **Authentication > Bindings**.
21. Set **Browser flow** to `demo-browser-passwordless-otp` and save.

## Why this order works

- The JIT form obtains the username first.
- For a 10-digit mobile number, it checks the customer registry and creates/refreshes an eligible Keycloak user.
- The Authentication Method subflow then chooses exactly one route:
  - mobile number: custom OTP step challenges; Password Form is skipped after the alternative succeeds;
  - LDAP/local user: OTP step returns `attempted`; Password Form validates the credential.
- The final guard confirms `sp*` and `p*` resolved from LDAP and other non-mobile users resolved locally.

## Exact provider names

- `JIT Customer Username Form`
- `Mobile Number Passwordless OTP`
- `Username Pattern / Backend Guard`

They appear only under **Add step** within a flow.
