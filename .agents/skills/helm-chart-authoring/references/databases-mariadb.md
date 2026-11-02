# MariaDB / MySQL Reference

Homelab applications requiring MySQL or MariaDB must never bundle raw generic subcharts. Deployments utilize the
cluster's **`mariadb-operator`** (`https://helm.mariadb.com/mariadb-operator`).

---

## Chart Dependency (`Chart.yaml`)

When declaring a dedicated MariaDB cluster for an application, add the `mariadb-cluster` subchart:

```yaml
dependencies:
  - name: mariadb-cluster
    repository: https://helm.mariadb.com/mariadb-operator
    version: 0.38.0
```

---

## Values Configuration (`values.yaml`)

Configure the cluster with storage, credentials secret, and S3 backup integration:

```yaml
mariadb-cluster:
  mariadb:
    rootPasswordSecretKeyRef:
      name: <app-name>-database-secret
      key: password
      generate: false
    storage:
      size: 5Gi
      storageClassName: ceph-block
    startupProbe:
      failureThreshold: 30
      periodSeconds: 10
      timeoutSeconds: 5
    bootstrapFrom:
      s3:
        bucket: mariadb-backups
        prefix: cl01tl/<app-name>
        endpoint: a.s3.alexlebens.dev
        region: garage
        accessKeyIdSecretKeyRef:
          name: <app-name>-mariadb-backup-secret-garage
          key: access
        secretAccessKeySecretKeyRef:
          name: <app-name>-mariadb-backup-secret-garage
          key: secret
        tls:
          enabled: true
      backupContentType: Physical
  databases:
    - name: <app-name>
      characterSet: utf8mb4
      collate: utf8mb4_unicode_ci
```

---

## Application Connection (`app-template`)

The operator exposes service `<app-name>-mariadb.<namespace>:3306`:

```yaml
controllers:
  main:
    containers:
      main:
        env:
          - name: DB_HOST
            value: '<app-name>-mariadb'
          - name: DB_PORT
            value: '3306'
          - name: DB_NAME
            value: '<app-name>'
          - name: DB_USER
            value: 'root'
          - name: DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: '<app-name>-database-secret'
                key: password
```
