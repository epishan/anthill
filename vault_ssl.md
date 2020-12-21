https://learn.hashicorp.com/tutorials/vault/pki-engine

# Vault CA authority:
## Step 1: Generate Root CA
    
    vault secrets enable pki
     
    # 10yrs
    vault secrets tune -max-lease-ttl=87600h pki

    # Generate the root certificate and save the certificate in CA_cert.crt.
     vault write -field=certificate pki/root/generate/internal \
        common_name="vault" \
        ttl=87600h > CA_cert.crt

    # Configure the CA and CRL URLs.
    vault write pki/config/urls \
        issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
        crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"

## Step 2: Generate Intermediate CA
    vault secrets enable -path=pki_int pki

    # 5yr
    vault secrets tune -max-lease-ttl=43800h pki_int

    # generate an intermediate and save the CSR as pki_intermediate.csr.
    vault write -format=json pki_int/intermediate/generate/internal \
        common_name="vault Intermediate Authority" \
        | jq -r '.data.csr' > pki_intermediate.csr

    # Sign the intermediate certificate with the root certificate and save the generated certificate as intermediate.cert.pem
    vault write -format=json pki/root/sign-intermediate csr=@pki_intermediate.csr \
        format=pem_bundle ttl="43800h" \
        | jq -r '.data.certificate' > intermediate.cert.pem

    # import signed int cert back to vault
    vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem


## Step 3. Configure role
    vault write pki_int/roles/anthill_test \
        allow_any_name=true \
        max_ttl="8760h" 

## Step 4: Request Certificates
    vault write pki_int/issue/anthill_test common_name="vault" ttl="24h"

    

## 
    curl \
        --header "X-Vault-Token: $TOKEN" \
        $VAULT_ADDR/v1/pki/config/urls    
    
## Issues ca for vault
vault write pki/roles/vault_site \
    allow_any_name=true \
    client_flag=false server_flag=true \
    code_signing_flag=false email_protection_flag=false \
    max_ttl="8760h" 

vault write -format=json pki/issue/vault_site \
    common_name=vault \
    alt_names=localhost, \
    ip_sans=127.0.0.1 \
    ttl=87500h > cert.json 
cat cert.json | jq -r '.data.certificate' > cert.crt && cat cert.json | jq -r '.data.private_key'  > cert.key && rm cert.json

export VAULT_CACERT=~/certs/vault_rootCA.pem
