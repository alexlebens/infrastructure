# Observability & Monitoring Reference

Guidelines for Blackbox probes and Prometheus metrics scraping via `app-template`.

---

## Blackbox Probes (via `common-helpers`)

Avoid creating manual `templates/probe.yaml` files. Configure Blackbox probes via `common-helpers` values:

```yaml
common-helpers:
  probe:
    internal: http://<app-name>.<namespace>:80
    external: https://<app-name>.alexlebens.dev
```

This automatically declares both internal cluster ping probes and external TLS/HTTP ingress probes.

---

## Prometheus Metrics & ServiceMonitors (via `app-template`)

Do not create manual `templates/service-monitor.yaml` manifests. In `app-template`, declare metrics ports and
`ServiceMonitor` resources entirely in `values.yaml`.

### 1. Native Application Metrics

When the application natively exposes a `/metrics` endpoint:

```yaml
service:
  main:
    ports:
      http:
        port: 80
        targetPort: 8080
      metrics:
        port: 9100

serviceMonitor:
  main:
    serviceName: <app-name>
    endpoints:
      - port: metrics
```

### Sidecar Exporter Container (e.g. Exportarr, Custom Exporter)

When an application does not natively support Prometheus metrics, run an exporter container as a sidecar under
`controllers.main.containers.metrics`:

```yaml
controllers:
  main:
    containers:
      main:
        # main container configuration...
      metrics:
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        image:
          repository: <exporter-image>
          tag: <version>@sha256:<digest>
        env:
          - name: URL
            value: http://localhost:8080
          - name: API_KEY
            valueFrom:
              secretKeyRef:
                name: <app-name>-secret
                key: api-key
        resources:
          requests:
            cpu: 1m
            memory: 10Mi

service:
  main:
    ports:
      http:
        port: 80
        targetPort: 8080
      metrics:
        port: 9100

serviceMonitor:
  main:
    serviceName: <app-name>
    endpoints:
      - port: metrics
```

### OAuth2-Proxy Metrics (SSO Sidecar)

When using Mode 2 SSO (`oauth2-proxy`), scrape the proxy metrics endpoint (`44180`):

```yaml
service:
  main:
    ports:
      metrics:
        port: 9100
      oauth-metrics:
        port: 44180

serviceMonitor:
  main:
    serviceName: <app-name>
    endpoints:
      - port: metrics
        interval: 1m
        scrapeTimeout: 10s
      - port: oauth-metrics
        interval: 3m
        scrapeTimeout: 10s
```

---

## Grafana Dashboards

For declarative Grafana Operator dashboard JSON placement, folder categories, and standard manifests, see
[grafana-dashboards.md](grafana-dashboards.md).
