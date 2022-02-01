{{- /* /tmp/cert.tpl */ -}}
{{ with secret "pki/issue/mtls-default" "common_name=dc1.arcticlabs.dev" }}
{{ .Data.certificate }}{{ end }}


{{- /* /tmp/ca.tpl */ -}}
{{ with secret "pki/issue/mtls-default" "common_name=dc1.arcticlabs.dev" }}
{{ .Data.issuing_ca }}{{ end }}


{{- /* /tmp/key.tpl */ -}}
{{ with secret "pki/issue/mtls-default" "common_name=dc1.arcticlabs.dev" }}
{{ .Data.private_key }}{{ end }}
