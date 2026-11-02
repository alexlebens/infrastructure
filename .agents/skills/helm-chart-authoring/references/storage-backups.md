# Storage & Backups Reference

Guidelines for persistent storage claims, VolSync backup pipelines, and S3 object storage.

---

## Persistent Storage (PVC via `app-template`)

Stateful workloads requiring block storage use Ceph RBD (`ceph-block`) declared directly under `persistence` in
`values.yaml`:

### 1. Dedicated Block Storage Volume (`ceph-block`)

Use `forceRename` to ensure the generated PVC matches the volume name expected by backup tools like VolSync
(`<app-name>-<volume>`):

```yaml
persistence:
  data:
    forceRename: <app-name>-data
    storageClass: ceph-block
    accessMode: ReadWriteOnce
    size: 10Gi
    advancedMounts:
      main:
        main:
          - path: /data
```

### 2. Ephemeral Storage (`emptyDir`)

When running with a read-only root filesystem (`readOnlyRootFilesystem: true`), supply `emptyDir` mounts for writeable
directories like `/tmp`:

```yaml
persistence:
  tmp:
    type: emptyDir
    advancedMounts:
      main:
        main:
          - path: /tmp
```

### 3. Shared NFS Storage (Synology NAS)

Unlike Ceph block storage (which `app-template` provisions automatically), shared NFS media storage requires creating
dedicated static PV and PVC manifests in `templates/` and referencing them via `existingClaim`:

#### Values Configuration (`values.yaml`)

```yaml
persistence:
  media:
    existingClaim: <app-name>-nfs-storage
    advancedMounts:
      main:
        main:
          - path: /mnt/store
```

#### Manifest 1: Static PersistentVolume (`templates/persistent-volume.yaml`)

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: {{ .Values.<app-alias>.persistence.media.existingClaim }}
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/name: {{ .Values.<app-alias>.persistence.media.existingClaim }}
    {{- include "custom.labels" . | nindent 4 }}
spec:
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs-client
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteMany
  nfs:
    path: /volume1/Storage
    server: synology-bond{{ include "custom.domain" . }}
  mountOptions:
    - vers=4
    - minorversion=1
```

#### Manifest 2: PersistentVolumeClaim (`templates/persistent-volume-claim.yaml`)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Values.<app-alias>.persistence.media.existingClaim }}
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/name: {{ .Values.<app-alias>.persistence.media.existingClaim }}
    {{- include "custom.labels" . | nindent 4 }}
spec:
  volumeName: {{ .Values.<app-alias>.persistence.media.existingClaim }}
  storageClassName: nfs-client
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
```

---

## VolSync Tiered Backup Replication

Stateful volumes must be protected using the VolSync replication schedule pattern. Used only for ceph backed storage.

### Standard Subchart Dependency (`Chart.yaml`)

```yaml
dependencies:
  - name: volsync-target
    alias: volsync-target-data
    repository: oci://harbor.alexlebens.dev/helm-charts
    version: 3.1.0
```

### Standard Schedule Pattern (`values.yaml`)

```yaml
volsync-target-data:
  pvcTarget: <app-name>-data
  a:
    enabled: true
    schedule: '30 7 * * *'
  c:
    enabled: true
    schedule: '30 10 * * 0'
  d:
    enabled: true
    schedule: '30 9 * * 0'
```

---

## S3 Object Storage

For declarative S3 bucket provisioning via OpenTofu (`s3-bucket:`), multi-tier replication schedules, and OpenBao
credentials sync, see [storage-s3.md](storage-s3.md).
