#!/usr/bin/env bash
set -euo pipefail

TOKEN="${1:-${ACCESS_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  echo "Usage: $0 <access-token>" >&2
  echo "Or export ACCESS_TOKEN before running." >&2
  exit 1
fi

python3 - "$TOKEN" <<'PY'
import base64, json, sys
raw = sys.argv[1]
parts = raw.split('.')
if len(parts) < 2:
    raise SystemExit('Not a JWT')
payload = parts[1] + '=' * (-len(parts[1]) % 4)
data = json.loads(base64.urlsafe_b64decode(payload))
print(json.dumps({
    'preferred_username': data.get('preferred_username'),
    'roles_array': data.get('roles_array'),
    'roles_csv': data.get('roles_csv'),
    'external_enrichment': data.get('external_enrichment')
}, indent=2))
PY
