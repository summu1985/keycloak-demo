# Consulting Variant (Includes External Token Enrichment)

This branch contains everything in the customer demo plus:

- `ExternalEnrichmentProtocolMapper`
- Mock `token-enrichment-api`
- `employee-enrichment` mapper configuration in the realm import

Use this as a consulting accelerator or feasibility reference, not as the customer-facing demo branch. Production adoption requires API authentication, TLS, timeout/retry/circuit-breaker policy, high availability, privacy review, error semantics, observability, performance testing, and an agreed fail-open/fail-closed policy.

Deploy from this branch:

```bash
GIT_REF=consulting-enrichment ./scripts/deploy.sh
oc start-build customer-keycloak -n keycloak-demo --follow
./scripts/deploy-keycloak.sh
```
