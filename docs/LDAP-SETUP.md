# Configure LDAP federation

In realm `customer-iam`, open **User federation > Add LDAP provider** and enter:

- UI display name: `demo-ldap`
- Vendor: `Other`
- Connection URL: `ldap://openldap:389`
- Bind type: `simple`
- Bind DN: `cn=admin,dc=demo,dc=local`
- Bind credential: `adminpass`
- Users DN: `ou=people,dc=demo,dc=local`
- Username LDAP attribute: `uid`
- RDN LDAP attribute: `uid`
- UUID LDAP attribute: `entryUUID`
- User object classes: `inetOrgPerson, organizationalPerson`
- Edit mode: `READ_ONLY`
- Import users: `ON`
- Sync registrations: `OFF`
- Search scope: `One Level`

Use **Test connection**, **Test authentication**, then **Synchronize all users**.

Demo LDAP accounts:

- `sp001 / Password@123`
- `p001 / Password@123`

## OpenShift deployment prerequisite

The OpenLDAP simulator uses the `osixia/openldap` image, which changes file ownership at startup. Grant the dedicated service account the `anyuid` SCC:

```bash
oc adm policy add-scc-to-user anyuid \
  -z openldap-sa \
  -n keycloak-demo

oc rollout restart deployment/openldap -n keycloak-demo
oc rollout status deployment/openldap -n keycloak-demo --timeout=180s
```

The LDIF ConfigMap is not mounted directly into OpenLDAP. An init container copies it into a writable `emptyDir`; this prevents the `Read-only file system` failure caused by attempts to `chown` ConfigMap files.

Verify the live volume layout:

```bash
oc get deployment openldap -n keycloak-demo \
  -o jsonpath='{range .spec.template.spec.initContainers[*]}INIT: {.name}{"\\n"}{range .volumeMounts[*]}  {.name} -> {.mountPath}{"\\n"}{end}{end}{range .spec.template.spec.containers[*]}CONTAINER: {.name}{"\\n"}{range .volumeMounts[*]}  {.name} -> {.mountPath}{"\\n"}{end}{end}'
```

Expected:

```text
INIT: copy-bootstrap-ldif
  bootstrap-config -> /config
  bootstrap-writable -> /bootstrap
CONTAINER: openldap
  bootstrap-writable -> /container/service/slapd/assets/config/bootstrap/ldif/custom
```
