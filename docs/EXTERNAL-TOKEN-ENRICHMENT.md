# External Token Enrichment

## Runtime sequence

1. User completes the validated authentication flow.
2. Keycloak starts access-token creation.
3. `ExternalEnrichmentProtocolMapper` derives:
   - `userid`: Keycloak username
   - `userType`: user-session note, user attribute, or username/backend fallback
   - `roles`: effective realm roles
4. The mapper POSTs those fields to `http://mock-enrichment-api:8080/enrich`.
5. The mock API echoes the fields and adds `customKey=customValue` and `enrichmentApplied=true`.
6. The mapper adds the complete response to `external_enrichment` in the access token.

## Expected token claim

```json
"external_enrichment": {
  "userid": "9876543210",
  "userType": "customer",
  "roles": ["claim_submitter", "customer_user", "policy_viewer"],
  "customKey": "customValue",
  "enrichmentApplied": true
}
```

## Failure behaviour

The mapper is configurable:

- `enrichment.api.url`
- `enrichment.timeout.ms`
- `enrichment.fail.on.error`
- `claim.name`

The demo defaults to fail-open. If the API is unavailable, the token contains:

```json
"external_enrichment": {
  "enrichmentApplied": false,
  "error": "enrichment_service_unavailable"
}
```

Set `enrichment.fail.on.error=true` to fail token creation instead.

## Production considerations

Use mTLS or workload identity, strict timeouts, bounded retries, caching where appropriate, capacity testing, circuit breaking, data minimization, audit controls and an explicit fail-open/fail-closed decision.

## Demo validation

Watch the API:

```bash
oc logs -f deployment/mock-enrichment-api -n keycloak-demo
```

After exchanging a fresh authorization code:

```bash
export ACCESS_TOKEN=$(jq -r '.access_token' /tmp/tokens.json)
./scripts/decode-enrichment-token.sh
```

Expected output includes:

```json
{
  "external_enrichment": {
    "userid": "9876543210",
    "userType": "customer",
    "roles": ["claim_submitter", "customer_user", "policy_viewer"],
    "customKey": "customValue",
    "enrichmentApplied": true
  }
}
```
