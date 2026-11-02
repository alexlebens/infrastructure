# CloudNativePG (PostgreSQL) Reference

Homelab applications must never embed Bitnami or generic in-chart PostgreSQL subcharts. Workloads requiring PostgreSQL
must connect to a dedicated CloudNativePG (`Cluster`) instance.

---

## Architectural Patterns

Applications integrate with CNPG with a depdent chart.

```yaml
dependencies:
  - name: postgres-cluster
    repository: oci://harbor.alexlebens.dev/helm-charts
    version: 0.1.0
```

A minimal configuration for values.yaml. Use standalone mode to boostrap, recovery mode once initalized. Additional
configuration is possible as the app requires in the Chart's values.

```yaml
postgres-18-cluster:
  mode: standalone
  recovery:
    objectStore:
      index: 1
  backup:
    objectStore:
      index: 1
    scheduledBackups:
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
