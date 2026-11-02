# HTTPRoute & Gateway API Reference

Traffic ingress in `cl01tl` is managed via Traefik utilizing the Kubernetes Gateway API (`HTTPRoute` resources).

---

## Declarative Route Configuration (`app-template`)

In `bjw-s/app-template` v5 charts, routes are defined under `route.main` in `values.yaml`:

```yaml
route:
  main:
    kind: HTTPRoute
    annotations:
      # Homepage dashboard annotations must be defined here.
      # See references/homepage.md for required fields, icons, and groups.
    parentRefs:
      - name: traefik-gateway
        namespace: traefik
    hostnames:
      - <app-name>.alexlebens.dev
    rules:
      - backendRefs:
          - name: <app-name>
            port: 80
        matches:
          - path:
              type: PathPrefix
              value: /
```

> **Note on Homepage Discovery**: Always consult [references/homepage.md](homepage.md) for full annotation options, icon
> conventions, and the approved 11-category group taxonomy.

---

## Authentication Delegation (OAuth2-Proxy)

If the workload uses an `oauth2-proxy` sidecar container (see [references/auth-sso.md](auth-sso.md)), the `HTTPRoute`
backendRefs must target the `oauth` port (`4180`) instead of the application container port:

```yaml
rules:
  - backendRefs:
      - name: <app-name>
        port: 4180
    matches:
      - path:
          type: PathPrefix
          value: /
```

---

## Dedicated Manifest Format (`templates/http-route.yaml`)

When writing standalone charts without `app-template`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app name>
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/name: <app name>
    {{- include "custom.labels" . | nindent 4 }}
  annotations:
    # See references/homepage.md for details
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: traefik-gateway
      namespace: traefik
  hostnames:
    - {{ .Release.Name }}-temporal{{ include "custom.domain" . }}
  rules:
    - backendRefs:
        - group: ""
          kind: Service
          name: <app name>
          port: 80
          weight: 1
      matches:
        - path:
            type: PathPrefix
            value: /
```
