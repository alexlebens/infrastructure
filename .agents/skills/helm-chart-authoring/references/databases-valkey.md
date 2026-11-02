# Valkey / Redis (Cache & Key-Value) Reference

Homelab applications requiring Redis or Valkey for caching, queuing, or state storage must never embed Bitnami Redis
subcharts. Workloads connect to either the shared cluster Valkey instance or a dedicated instance using the `valkey` OCI
subchart.

---

## Architectural Patterns

1. **Shared Cluster Valkey**: Workloads using lightweight ephemeral cache can connect to the shared Valkey service in
   the cluster.
2. **Dedicated Valkey Instance (`Chart.yaml`)**: For workloads requiring dedicated memory or specific persistence:
   ```yaml
   dependencies:
     - name: valkey
       repository: oci://harbor.alexlebens.dev/helm-charts
       version: 1.13.0
   ```

---

## Values Configuration (`values.yaml`)

When bundling the `valkey` subchart. It is often not necesary to specify values if it is not necesary to adjust the
default options and resources.

```yaml
valkey:
  persistence:
    enabled: true
    storageClass: ceph-block
    size: 2Gi
  resources:
    requests:
      cpu: 10m
      memory: 64Mi
    limits:
      memory: 256Mi
```

---

## Application Connection (`app-template`)

### Service Endpoints

- **Dedicated Subchart**: `<app-name>-valkey.<namespace>.svc.cluster.local:6379`
- **Shared Instance**: `valkey.valkey.svc.cluster.local:6379`

### Environment Injection (`values.yaml`)

```yaml
controllers:
  main:
    containers:
      main:
        env:
          - name: REDIS_HOST
            value: '<app-name>-valkey'
          - name: REDIS_PORT
            value: '6379'
          - name: REDIS_URL
            value: 'redis://<app-name>-valkey:6379/0'
```

If password authentication is enabled via OpenBao:

```yaml
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: '<app-name>-valkey-secret'
      key: password
```
