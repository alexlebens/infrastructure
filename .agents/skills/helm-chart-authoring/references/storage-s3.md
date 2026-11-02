# S3 Object Storage & OpenTofu Reference

Guidelines for declarative S3 bucket provisioning via OpenTofu and workload integration in Helm charts.

---

## Architecture Overview

Object storage is managed across multiple Garage S3 and cloud tiers:

| Tier  | Identifier       | Target Location                         | Use Case                                         |
| :---- | :--------------- | :-------------------------------------- | :----------------------------------------------- |
| **A** | `a` / `a_ps02sn` | `ps02sn` (Synology NAS Garage S3)       | High-capacity primary / backup storage           |
| **B** | `b` / `b_cl01tl` | `cl01tl` (Cluster-local Ceph/Garage S3) | Low-latency application state & caches (Default) |
| **C** | `c` / `c_ps10rp` | `ps10rp` (Raspberry Pi Garage S3)       | Offsite replica                                  |
| **D** | `d` / `d_cs01bb` | Backblaze B2 (`us-east-005`)            | Cloud disaster recovery                          |

> [!IMPORTANT] Never manually create S3 buckets via CLI or embed MinIO subcharts. All application buckets are
> declaratively discovered by OpenTofu from the chart's `values.yaml` and provisioned automatically.

---

## Declarative Chart Configuration (`values.yaml`)

Define the `s3-bucket:` block in the application's `values.yaml`:

```yaml
s3-bucket:
  enabled: true
  bucketName: <app-name>-assets # Defaults to chart name if omitted
  target: b # Target tier: 'a', 'b', 'c', or 'd' (default: 'b')
  cors:
    enabled: true
    allowedOrigins:
      - 'https://<app-name>.alexlebens.dev'
    allowedMethods:
      - GET
      - PUT
      - POST
      - DELETE
      - HEAD
  backups:
    a:
      enabled: true
      schedule: '10 3 * * *'
      destination:
        bucketName: <app-name>-assets
    c:
      enabled: true
      schedule: '30 2 * * 3'
      destination:
        bucketName: <app-name>-assets
    d:
      enabled: true
      schedule: '0 2 * * 3'
      destination:
        bucketName: <app-name>-assets-<hash>
```

### Static Website Hosting (Optional)

If the bucket serves static web assets directly:

```yaml
s3-bucket:
  enabled: true
  bucketName: <app-name>-static
  target: a
  website:
    enabled: true
    indexDocument: index.html
    errorDocument: error.html
```

---

## OpenTofu Automation (`infrastructure/tofu/buckets/`)

OpenTofu continuously scans all charts in `clusters/cl01tl/helm/*/values.yaml` for `s3-bucket.enabled: true`:

1. **Bucket Creation**: Provisions the bucket on the target Garage S3 cluster (or Backblaze).
2. **Access Key Generation**: Generates dedicated access and secret keys per bucket.
3. **OpenBao Secrets Sync**: Automatically stores credentials in OpenBao at:
   - Tier A: `/ps02sn/garage/keys/<bucket-name>`
   - Tier B: `/cl01tl/garage/keys/<bucket-name>`
   - Tier C: `/ps10rp/garage/keys/<bucket-name>`
   - Tier D: `/cs01bb/backblaze/keys/<bucket-name>`

Stored properties include:

- `BUCKET_NAME`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` (`"garage"`)
- `ENDPOINT` (Tier B cluster endpoint)

### Applying OpenTofu Changes

When adding or altering `s3-bucket` values in a chart:

```bash
cd infrastructure/tofu/buckets
tofu plan
tofu apply
```

---

## Workload Integration (ExternalSecret & app-template)

Workloads consume S3 credentials by synchronizing them into a Kubernetes Secret via ESO and mounting them into the
container.

### 1. ExternalSecret Manifest (`templates/external-secret.yaml`)

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <app-name>-s3-secret
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/name: <app-name>-s3-secret
    {{- include "custom.labels" . | nindent 4 }}
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: openbao
  data:
    - secretKey: S3_ENDPOINT
      remoteRef:
        key: /ps02sn/garage/config # or /cl01tl/garage-operator/config
        property: ENDPOINT
    - secretKey: S3_BUCKET
      remoteRef:
        key: /ps02sn/garage/keys/<bucket-name>
        property: BUCKET_NAME
    - secretKey: S3_REGION
      remoteRef:
        key: /ps02sn/garage/keys/<bucket-name>
        property: AWS_REGION
    - secretKey: S3_ACCESS_KEY_ID
      remoteRef:
        key: /ps02sn/garage/keys/<bucket-name>
        property: AWS_ACCESS_KEY_ID
    - secretKey: S3_SECRET_ACCESS_KEY
      remoteRef:
        key: /ps02sn/garage/keys/<bucket-name>
        property: AWS_SECRET_ACCESS_KEY
```

### 2. Application Container Mount (`values.yaml`)

Inject S3 credentials as environment variables into `app-template`:

```yaml
controllers:
  main:
    containers:
      main:
        envFrom:
          - secretRef:
              name: <app-name>-s3-secret
```
