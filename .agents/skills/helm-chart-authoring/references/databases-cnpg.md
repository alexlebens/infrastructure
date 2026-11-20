# CloudNativePG (PostgreSQL) Reference

Homelab applications must never embed Bitnami or generic in-chart PostgreSQL subcharts. Workloads requiring PostgreSQL
must connect to a dedicated CloudNativePG (`Cluster`) instance.

---

## Architectural Patterns

Applications integrate with CNPG via a dependent `postgres-cluster` chart (no alias needed for `v9.0.0+`, which
provisions versionless `<release>-postgres-cluster` resources and defaults to `ClusterImageCatalog`
`postgresql-standard-trixie` at PostgreSQL `major: 19` for future in-place `pg_upgrade` support and automatic
`<cluster.name>-pg<major>-backup-<index>` Barman `serverName` rotation).

```yaml
dependencies:
  - name: postgres-cluster
    repository: oci://harbor.alexlebens.dev/helm-charts
    version: 9.0.0
```

A minimal configuration for `values.yaml`. Use `standalone` mode to bootstrap, `recovery` mode (`objectStore`) once
initialized. Additional configuration is possible as the app requires in the chart's values.

```yaml
postgres-cluster:
  mode: standalone
  recovery:
    objectStore:
      index: 1
  backup:
    objectStore:
      index: 1
    scheduledBackup:
      suspend: false
      schedule: '0 5 5 * * *'
```

---

## Credentials Secret Format

CNPG automatically generates a Kubernetes Secret named `<cluster-name>-app` containing:

- `uri`: `postgresql://<user>:<password>@<cluster-name>-rw:5432/<dbname>`
- `host`: `<cluster-name>-rw`
- `port`: `5432`
- `user` / `username`: `<user>`
- `password`: `<password>`
- `dbname`: `<dbname>`

---

## Values Configuration (`app-template`)

Inject the CNPG credentials into your application container via environment variables. Check the apps configuration for
the correct envs, these are examples.

### Direct Secret Key Mapping

```yaml
controllers:
  main:
    containers:
      main:
        env:
          - name: DB_HOST
            value: '<cluster-name>-rw'
          - name: DB_PORT
            value: '5432'
          - name: DB_NAME
            value: '<dbname>'
          - name: DB_USER
            valueFrom:
              secretKeyRef:
                name: '<cluster-name>-app'
                key: username
          - name: DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: '<cluster-name>-app'
                key: password
```

### Full URI Connection String

For applications that accept a single connection URI:

```yaml
controllers:
  main:
    containers:
      main:
        env:
          - name: DATABASE_URL
            valueFrom:
              secretKeyRef:
                name: '<cluster-name>-app'
                key: uri
```
