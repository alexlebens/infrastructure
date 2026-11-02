# MongoDB (Percona PSMDB) Reference

Homelab applications requiring MongoDB must never bundle raw unmanaged MongoDB subcharts. Applications use **Percona
Server for MongoDB Operator** (`psmdb-operator`), which watches all cluster namespaces.

---

## Chart Dependency (`Chart.yaml`)

Workloads deploy a managed replica set using the `psmdb-db` subchart:

```yaml
dependencies:
  - name: psmdb-db
    alias: <app-name>-mongodb
    repository: https://percona.github.io/percona-helm-charts/
    version: 1.23.4
```

---

## Values Configuration (`values.yaml`)

Define replica set name, image, storage, and backup integration:

```yaml
<app-name>-mongodb:
  fullnameOverride: <app-name>-mongodb
  image:
    repository: percona/percona-server-mongodb
    tag: 8.0.4-1
  replsets:
    - name: rs0
      size: 1
      volumeSpec:
        pvc:
          storageClassName: ceph-block
          resources:
            requests:
              storage: 5Gi
  secrets:
    users: <app-name>-mongodb-user-secret
  backup:
    enabled: true
    storages:
      s3:
        type: s3
        s3:
          bucket: mongodb-backups
          prefix: cl01tl/<app-name>
          region: garage
          endpointUrl: https://a.s3.alexlebens.dev
          credentialsSecret: <app-name>-mongodb-backup-s3
```

---

## Application Connection (`app-template`)

The replica set exposes a headless / internal cluster service at `<app-name>-mongodb-rs0.<namespace>:27017`:

```yaml
controllers:
  main:
    containers:
      main:
        env:
          - name: DB_USERNAME
            valueFrom:
              secretKeyRef:
                name: <app-name>-mongodb-user-secret
                key: MONGODB_USER
          - name: DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: <app-name>-mongodb-user-secret
                key: MONGODB_USER_PASSWORD
          - name: MONGODB_URI
            value: 'mongodb://$(DB_USERNAME):$(DB_PASSWORD)@<app-name>-mongodb-rs0.<namespace>.svc.cluster.local:27017/<app-name>?replicaSet=rs0&authSource=admin'
```
