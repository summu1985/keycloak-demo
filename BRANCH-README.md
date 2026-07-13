# Customer Demo Variant (No External Token Enrichment)

This branch demonstrates:

- LDAP federation for `sp*` and `p*` employees
- Local Keycloak database login for ordinary internal users
- Just-in-time customer validation and provisioning for registered 10-digit mobile numbers
- Passwordless OTP through a mock SMS API
- Username/backend enforcement
- Realm roles in a JSON array and comma-separated string claim

It intentionally excludes the external API token-enrichment protocol mapper and its mock API. Position external token enrichment as technically feasible through a custom Keycloak provider, requiring detailed design, security review, performance testing, lifecycle ownership, and services engagement.

Deploy from this branch:

```bash
GIT_REF=demo-no-enrichment ./scripts/deploy.sh
oc start-build customer-keycloak -n keycloak-demo --follow
./scripts/deploy-keycloak.sh
```
