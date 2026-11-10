# ==============================================================================
# Harbor Projects
#
# Keys are the Harbor project names. Fields:
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
#                            schedule (Hourly, Daily, Weekly or cron).
#
# To adopt a project created in the Harbor UI, add it here and temporarily add an import block
# (to = harbor_project.this["<name>"], id = "/projects/<project_id>"; retention policies use
# harbor_retention_policy.this["<name>"] with id "/retentions/<retention_id>"), or run `tofu import`.
#
# Registries (endpoints/credentials) are NOT managed here; they are looked up by name.
# Retention policies are only managed for projects with a `retention` block.
# ==============================================================================
locals {
  projects = {
    "ci-images" = {
      storage_quota_gb       = 10
      vulnerability_scanning = true
      retention = {
        most_recently_pushed = 1
        schedule             = "Hourly"
      }
    }
    "helm-charts" = {
      storage_quota_gb       = 1
      vulnerability_scanning = true
      auto_sbom_generation   = true
    }
    "images" = {
      storage_quota_gb = 40
      retention = {
        most_recently_pushed = 10
        schedule             = "Weekly"
      }
    }
    "library" = {
      storage_quota_gb = 1
    }
    "models" = {
      storage_quota_gb       = 50
      vulnerability_scanning = true
      retention = {
        most_recently_pushed = 2
        schedule             = "Daily"
      }
    }
    "proxy-dhi.io" = {
      storage_quota_gb               = 40
      vulnerability_scanning         = true
      auto_sbom_generation           = true
      registry                       = "dhi.io"
      proxy_speed_kb                 = -1
      proxy_cache_local_on_not_found = true
    }
    "proxy-gcr.io" = {
      storage_quota_gb       = 5
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "gcr.io"
      proxy_speed_kb         = -1
    }
    "proxy-ghcr.io" = {
      storage_quota_gb       = 80
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "ghcr.io"
      proxy_speed_kb         = -1
    }
    "proxy-hub.docker" = {
      storage_quota_gb       = 80
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "hub.docker"
      proxy_speed_kb         = -1
    }
    "proxy-quay.io" = {
      storage_quota_gb       = 50
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "quay.io"
      proxy_speed_kb         = -1
    }
    "proxy-registry-1.docker.io" = {
      storage_quota_gb       = 1
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "registry-1.docker.io"
      proxy_speed_kb         = -1
    }
    "proxy-registry.k8s" = {
      storage_quota_gb       = 5
      vulnerability_scanning = true
      auto_sbom_generation   = true
      registry               = "registry.k8s.io"
      proxy_speed_kb         = -1
    }
  }

  registry_names = toset(compact([for _, p in local.projects : try(p.registry, "")]))
}
