#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"
require_cmd curl
require_cmd jq

USERID="${1:-9876543210}"
USERTYPE="${2:-customer}"
ROLES_JSON="${3:-[\"customer_user\",\"policy_viewer\",\"claim_submitter\"]}"

oc exec deployment/mock-enrichment-api -n "$NS" -- python3 - "$USERID" "$USERTYPE" "$ROLES_JSON" <<'PY'
import json, sys, urllib.request
userid, usertype, roles_json = sys.argv[1:]
body = json.dumps({"userid": userid, "userType": usertype, "roles": json.loads(roles_json)}).encode()
req = urllib.request.Request("http://127.0.0.1:8080/enrich", data=body, headers={"Content-Type":"application/json"}, method="POST")
print(urllib.request.urlopen(req).read().decode())
PY
