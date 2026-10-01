# Key-pair auth (needed when MFA is enforced)

```bash
mkdir -p ~/.snowflake && cd ~/.snowflake
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt   # PKCS#8 private key
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
chmod 600 rsa_key.p8
```

In Snowsight (strip the BEGIN/END lines and newlines from rsa_key.pub):

```sql
ALTER USER <your_user> SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqh...';
DESC USER <your_user>;   -- RSA_PUBLIC_KEY_FP should now be populated
```

If you already set up a key for the Aether Trade deploy workflow you can reuse the same `rsa_key.p8`.
