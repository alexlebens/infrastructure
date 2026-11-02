# Mail and Notifications Reference

Guidelines for integrating homelab workloads with shared mail relays and push notification services.

---

## Cluster SMTP Relay (Postfix)

For workloads requiring outbound transactional email (password resets, alerts, verification emails):

### Connection Parameters

- **SMTP Host**: `postfix.postfix.svc.cluster.local` (or `postfix.<namespace>.svc.cluster.local`)
- **Port**: `25`
- **TLS / SSL**: None (disabled internally across the pod network)
- **Authentication**: None required for internal pod IP range

### Values Configuration (`app-template`)

```yaml
controllers:
  main:
    containers:
      main:
        env:
          - name: SMTP_HOST
            value: 'postfix.postfix.svc.cluster.local'
          - name: SMTP_PORT
            value: '25'
          - name: SMTP_SECURE
            value: 'false'
          - name: SMTP_FROM
            value: '<app-name>@alexlebens.dev'
```

---

## Push Notifications (`ntfy`)

For applications supporting webhook or ntfy-based push notifications configuration must be done with secrets as it is
required to have both credentials and topics to send.
