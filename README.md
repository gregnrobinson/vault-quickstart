# Vault Quickstart

This quickstart walks through a Vault installation using Helm with an HA configuration. The setup also walks through setting up OIDC for authenticating using Google and has steps for configuring the GCP secrets engines for both encrypting/decrypting data but also setting up GCP rolesets to allow users to generate temporary GCP credentials on the go using the vault cli.

- [Prerequisites](#prerequisites)
  * [Set Environment Variables](#set-environment-variables)
  * [Install Vault Tools](#install-vault-tools)
  * [Enable APIs](#enable-apis)
  * [Create Storage Bucket](#create-storage-bucket)
  * [Create KMS Keyring and Key](#create-kms-keyring-and-key)
  * [Create Service Account / Kubernetes Secret](#create-service-account---kubernetes-secret)
  * [Create vault namespace and kms-creds secret](#create-vault-namespace-and-kms-creds-secret)
  * [Helm Overrides File](#helm-overrides-file)
- [Install Vault](#install-vault)
- [Unseal and Join Nodes to Raft](#unseal-and-join-nodes-to-raft)
- [Login to Vault](#login-to-vault)
- [Setup GCP OIDC Authentication](#setup-gcp-oidc-authentication)
  * [GCP Configuration](#gcp-configuration)
  * [Add Certificates to Ingress Resources](#add-certificates-to-ingress-resources)
  * [Ingress using Cloudflare](#ingress-using-cloudflare)
  * [Disable unused auth methods](#disable-unused-auth-methods)
- [Setup GCP Engine Rolesets](#setup-gcp-engine-rolesets)
  * [Write initial GCP credentials to engine](#write-initial-gcp-credentials-to-engine)
  * [Allow Vault to generate temporary service account keys](#allow-vault-to-generate-temporary-service-account-keys)
  * [Allow Vault to generate temporary JWTs for GCP API](#allow-vault-to-generate-temporary-jwts-for-gcp-api)
  * [Generate Credentials](#generate-credentials)
  * [Get Just the Service account in plain text](#get-just-the-service-account-in-plain-text)
- [Setup GCP KMS Secret Engine](#setup-gcp-kms-secret-engine)
- [Create Custom Functions for Vault CLI](#create-custom-functions-for-vault-cli)
- [Troubleshooting](#troubleshooting)
- [Reference](#reference)

[Vault Helm Repo](https://github.com/hashicorp/vault-helm)

## Prerequisites

### Set Environment Variables

```bash
export VAULT_ADDR='http://vault.phronesis.cloud:8200'
export GCP_PROJECT="phronesis-cloud"
export GCP_REGION="northamerica-northeast2"
export GCS_BUCKET_NAME="vault-phronesis"
export VAULT_SA_NAME=vault-seal;
export VAULT_SA=${VAULT_SA_NAME}@$GCP_PROJECT.iam.gserviceaccount.com
```

### Install Vault Tools

```
pip install -r requirements.txt
```

### Enable APIs

```bash
gcloud services enable \
    cloudapis.googleapis.com \
    cloudkms.googleapis.com \
    container.googleapis.com \
    containerregistry.googleapis.com \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    --project ${GCP_PROJECT}
```

### Create Storage Bucket

```bash
gsutil mb gs://${GCS_BUCKET_NAME}
gsutil versioning set on gs://${GCS_BUCKET_NAME}
```

### Create KMS Keyring and Key

```bash
gcloud kms keyrings create vault \
    --location ${GCP_REGION} \
    --project ${GCP_PROJECT}

gcloud kms keys create auto-seal \
    --location ${GCP_REGION} \
    --keyring vault \
    --purpose encryption \
    --project ${GCP_PROJECT}
```

### Create Service Account / Kubernetes Secret

```bash
gcloud iam service-accounts create ${VAULT_SA_NAME} \
    --display-name "Vault server service account" \
    --project ${GCP_PROJECT}

gcloud iam service-accounts keys create \
      --iam-account ${VAULT_SA} ./secrets/credentials.json

gcloud kms keys add-iam-policy-binding \
    auto-seal \
    --location ${GCP_REGION} \
    --keyring vault \
    --member serviceAccount:${VAULT_SA} \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --role roles/cloudkms.viewer \
    --role roles/cloudkms.signerVerifier \
    --project ${GCP_PROJECT}
```

### Create vault namespace and kms-creds secret

```
k apply -k ./secrets
```

### Helm Overrides File

*Configure the vault environment within this file.*

```yaml
global:
  enabled: true
  image: "vault:1.12.1"
server:
  extraEnvironmentVars:
    GOOGLE_REGION: northamerica-northeast2
    GOOGLE_PROJECT: phronesis-cloud
    GOOGLE_CREDENTIALS: /vault/userconfig/kms-creds/credentials.json
    GOOGLE_APPLICATION_CREDENTIALS: /vault/userconfig/kms-creds/credentials.json
    VAULT_ADDR: http://127.0.0.1:8200
    VAULT_SKIP_VERIFY: true
  extraVolumes:
  - type: secret
    name: kms-creds
    path: "/vault/userconfig"
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      config: |
        ui = true

        listener "tcp" {
          tls_disable = 1
          address = "[::]:8200"
          cluster_address = "[::]:8201"
        }

        storage "raft" {
            path = "/vault/data"
        }

        seal "gcpckms" {
          project     = "phronesis-cloud"
          region      = "northamerica-northeast2"
          key_ring    = "vault"
          crypto_key  = "auto-seal"
        }

        service_registration "kubernetes" {}
  ingress:
    enabled: true
    labels: {}
      # traffic: external
    annotations:
      kubernetes.io/ingress.class: nginx

    # Optionally use ingressClassName instead of deprecated annotation.
    # See: https://kubernetes.io/docs/concepts/services-networking/ingress/#deprecated-annotation
    ingressClassName: ""

    # As of Kubernetes 1.19, all Ingress Paths must have a pathType configured. The default value below should be sufficient in most cases.
    # See: https://kubernetes.io/docs/concepts/services-networking/ingress/#path-types for other possible values.
    pathType: Prefix

    # When HA mode is enabled and K8s service registration is being used,
    # configure the ingress to point to the Vault active service.
    activeService: true
    hosts:
    - host: vault.phronesis.cloud
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: vault-ui
              port:
                number: 80
     # Extra paths to prepend to the host configuration. This is useful when working with annotation based services.
    tls:
      - secretName: vault-phronesis-cert
        hosts:
          - vault.phronesis.cloud
  service:
    enabled: true

  dataStorage:
    enabled: true
    size: 10Gi
    storageClass: nfs-client
    accessMode: ReadWriteOnce

ui:
  enabled: true
  serviceType: LoadBalancer
```

## Install Vault

```bash
# Add repo
helm repo add hashicorp https://helm.releases.hashicorp.com

# Install/Upgrade
helm upgrade --install vault hashicorp/vault -n vault -f vault/override-values.yml

# Upgrade
helm upgrade vault hashicorp/vault -n vault -f vault/override-values.yml --force

# Uninstall
helm uninstall vault -n vault
```

## Unseal and Join Nodes to Raft

```bash
kubectl exec -n vault -ti vault-0 -- vault operator init
kubectl exec -n vault -ti vault-0 -- vault operator unseal

kubectl exec -n vault -ti vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault -ti vault-1 -- vault operator unseal

kubectl exec -n vault -ti vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault -ti vault-2 -- vault operator unseal

kubectl exec -n vault -ti vault-0 -- vault status
```

## Login to Vault

```bash
export VAULT_ADDR='https://vault.phronesis.cloud'

# Using root token... (do this first to perform rest of the steps)
vault login

# Using OIDC...
vault login -method=oidc role="admin"
```

*You should see a confirmation that you have logged in. If it doesn't work, double-check that all the redirect URLs match on both sides.*

![success](https://user-images.githubusercontent.com/26353407/143464478-9557bd5e-3804-4419-bebf-eef3f6ab4be7.png)

## Setup GCP OIDC Authentication

```bash
export DOMAIN="vault.phronesis.cloud"
export OIDC_DISCOVERY_URL="https://accounts.google.com"
export OIDC_CLIENT_ID=""
export OIDC_CLIENT_SECRET=""

# Enable OIDC auth method
vault auth enable oidc

# Deploy the admin and reader policies to Vault.
vault policy write admin vault/policies/admin.hcl
vault policy write reader vault/policies/reader.hcl

vault write auth/oidc/config \
    oidc_discovery_url="${OIDC_DISCOVERY_URL}" \
    oidc_client_id="${OIDC_CLIENT_ID}" \
    oidc_client_secret="${OIDC_CLIENT_SECRET}" \
    default_role="admin"

# Create a new OIDC role that binds the admin policy to the admin role. Configure redirects to match your own domain if applicable.
# If you are using an ingress for ${DOMAIN} be sure to adjust ports as it may be on port 80 like me.
vault write auth/oidc/role/admin \
    bound_audiences="${OIDC_CLIENT_ID}" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    allowed_redirect_uris="https://localhost:8250/oidc/callback" \
    allowed_redirect_uris="https://localhost:8200/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="https://127.0.0.1:8250/oidc/callback" \
    allowed_redirect_uris="https://127.0.0.1:8200/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="https://${DOMAIN}/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="https://${DOMAIN}/oidc/callback" \
    user_claim="sub" \
    policies="admin"
```

### GCP Configuration

*Note the sections in red. I am currently using only local dns to resolve the domain name. Doing this allows for me to add this domain in the approved JavaScript origins which is what allows me to log in to vault using the UI. IP addresses are not allowed in the allowed origins section so you need to be using either a local or publically accessible domain name.*

![oidc_config](https://user-images.githubusercontent.com/26353407/143460972-8df8d06f-d356-4812-8ffe-2d4d927364d3.png)

### Add Certificates to Ingress Resources

```bash
# Deploy CloudFlare issuer for Cloudflare Origin CA Certificates
# Modify tls/cloudflare/API-key.yaml with your API key. 
# Add cert files that call the deployed cluster issuers. Refer to the examples below on how to do this.
kubectl apply -k tls --validate=false
```

### Ingress using Cloudflare

*Note: The ingress needs to reside within the same namespace as the cert that was created in the step above. The `secretName` field in `ingress.yaml` needs to match the `secretName` in `cert.yaml`.*

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-phronesis-cert
  namespace: vault
spec:
  secretName: vault-phronesis-cert # <---- SECRET THAT WILL STORE CERT
  dnsNames:
  - 'vault.phronesis.cloud'
  acme:
    config:
    - dns01:
        provider: cloudflare
      domains:
      - 'vault.phronesis.cloud'
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-cloudflare-ingress
  namespace: <NAMESPACE_WITH_CERT>
spec:
  tls:
  - hosts:
      - <DOMAIN_LINKED_TO_CERT>
    secretName: vault-phronesis-cert # <---- SECRET WITH CERT
  rules:
  - host: <DOMAIN_LINKED_TO_CERT>
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: service1
            port:
              number: 80
```

### Disable unused auth methods

```bash
vault auth disable userpass/
```

## Setup GCP Engine Rolesets

### Write initial GCP credentials to engine

```bash
vault write gcp/config credentials=@secrets/credentials.json
```

required vault permissons...
```bash
path "/gcp/roleset/+" {
    capabilities = ["read"]
}
```

### Allow Vault to generate temporary service account keys
```bash
# Generate OAuth2 keys/
# Add these roles to service account
# -- Service Account Admin
# -- Service Account Key Admin
vault write gcp/roleset/access-token \
  project="phronesis-cloud" \
  secret_type="access_token"  \
  token_scopes="https://www.googleapis.com/auth/cloud-platform" \
  bindings=-<<EOF
    resource "//cloudresourcemanager.googleapis.com/projects/phronesis-cloud" {
      roles = ["roles/editor"]
    }
EOF
```

### Allow Vault to generate temporary JWTs for GCP API

```bash
# Generate Service Accounts/Keys
# Add these roles to service account
vault write gcp/roleset/service-account \
    project="phronesis-cloud" \
    secret_type="service_account_key"  \
    bindings=-<<EOF
      resource "//cloudresourcemanager.googleapis.com/projects/phronesis-cloud" {
        roles = ["roles/editor"]
      }
EOF
```

### Generate Credentials

```bash
# Access Token
vault read gcp/roleset/access-token/token

# Service Account Key
vault kv get -field=private_key_data gcp/roleset/service-account/key | base64 -d | tr -d '\n'

# Dynamic token generation.
vault read -format json gcp/roleset/access-token/token > token.json

# OIDC LOGIN
gcloud auth login --cred-file=$(gcloud auth application-default print-access-token --access-token-file token.json) --update-adc
```

### Get Just the Service account in plain text

```bash
vault read -field=private_key_data -format=json gcp/roleset/service-account/key | jq -r . | base64 -D > credentials.json
export GOOGLE_APPLICATION_CREDENTIALS="credentials.json"
```

## Setup GCP KMS Secret Engine

```bash
vault secrets enable gcpkms

# Preferred to use a perminent service account to handle key rotations.
vault write gcpkms/config \
    credentials=@secrets/credentials.json
```

```bash
vault write gcpkms/keys/default \
  key_ring=projects/phronesis-cloud/locations/northamerica-northeast2/keyRings/vault \
  rotation_period="24h"
```

```bash
# Encrypt data
vault write gcpkms/encrypt/default plaintext="hello"
Key            Value
---            -----
ciphertext     CiQADBIU7e3IZdrGKLQdEzoI3vaf0ah9Tquz9XkNtlKwSZ/0Dv8SLgAW0CSCelLlCt4b4hcqeJ0tCZrIxm8xAqs8OV1wLJHeO2Eh43huvLAZ7+PkJAg=
key_version    1

# Decrypt data
vault write gcpkms/decrypt/default ciphertext="CiQADBIU7e3IZdrGKLQdEzoI3vaf0ah9Tquz9XkNtlKwSZ/0Dv8SLgAW0CSCelLlCt4b4hcqeJ0tCZrIxm8xAqs8OV1wLJHeO2Eh43huvLAZ7+PkJAg="
Key          Value
---          -----
plaintext    hello
```

## Create Custom Functions for Vault CLI

Place the functions in ~/.bashrc or ~/.zshrc and execute as commands

```bash
# encrypt plaintext data
# usage: vault-encrypt <plain_text>
vault-encrypt() {
    vault write -field=ciphertext gcpkms/encrypt/default plaintext="$1"
}

# decrypt ciphertext data
# usage: vault-decrypt <cipher_text>
vault-decrypt() {
    vault write -field=plaintext gcpkms/decrypt/default ciphertext="$1"
}

# generate a temporary gcp token for using against GCP APIs
vault-gcp-token() {
    vault kv get -field=token gcp/roleset/access-token/token
}

# generate a temporary gcp service account credential file for use against GCP
vault-gcp-sa() {
    vault kv get -field=private_key_data gcp/roleset/service-account/key | base64 -d | tr -d '\n' | jq .
}
```

## Troubleshooting

```bash
vault operator raft list-peers 
```

```yaml
Node                                    Address                        State       Voter
----                                    -------                        -----       -----
75b60fd0-4fdd-4e0a-14d4-c80e2f4600fb    vault-0.vault-internal:8201    leader      true
1d2353fb-3759-b463-4fc0-bf4d7e0e21a5    vault-1.vault-internal:8201    follower    true
fcf2a4b7-3ad3-4757-e922-bf8c4d0ce7a3    vault-2.vault-internal:8201    follower    true
```

## Reference

- <https://learn.hashicorp.com/tutorials/vault/oidc-auth>
- <https://www.youtube.com/watch?v=u_-rNq1xH7A&t=622s>
- <https://github.com/IdentityServer/IdentityServer4/issues/1116>
- <https://www.vaultproject.io/docs/configuration/listener/tcp>
- <https://www.vaultproject.io/docs/configuration/seal/gcpckms>
- <https://blog.doit-intl.com/vault-high-availability-on-gke-68ef4fd7ca33>
- <https://www.vaultproject.io/docs/configuration/storage/google-cloud-storage>
- <https://github.com/hashicorp/vault/issues/7790>
- <https://www.vaultproject.io/docs/auth/jwt/oidc_providers>  
- <https://discuss.hashicorp.com/t/problem-getting-oidc-to-work-with-azure-in-the-ui-cli-works-fine/4721/>  
- <https://www.vaultproject.io/docs/auth/gcp>
- <https://www.vaultproject.io/docs/secrets/ssh/signed-ssh-certificates>
- <https://learn.hashicorp.com/tutorials/vault/agent-kubernetes?in=vault/kubernetes>
- <https://www.vaultproject.io/docs/secrets/aws>
