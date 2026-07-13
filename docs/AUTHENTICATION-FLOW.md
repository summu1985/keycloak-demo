# Configure the demo browser authentication flow

This flow supports LDAP employees, local Keycloak users, and registered mobile customers who are provisioned just in time and authenticate without a password.

1. Sign in to the `customer-iam` realm Admin Console.
2. Open **Authentication > Flows**.
3. Duplicate the built-in **browser** flow and name it `demo-browser-passwordless-otp`.
4. In the copied Forms subflow, disable or delete **Username Password Form**.
5. Add **JIT Customer Username Form** as `REQUIRED`. Configure the registry URL as `http://mock-customer-registry:8080/customers/by-mobile`.
6. Add a subflow named **Authentication Method** and set it to `REQUIRED`.
7. Inside it, add **Mobile Number Passwordless OTP** as `ALTERNATIVE`. Configure `http://mock-sms-api:8080/send`, TTL `120`, and attempts `3`.
8. Add **Password Form** in the same subflow as `ALTERNATIVE`.
9. After the subflow, add **Username Pattern / Backend Guard** as `REQUIRED`.
10. Disable the copied Conditional OTP/TOTP subflow.
11. Bind `demo-browser-passwordless-otp` as the realm browser flow.

Expected behavior:

- `sp001` and `p001`: resolved from LDAP and authenticated by password.
- `9876543210`: validated as active by the registry, created/refreshed in Keycloak, then authenticated using a mock SMS OTP without a password.
- `9876500000`: rejected because the registry marks it inactive.
- `9999999999`: rejected because it is unknown.
- `agent001` and `banca001`: authenticated from Keycloak's local database by password.

See `JIT-CUSTOMER-PROVISIONING.md` and `MOBILE-OTP-SETUP.md` for the full demonstration steps.
