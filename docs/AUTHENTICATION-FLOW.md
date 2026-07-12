# Configure the demo browser authentication flow

This flow implements password validation against the user's actual storage provider, validates that the provider matches the username pattern, and requires TOTP for users carrying the `otp_required` role.

1. Sign in to the `customer-iam` realm Admin Console.
2. Open **Authentication > Flows**.
3. Duplicate the built-in **browser** flow and name it `demo-browser`.
4. In the copied flow, locate the forms subflow. Keep **Username Password Form** as `REQUIRED`.
5. Immediately after it, choose **Add step**, select **Username Pattern / Backend Guard**, and mark it `REQUIRED`.
6. Disable the copied default `Conditional 2FA` subflow to prevent OTP from being triggered merely because any user has configured OTP.
7. Add a new subflow named `OTP for mobile users`; set it to `CONDITIONAL`.
8. Inside that subflow add **Condition - User Role**, set it to `REQUIRED`, and configure role `otp_required`.
9. Add **OTP Form** after the condition and set it to `REQUIRED`.
10. Bind `demo-browser` as the realm browser flow.

Expected behavior:

- `sp001` and `p001`: LDAP password validation, backend guard accepts only a federated LDAP user, user type is employee.
- `9876543210`: local Keycloak password followed by Configure TOTP on first login and TOTP on later logins.
- `agent001`, `banca001`: local Keycloak password only.

The provided implementation interprets “soft OTP login” as password plus app-generated TOTP. OTP-only authentication is a separate custom credential/authenticator design and is not implemented here.
