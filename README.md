# Vault Quickstart

- [Prerequisites](#prerequisites)
  - [Environment Variables](#environment-variables)
  - [Enable APIs](#enable-apis)
  - [Create Storage Bucket](#create-storage-bucket)
  - [Create KMS Keyring and Key](#create-kms-keyring-and-key)
  - [Create Service Account](#create-service-account-kubernetes-secret)
  - [Helm Overrides File](#helm-overrides-file)
  - [`override-values.yml`](#override-valuesyml)
- [Install](#install)
- [Unseal and Join Nodes to Raft](#unseal-and-join-nodes-to-raft)
- [GCP OIDC Authentication](#gcp-oidc-authentication)
  - [GCP Configuration](#gcp-configuration)
- [Login to Vault](#login-to-vault)
- [Add Certificates to Ingress Resources](#add-certificates-to-ingress-resources)
  - [Ingress using Cloudflare](#ingress-using-cloudflare)
  - [Ingress using Selfsigned](#ingress-using-selfsigned)
- [Troubleshooting](#troubleshooting)
- [Reference](#reference)

This quickstart walks through a Vault installation using Helm with an HA configuration. The storage backend is in a GCS bucket and KMS is used for auto sealing the Vault environment. This quickstart also shows how to get OIDC authentication working with GCP.

[Vault Helm Repo](https://github.com/hashicorp/vault-helm)

## Prerequisites

### Environment Variables

```bash
export VAULT_ADDR='http://vault.phronesis.cloud:8200'
export VAULT_TOKEN='<YOUR_ROOT_TOKEN>'

export GCP_PROJECT=""
export GCP_REGION=""
export GCS_BUCKET_NAME=""
export VAULT_SA_NAME=vault-seal;
export VAULT_SA=${VAULT_SA_NAME}@$GCP_PROJECT.iam.gserviceaccount.com
```

### Enable APIs

```bash
gcloud services enable \
    cloudapis.googleapis.com \
    cloudkms.googleapis.com \
    container.googleapis.com \
    containerregistry.googleapis.com \
    iam.googleapis.com \
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
      --iam-account ${VAULT_SA} credentials.json

gcloud kms keys add-iam-policy-binding \
    vault-helm-unseal-key \
    --location ${GCP_REGION} \
    --keyring vault \
    --member serviceAccount:${VAULT_SA} \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --role roles/cloudkms.viewer \
    --project ${GCP_PROJECT}
```

## Helm Overrides File

*Configure the vault environment within this file.*

### `override-values.yml`

```yaml
global:
  enabled: true
  image: "vault:1.9.0"
server:
  extraEnvironmentVars:
    GOOGLE_REGION: northamerica-northeast2
    GOOGLE_PROJECT: phronesis-310405
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
          project     = "phronesis-310405"
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

## Install

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
export VAULT_TOKEN='<YOUR_ROOT_TOKEN>'

# Using root token... (do this first to perform rest of the steps)
vault login

# Using OIDC...
vault login -method=oidc role="admin"
```

*You should see a confirmation that you have logged in. If it doesn't work, double-check that all the redirect URLs match on both sides.*

![success](https://user-images.githubusercontent.com/26353407/143464478-9557bd5e-3804-4419-bebf-eef3f6ab4be7.png)

## GCP OIDC Authentication

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

## Add Certificates to Ingress Resources

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

### Ingress using Selfsigned

```yaml
# Certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: consul-phronesis-cert
  namespace: consul
spec:
  secretName: consul-phronesis-cert # <---- SECRET THAT WILL STORE CERT
  dnsNames:
  - 'consul.phronesis.cloud'
  issuerRef:
    name: selfsigning-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
# Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-selfsigned-ingress
  namespace: <NAMESPACE_WITH_CERT>
spec:
  tls:
  - hosts:
      - <DOMAIN_LINKED_TO_CERT>
    secretName: consul-phronesis-cert # <---- SECRET WITH CERT
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

## Disable unused auth methods

```bash
vault auth disable userpass/
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

## Retrieving Secrets

```bash
vault kv get gcp/test
```

## Setup GCP Roleset

### Write credentials to engine

```bash
vault write gcp/config credentials=@secrets/credentials.json
```

### Permissions

```bash
path "/gcp/roleset/+" {
    capabilities = ["read"]
}
```

```bash
# Generate OAuth2 keys/
# Add these roles to service account
# -- Service Account Admin
# -- Service Account Key Admin
vault write gcp/roleset/access-token \
  project="phronesis-310405" \
  secret_type="access_token"  \
  token_scopes="https://www.googleapis.com/auth/cloud-platform" \
  bindings=-<<EOF
    resource "//cloudresourcemanager.googleapis.com/projects/phronesis-310405" {
      roles = ["roles/editor"]
    }
EOF

# Generate Service Accounts
# Add these roles to service account
vault write gcp/roleset/service-account \
    project="phronesis-310405" \
    secret_type="service_account_key"  \
    bindings=-<<EOF
      resource "//cloudresourcemanager.googleapis.com/projects/phronesis-310405" {
        roles = ["roles/editor"]
      }
EOF
```

### Retrieve Credentials

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

## Get Just the Service account in plain text

```bash
vault read -field=private_key_data -format=json gcp/roleset/service-account/key | jq -r . | base64 -D > credentials.json
export GOOGLE_APPLICATION_CREDENTIALS="credentials.json"
```

## GCP KMS Secret Engine

```bash

# Preferred to use a perminent service account to handle key rotations.
vault write gcpkms/config \
    credentials=@secrets/credentials.json
Success! Data written to: gcpkms/config
```

```bash
vault write gcpkms/keys/default \
  key_ring=projects/phronesis-310405/locations/northamerica-northeast2/keyRings/vault-gcpkms \
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

## SSH Engine

### Backend config

```bash
# Generate signing key. This key needs to be placed on all hosts.
vault write ssh-client-signer/config/ca generate_signing_key=true

# retrieve public key from remote host
curl -k --silent https://vault.phronesis.cloud/v1/ssh-client-signer/public_key > vault_ca.pem
sudo cp vault_ca.pem /etc/ssh

sudo vi /etc/ssh/sshd_config

# add this line...
TrustedUserCAKeys /etc/ssh/vault_ca.pem

# Create role to allow ssh...
vault write ssh-client-signer/roles/ssh-allow -<<"EOH"
{
  "allow_user_certificates": true,
  "allowed_users": "*",
  "allowed_extensions": "permit-pty,permit-port-forwarding",
  "default_extensions": [
    {
      "permit-pty": ""
    }
  ],
  "key_type": "ca",
  "default_user": "ubuntu",
  "ttl": "30m0s"
}
EOH
```

### Client config

```bash
# Get your local machines ssh public key signed...
vault write ssh-client-signer/sign/ssh-allow \
    public_key=@$HOME/.ssh/id_rsa.pub

vault write -field=signed_key ssh-client-signer/sign/ssh-allow \
    public_key=@$HOME/.ssh/id_rsa.pub > signed-cert.pub

# Show more details about cert
ssh-keygen -Lf ~/.ssh/signed-cert.pub
```

```bash
vault write gcpkms/keys/default plaintext="hello world"
```

```bash
export SSH_KEY=$(vault kv get -field="id_rsa" ssh/arctiq-mac/)
printf '%s' $SSH_KEY | ssh-add -
```

```bash
vault write -field=signed_key ssh-client-signer/sign/ssh-allow \
    public_key=@$HOME/.ssh/id_rsa.pub > signed-cert.pub
```

## AWS Secrets Engine

```bash
vault secrets enable aws

vault write aws/config/root \
    access_key=<ACCESS_KEY> \
    secret_key=<SECRET_KEY> \
    region=us-east-1
    
vault write aws/roles/ec2-admin \
    credential_type=iam_user \
    policy_document=-<<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:*",
      "Resource": "*"
    }
  ]
}
EOF

# Grab new credentials with ec2-admin permissions...
vault read aws/creds/ec2-admin ttl=30m
```

## Azure Secret Engine

```bash
vault secrets enable azure

vault write azure/config \
    subscription_id="3ce1827e-a29b-45c2-aed2-aaa5d39a9342" \
    tenant_id="65b6be73-2104-4ff4-899f-5bff3196f3d1" \
    client_id="3b38cc97-247b-4b5f-9e71-0e196e814432" \
    client_secret="iU97Q~t2mAfsRfwWHFp0TOWSAcAGBU49brNT-" \
    use_microsoft_graph_api=true

vault write azure/roles/contributer ttl=1h azure_roles=-<<EOF
    [
        {
            "role_name": "Contributor",
            "scope":  "/subscriptions/3ce1827e-a29b-45c2-aed2-aaa5d39a9342/resourceGroups/Website"
        }
    ]
EOF

vault read azure/creds/viewer

vault read azure/creds/contributer
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
