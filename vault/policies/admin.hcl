path "sys/health"
{
  capabilities = ["read", "sudo"]
}

# Create and manage ACL policies broadly across Vault

# List existing policies
# Write ACL policies
path "sys/policies/acl/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

path "transit/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

path "kubernetes/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

path "database/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

path "creds/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

path "secret*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

path "sendgrid*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

path "repos/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

# Create and manage ACL policies
path "sys/policies/acl/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Enable and manage authentication methods broadly across Vault

# Manage auth methods broadly across Vault
path "auth/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Create, update, and delete auth methods
path "sys/auth/*"
{
  capabilities = ["create", "update", "delete", "sudo"]
}

# List auth methods
path "sys/auth"
{
  capabilities = ["read"]
}

# Enable and manage the key/value secrets engine at `secret/` path

# List, create, update, and delete key/value secrets
path "secret/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}


path "aws/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "azure/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "ssh/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "static/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "/gcp/roleset/+" {
    capabilities = ["read"]
}

path "/gcpkms/*" {
    capabilities = ["read"]
}

# Manage secrets engines
path "sys/mounts/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/internal/ui/mounts/*" {
  capabilities = ["read"]
}

# List existing secrets engines.
path "sys/mounts"
{
  capabilities = ["read"]
}

path "secret/metadata" {
  		capabilities = ["list"]
}

# Allow tokens to look up their own properties
path "auth/token/lookup-self" {
    capabilities = ["read"]
}

# Manage tokens for verification
path "auth/token/create" {
  capabilities = [ "create", "read", "update", "delete", "list", "sudo" ]
}

# Allow tokens to renew themselves
path "auth/token/renew-self" {
    capabilities = ["update"]
}

# Allow tokens to revoke themselves
path "auth/token/revoke-self" {
    capabilities = ["update"]
}

# Allow a token to look up its own capabilities on a path
path "sys/capabilities-self" {
    capabilities = ["update"]
}

# Allow a token to look up its own entity by id or name
path "identity/entity/id/{{identity.entity.id}}" {
  capabilities = ["read"]
}
path "identity/entity/name/{{identity.entity.name}}" {
  capabilities = ["read"]
}

# Allow a token to look up its resultant ACL from all policies. This is useful
# for UIs. It is an internal path because the format may change at any time
# based on how the internal ACL features and capabilities change.
path "sys/internal/ui/resultant-acl" {
    capabilities = ["read"]
}

# Allow a token to renew a lease via lease_id in the request body; old path for
# old clients, new path for newer
path "sys/renew" {
    capabilities = ["update"]
}
path "sys/leases/renew" {
    capabilities = ["update"]
}

# Allow looking up lease properties. This requires knowing the lease ID ahead
# of time and does not divulge any sensitive information.
path "sys/leases/lookup" {
    capabilities = ["update"]
}

# Allow a token to manage its own cubbyhole
path "cubbyhole/*" {
    capabilities = ["create", "read", "update", "delete", "list"]
}

path "gcp/*" {
    capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Allow a token to wrap arbitrary values in a response-wrapping token
path "sys/wrapping/wrap" {
    capabilities = ["update"]
}

# Allow a token to look up the creation time and TTL of a given
# response-wrapping token
path "sys/wrapping/lookup" {
    capabilities = ["update"]
}

# Allow a token to unwrap a response-wrapping token. This is a convenience to
# avoid client token swapping since this is also part of the response wrapping
# policy.
path "sys/wrapping/unwrap" {
    capabilities = ["update"]
}

# Allow general purpose tools
path "sys/tools/hash" {
    capabilities = ["update"]
}
path "sys/tools/hash/*" {
    capabilities = ["update"]
}

# Allow checking the status of a Control Group request if the user has the
# accessor
path "sys/control-group/request" {
    capabilities = ["update"]
}

# Allow a token to make requests to the Authorization Endpoint for OIDC providers.
path "identity/oidc/provider/+/authorize" {
	capabilities = ["read", "update"]
}

# Read system health check
path "sys/health"
{
  capabilities = ["read", "sudo"]
}

# Create and manage ACL policies broadly across Vaultcation methods broadly across Vault
