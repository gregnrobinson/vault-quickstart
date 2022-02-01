# Install

```bash
export VAULT_ADDR="https://vault.phronesis.cloud"


# GENERATE ROOT CERTIFICATE
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki

vault write -field=certificate pki/root/generate/internal \
     common_name="example.com" \
     ttl=87600h > CA_cert.crt

vault write pki/config/urls \
     issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
     crl_distribution_points="$VAULT_ADDR/v1/pki/crl"

# GENERATE INTERMEDIATE CA
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int

vault write -format=json pki_int/intermediate/generate/internal \
     common_name="example.com Intermediate Authority" \
     | jq -r '.data.csr' > pki_intermediate.csr

vault write -format=json pki/root/sign-intermediate csr=@pki_intermediate.csr \
     format=pem_bundle ttl="43800h" \
     | jq -r '.data.certificate' > intermediate.cert.pem

vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem

vault write pki_int/roles/mtls-default \
     allowed_domains="arcticlabs.dev" \
     allow_subdomains=true \
     max_ttl="720h"

# USE THIS ONE LINER TO GET CERTIFICATES
vault write pki_int/issue/mtls-default common_name="dev.arcticlabs.dev" ttl="24h" -format=table | grep "-----" > cert.pem
vault write pki_int/issue/mtls-default common_name="dev.arcticlabs.dev" ttl="24h" -format=json | jq '.data.certificate'


consul-template \
    -template "./template.ctmpl:/tmp/result"
```
