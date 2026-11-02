# Homepage Dashboard Annotations Reference

Homelab applications are automatically discovered and populated on the central Homepage dashboard via Kubernetes
resource annotations.

Official configuration can be found [here](https://gethomepage.dev/).

---

## Governance & Golden Rules

- **Avoid Static Tiles**: When necessary define static dashboard tiles in
  `infrastructure/clusters/cl01tl/helm/homepage/values.yaml`. All services where possible must be dynamically discovered
  via annotations.
- **Placement**: Place Homepage annotations on the Gateway API `HTTPRoute` resource (`route.main.annotations` in
  `app-template` or `metadata.annotations` on `templates/http-route.yaml`).
- **Order**: Weight is used for order in "50" increments from 50 to 1000. Avoid overlapping, append to end if there are
  no gaps.
- **Icon**: Check [selfh.st](https://selfh.st/icons/) for the icon existance, otherwise fallback to material icons.

---

## Standard Annotations Schema

Replace content in arrows with appropriate configuration. Add additional annotations when necessary for items such as
href or widget.

```yaml
gethomepage.dev/enabled: 'true'
gethomepage.dev/name: '<Generalized purpose of application>'
gethomepage.dev/description: '<Name of application>'
gethomepage.dev/group: '<Approved Group>'
gethomepage.dev/icon: 'sh-<app-name>.webp'
gethomepage.dev/weight: '50'
gethomepage.dev/siteMonitor: 'http://<app-name>.<namespace>:80'
gethomepage.dev/pod-selector: ''
```

### Key Field Specifications

| Annotation                     | Description                                                                    | Example                                    |
| :----------------------------- | :----------------------------------------------------------------------------- | :----------------------------------------- |
| `gethomepage.dev/enabled`      | Enables discovery. Must be `"true"`.                                           | `"true"`                                   |
| `gethomepage.dev/name`         | Human-readable title shown on the tile.                                        | `"Actual Budget"`                          |
| `gethomepage.dev/description`  | Subtitle explaining the application's role.                                    | `"Personal finance & envelope budgeting"`  |
| `gethomepage.dev/group`        | Destination dashboard group column.                                            | `"Knowledge"`                              |
| `gethomepage.dev/icon`         | Icon from [selfh.st/icons](https://selfh.st/icons).                            | `"sh-actual-budget.webp"`                  |
| `gethomepage.dev/weight`       | Integer weight controlling order within the group (lower = higher up).         | `"100"`                                    |
| `gethomepage.dev/siteMonitor`  | Internal cluster HTTP URL for latency & status ping dot.                       | `"http://actual.actual:80"`                |
| `gethomepage.dev/pod-selector` | Empty string to prevent automatic container metric scraping unless configured. | `""`                                       |
| `gethomepage.dev/href`         | _(Optional)_ Override link target if anchor or subpath is needed.              | `"https://bentopdf.alexlebens.dev/#tools"` |

---

## Approved Group Taxonomy

Every application must belong to exactly one of the standard functional groups:

- `Applications`: End-user consumer applications.
- `Tools`: Productivity utilities and converter services (e.g. BentoPDF, CyberChef).
- `Knowledge`: Wikis, documentation, finance, and personal databases (e.g. Actual, Paperless).
- `Media`: Media streaming and libraries (e.g. Jellyfin, Audiobookshelf).
- `Content`: Downloader and media management stacks (e.g. Radarr, Sonarr, Bazarr).
- `Automation`: Workflow engines and cron automation (e.g. Home Assistant, n8n).
- `Monitoring`: Cluster telemetry, metrics, and alerting (e.g. Grafana, VictoriaMetrics).
- `Services`: Shared platform utilities and microservices.
- `Storage`: Storage backends, Ceph, and S3 file explorers.
- `Hardware`: Physical node interfaces, IPMI, and UPS monitors.
- `Background`: Headless system daemons and workers.
