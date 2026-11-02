# Authentication & Single Sign-On (SSO) Reference

All workloads that can, either through oidc or oauth-proxy, must integrate with Pocket ID using the `pocket-id-client`
subchart dependency (`oci://harbor.alexlebens.dev/helm-charts/pocket-id-client`).

---

# SSO Reference (`pocket-id-client`)

Add to `Chart.yaml` and run `helm dependency update`:

```yaml
dependencies:
  - name: pocket-id-client
    repository: oci://harbor.alexlebens.dev/helm-charts
    version: 0.4.4
```

---

## Mode 1: Native OIDC

Used when the upstream application natively supports OpenID Connect (e.g. Immich, Audiobookshelf, Actual Budget,
Grafana, Gitea).

### Values Configuration (`values.yaml`)

- Check upstream for the apps's configured callback.
- Remove allowedUserGroups if only use group as its the default.
- Remove clientID to generate a deterministic UUID from release name + namespace when not grandfathering in.

```yaml
pocket-id-client:
  mode: oidc
  client:
    displayName: '<App Title>'
    description: '<App Description>'
    callbackUrls:
      - https://<app-name>.alexlebens.dev/api/oauth/callback
    allowedUserGroups:
      - name: user
        namespace: pocket-id-operator
    clientID: ''
```

### Application Connection

The subchart outputs a Secret `<release-name>-oidc-secret` containing:

- `clientSecret`: Generated client secret. Pass the discovery URL and credentials into the app:
- Discovery URL: `https://auth.alexlebens.dev/.well-known/openid-configuration`
- Client ID: UUID from CRD
- Client Secret: Reference from secret `<release-name>-oidc-secret` (key `clientSecret`)

---

## Mode 2: OAuth2-Proxy Sidecar (app-template)

Used when the application has no native authentication support or only legacy basic auth. In `app-template`, configure
the sidecar container, ports, routing, and mounts entirely in `values.yaml`:

### 1. Pocket ID Client Configuration

```yaml
pocket-id-client:
  mode: oauth
  client:
    displayName: '<App Title>'
    description: '<App Description>'
    allowedUserGroups:
      - name: user
        namespace: pocket-id-operator
```

### 2. Sidecar Container (`controllers.main.containers.oauth`)

```yaml
controllers:
  main:
    containers:
      oauth:
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        image:
          repository: quay.io/oauth2-proxy/oauth2-proxy
          tag: v7.15.5@sha256:8498b0d0ef0a7b29686414000a08aee467f02d0299c9ed1e006a8f33fc017916
        envFrom:
          - secretRef:
              name: <app-name>-oauth-proxy
        env:
          - name: OAUTH2_PROXY_HTTP_ADDRESS
            value: 0.0.0.0:4180
          - name: OAUTH2_PROXY_METRICS_ADDRESS
            value: 0.0.0.0:44180
          - name: OAUTH2_PROXY_UPSTREAMS
            value: http://localhost:<container-port>
          - name: OAUTH2_PROXY_PROVIDER
            value: oidc
          - name: OAUTH2_PROXY_CODE_CHALLENGE_METHOD
            value: 'S256'
          - name: OAUTH2_PROXY_SKIP_PROVIDER_BUTTON
            value: 'true'
          - name: OAUTH2_PROXY_EMAIL_DOMAINS
            value: '*'
        resources:
          requests:
            cpu: 1m
            memory: 10Mi
        probes:
          liveness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /ping
                port: 4180
          readiness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /ready
                port: 4180
```

### 3. Service Ports, ServiceMonitor & Route Configuration

Point the Gateway `HTTPRoute` backend to the `oauth` sidecar port (`4180`) rather than directly to the app port. Merge
the following into values:

```yaml
service:
  main:
    ports:
      http:
        port: 80
        targetPort: <container-port>
      oauth:
        port: 4180
      oauth-metrics:
        port: 44180

serviceMonitor:
  main:
    serviceName: <app-name>
    endpoints:
      - port: oauth-metrics

route:
  main:
    rules:
      - backendRefs:
          - name: <app-name>
            port: 4180
        matches:
          - path:
              type: PathPrefix
              value: /

persistence:
  tmp:
    type: emptyDir
    advancedMounts:
      main:
        main:
          - path: /tmp
        oauth:
          - path: /tmp
```
