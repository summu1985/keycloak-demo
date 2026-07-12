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
