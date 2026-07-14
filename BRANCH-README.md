# Consulting Enrichment Variant

This branch contains the full validated authentication demo plus a synchronous external token-enrichment protocol mapper.

The mapper sends this JSON payload during access-token creation:

```json
{
  "userid": "9876543210",
  "userType": "customer",
  "roles": ["customer_user", "policy_viewer", "claim_submitter"]
}
```

The mock enrichment API echoes those values and adds:

```json
{
  "customKey": "customValue",
  "enrichmentApplied": true
}
```

The complete response appears in the access token under `external_enrichment`.

Recommended Git branch: `consulting-enrichment`.

Build and install:

```bash
podman build --platform linux/amd64 \
  -t quay.io/summu85/customer-keycloak:consulting-enrichment-v1 \
  -f extensions/Containerfile extensions
podman push quay.io/summu85/customer-keycloak:consulting-enrichment-v1

DELETE_EXISTING=true \
KEYCLOAK_IMAGE=quay.io/summu85/customer-keycloak:consulting-enrichment-v1 \
GIT_REF=consulting-enrichment \
./scripts/install-demo.sh
```
