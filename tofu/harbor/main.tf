data "harbor_registry" "this" {
  for_each = local.registry_names
  name     = each.key
}

resource "harbor_project" "this" {
  for_each = local.projects

  name                   = each.key
  public                 = try(each.value.public, true)
  storage_quota          = try(each.value.storage_quota_gb, -1)
  vulnerability_scanning = try(each.value.vulnerability_scanning, false)
  auto_sbom_generation   = try(each.value.auto_sbom_generation, false)

  registry_id                    = try(data.harbor_registry.this[each.value.registry].registry_id, null)
  proxy_speed_kb                 = try(each.value.proxy_speed_kb, null)
  proxy_cache_local_on_not_found = try(each.value.proxy_cache_local_on_not_found, null)

  # Never delete repositories/artifacts through tofu.
  force_destroy = false
}

resource "harbor_retention_policy" "this" {
  for_each = { for k, v in local.projects : k => v.retention if try(v.retention, null) != null }

  scope    = harbor_project.this[each.key].id
  schedule = each.value.schedule

  rule {
    most_recently_pushed = each.value.most_recently_pushed
    untagged_artifacts   = true
    repo_matching        = "**"
    tag_matching         = "**"
  }
}
