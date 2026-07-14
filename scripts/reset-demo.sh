#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"
refresh_token
for username in 9876543210 9876500000 9999999999 sp-local migrated001; do
  id=$(api GET "users?username=$username&exact=true" | jq -r '.[0].id // empty')
  [[ -z "$id" ]] || { api DELETE "users/$id" >/dev/null; echo "Deleted $username"; }
done
api DELETE 'events' >/dev/null || true
echo 'Demo state reset. Core users and configuration retained.'

echo "Mock enrichment API has no persistent state; no enrichment reset is required."
