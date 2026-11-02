# Renovate & Image Tag Pinning Reference

Standards for container image pinning, sha256 digests, and atomic Renovate dependency tracking.

---

## Strict Tag & Digest Pinning

Never deploy images with the `latest` tag alone. Every container image in `values.yaml` must be pinned with both tag and
digest hash:

```yaml
image:
  repository: ghcr.io/org/app
  tag: 1.2.3@sha256:4eb4ec8f5030faf87c29a73d3d5a2781f28a597cf440c3ab111eb96aee550871
```

---

## Renovate `appVersion` Tracking

To ensure Renovate updates `Chart.yaml` (`appVersion`) and `values.yaml` (`tag` + digest) atomically in a single Pull
Request:

### Standard Chart.yaml Annotation

Annotate `appVersion` in `Chart.yaml` with the exact docker repository matching `values.yaml`:

```yaml
icon: https://cdn.jsdelivr.net/gh/selfhst/icons/png/<app-name>.png
# renovate: datasource=docker depName=ghcr.io/org/app
appVersion: '1.2.3'
```

### Datasource Selection Rules

- **`datasource=docker`**: Always use when `values.yaml` defines the container image for the main application. Matches
  `image.repository`.
- **`datasource=github-releases`**: Use only when the primary container image is not directly specified in `values.yaml`
  (e.g. umbrella charts or wrapped third-party charts).
- **`gitea-releases`**: Avoid unless formal Gitea Release objects are published.

---

## Resolving Image Digests

To query an image digest from a remote registry without pulling:

```bash
crane digest <image-repository>:<tag>
```
