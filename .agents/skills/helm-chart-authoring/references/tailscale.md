# Tailscale Ingress & Exposure Reference

Guidelines for exposing internal services securely over the private Tailscale network (tailnet) using the Tailscale
Kubernetes Operator (`tailscale-operator`).

---

## When to Use Tailscale Exposure

Use Tailscale exposure for:

- Workloads that should not be publicly routed through Cloudflare or Traefik.
- Cluster administrative dashboards and database UIs (e.g. pgAdmin, storage management).
- Internal DNS, development endpoints, and hardware management tools.

---

## Exposing a Service (`tailscale.com/expose`)

The Tailscale Kubernetes Operator dynamically provisions a Tailscale device node in your tailnet when a Service is
annotated with `tailscale.com/expose: "true"`.

### Values Configuration (`app-template`)

```yaml
service:
  main:
    type: ClusterIP
    ports:
      http:
        port: 80
        targetPort: <container-port>
  tailscale:
    enabled: true
    type: ClusterIP
    annotations:
      tailscale.com/expose: 'true'
      tailscale.com/hostname: '<app-name>'
    ports:
      http:
        port: 80
        targetPort: <container-port>
```

---

## Dedicated Tailscale Ingress

Alternatively, expose a workload using standard Kubernetes Ingress using the `tailscale` ingress class:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <app-name>-tailscale
spec:
  ingressClassName: tailscale
  rules:
    - host: <app-name>.boreal-beaufort.ts.net
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <app-name>
                port:
                  number: 80
```

---

## Tailnet Domain & TLS

- **Tailnet Domain**: All services exposed via Tailscale use the tailnet domain suffix: `.boreal-beaufort.ts.net`
- **Automatic TLS**: The Tailscale operator automatically provisions and manages valid Let's Encrypt TLS certificates
  for `<app-name>.boreal-beaufort.ts.net`.
