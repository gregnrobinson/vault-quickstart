# Consul

## Install

### `override-values.yml`

```yaml
global:
  # The main enabled/disabled setting. If true, servers,
  # clients, Consul DNS and the Consul UI will be enabled. Each component can override
  # this default via its component-specific "enabled" config. If false, no components
  # will be installed by default and per-component opt-in is required, such as by
  # setting `server.enabled` to true.
  enabled: true


ui:
  enabled: true
  service:
    enabled: true
    type: LoadBalancer

server:
  storage: 10Gi
  storageClass: nfs-client
```

```bash
# Install
helm install consul hashicorp/consul \
  --set global.name=consul \
  -n consul -f consul/override-values.yml

# Upgrade
helm upgrade consul hashicorp/consul \
  --set global.name=consul \
  -n consul -f consul/override-values.yml --force

# Self signed cert
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout privkey.pem -out cert.pem -subj "/CN=consul.phronesis.cloud/O=192.168.0.212"

# Uninstall
helm uninstall consul -n consul
```
