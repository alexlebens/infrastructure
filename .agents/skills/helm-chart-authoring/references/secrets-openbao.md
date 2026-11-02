# Secrets & OpenBao (External Secrets Operator) Reference

All sensitive credentials (API tokens, database passwords, OIDC client secrets, encryption keys) are securely stored in
OpenBao and synchronized into Kubernetes Secrets using the External Secrets Operator (ESO).

---

## SecretStore Reference

All namespaces sync from the cluster-wide SecretStore:

- **Kind**: `ClusterSecretStore`
- **Name**: `openbao`
- **API Version**: `external-secrets.io/v1`

---

## Dedicated Manifest (`templates/external-secret.yaml`)

Strictly separate external secrets into `templates/external-secret.yaml` (kebab-case):

### Example Pattern: Direct Key-Value Sync (Standard Workload Secrets)

Used for application tokens, passwords, and API keys stored under `/cl01tl/<app>/config` or `/cl01tl/<app>/key` (e.g.
`actual`, `homebox`, `paperless-ngx`):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <app-name>-secret
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/name: <app-name>-secret
    {{- include "custom.labels" . | nindent 4 }}
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: openbao
  data:
    - secretKey: password
      remoteRef:
        key: /cl01tl/<app-name>/config
        property: password
    - secretKey: api-key
      remoteRef:
        key: /cl01tl/<app-name>/key
        property: api-key
```

---

## Values Injection (`app-template`)

Mount the synchronized Secret into the application container:

### As Environment Variables (`env` / `envFrom`)

```yaml
controllers:
  main:
    containers:
      main:
        envFrom:
          - secretRef:
              name: <app-name>-secret
```

### Mounted as Files (`persistence`)

```yaml
persistence:
  secrets:
    type: secret
    name: <app-name>-secret
    globalMounts:
      - path: /etc/secrets
        readOnly: true
```
