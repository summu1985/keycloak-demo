#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"
for c in oc curl jq; do require_cmd "$c"; done
refresh_token
REALM_ID=$(api GET '' | jq -r '.id')
EXISTING=$(api GET 'components?type=org.keycloak.storage.UserStorageProvider' | jq -r '.[]|select(.name=="demo-openldap")|.id' | head -1)
if [[ -z "$EXISTING" ]]; then
  api POST 'components' "$(jq -nc --arg parent "$REALM_ID" '{name:"demo-openldap",providerId:"ldap",providerType:"org.keycloak.storage.UserStorageProvider",parentId:$parent,config:{enabled:["true"],priority:["0"],fullSyncPeriod:["-1"],changedSyncPeriod:["-1"],cachePolicy:["DEFAULT"],batchSizeForSync:["1000"],editMode:["READ_ONLY"],importEnabled:["true"],syncRegistrations:["false"],vendor:["other"],usernameLDAPAttribute:["uid"],rdnLDAPAttribute:["uid"],uuidLDAPAttribute:["entryUUID"],userObjectClasses:["inetOrgPerson, organizationalPerson"],connectionUrl:["ldap://openldap:389"],usersDn:["ou=people,dc=demo,dc=local"],authType:["simple"],bindDn:["cn=admin,dc=demo,dc=local"],bindCredential:["adminpass"],searchScope:["1"],useTruststoreSpi:["ldapsOnly"],connectionPooling:["true"],pagination:["true"],allowKerberosAuthentication:["false"],debug:["false"]}}')" >/dev/null
  echo "Created LDAP federation provider demo-openldap"
else
  echo "LDAP federation provider already exists: $EXISTING"
fi
