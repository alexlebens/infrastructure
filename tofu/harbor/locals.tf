# ==============================================================================
# Harbor Projects
#
# Keys are the Harbor project names. Fields:
#   project_id               Existing Harbor project ID. When set, import.tf adopts the
#                            project into state. Remove after the first successful apply.
#   storage_quota_gb         Storage quota in GiB (-1 = unlimited)
#   public                   Anonymous pull access
#   vulnerability_scanning   Scan on push
#   auto_sbom_generation     Generate SBOM on push
#   registry                 Harbor registry name; makes the project a proxy cache
#   proxy_speed_kb           Proxy cache bandwidth limit (-1 = unlimited)
#   proxy_cache_local_on_not_found  Serve local copy if upstream returns not found
#
#   retention                Optional. Retention policy keeping the N most recently pushed
#                            artifacts (incl. untagged) across all repos: most_recently_pushed,
#                            schedule (Hourly, Daily, Weekly or cron), retention_id (existing policy ID,
#                            used for import; remove after first apply).
#
# Registries (endpoints/credentials) are NOT managed here; they are looked up by name.
# Retention policies are only managed for projects with a `retention` block.
# ==============================================================================
locals {
  projects = {
    "ci-images" = {
      project_id             = 78
      storage_quota_gb       = 10
      vulnerability_scanning = true
      retention = {
        retention_id         = 108
        most_recently_pushed = 1
        schedule             = "Hourly"
      }
    }
    "helm-charts" = {
      project_id             = 10
      storage_quota_gb       = 1
      vulnerability_scanning = true
      auto_sbom_generation   = true
    }
    "images" = {
      project_id       = 11
      storage_quota_gb = 40
      retention = {
        retention_id         = 42
        most_recently_pushed = 10
        schedule             = "Weekly"
      }
    }
    "library" = {
      project_id       = 1
      storage_quota_gb = 1
    }
    "models" = {
      project_id             = 45
      storage_quota_gb       = 50
      vulnerability_scanning = true
      retention = {
        retention_id         = 75
        most_recently_pushed = 2
        schedule             = "Daily"
      }
    }
    "proxy-dhi.io" = {
      project_id                     = 12
      storage_quota_gb               = 40
      vulnerability_scanning         = true
      auto_sbom_generation           = true
      registry                       = "dhi.io"
      proxy_speed_kb                 = -1
      proxy_cache_local_on_not_found = true
    }
    "proxy-gcr.io" = {
      project_id             = 4
      storage_quota_gb       = 5
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "gcr.io"
      proxy_speed_kb         = -1
    }
    "proxy-ghcr.io" = {
      project_id             = 3
      storage_quota_gb       = 80
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "ghcr.io"
      proxy_speed_kb         = -1
    }
    "proxy-hub.docker" = {
      project_id             = 2
      storage_quota_gb       = 80
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "hub.docker"
      proxy_speed_kb         = -1
    }
    "proxy-quay.io" = {
      project_id             = 6
      storage_quota_gb       = 50
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "quay.io"
      proxy_speed_kb         = -1
    }
    "proxy-registry-1.docker.io" = {
      project_id             = 8
      storage_quota_gb       = 1
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "registry-1.docker.io"
      proxy_speed_kb         = -1
    }
    "proxy-registry.k8s" = {
      project_id             = 5
      storage_quota_gb       = 5
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "registry.k8s.io"
      proxy_speed_kb         = -1
    }
  }

  registry_names = toset(compact([for _, p in local.projects : try(p.registry, "")]))
}
