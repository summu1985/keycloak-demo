#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

require_cmd oc
require_cmd python3

USERID="${1:-9876543210}"
USERTYPE="${2:-customer}"
ROLES_JSON="${3:-[\"customer_user\",\"policy_viewer\",\"claim_submitter\"]}"

echo "Testing mock enrichment API"
echo "Namespace: $NS"
echo "User ID:   $USERID"
echo "User type: $USERTYPE"
echo "Roles:     $ROLES_JSON"
echo

oc exec -i deployment/mock-enrichment-api \
  -n "$NS" \
  -- python3 - "$USERID" "$USERTYPE" "$ROLES_JSON" <<'PY'
import json
import sys
import urllib.error
import urllib.request

userid, usertype, roles_json = sys.argv[1:]

try:
    roles = json.loads(roles_json)
except json.JSONDecodeError as exc:
    print(f"Invalid roles JSON: {exc}", file=sys.stderr)
    sys.exit(1)

payload = {
    "userid": userid,
    "userType": usertype,
    "roles": roles
}

body = json.dumps(payload).encode("utf-8")

request = urllib.request.Request(
    "http://127.0.0.1:8080/enrich",
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST"
)

try:
    with urllib.request.urlopen(request, timeout=5) as response:
        response_body = response.read().decode("utf-8")
        print(json.dumps(json.loads(response_body), indent=2))
except urllib.error.HTTPError as exc:
    print(f"Enrichment API returned HTTP {exc.code}", file=sys.stderr)
    print(exc.read().decode("utf-8"), file=sys.stderr)
    sys.exit(1)
except Exception as exc:
    print(f"Unable to call enrichment API: {exc}", file=sys.stderr)
    sys.exit(1)
PY
