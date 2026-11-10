# ==============================================================================
# Declarative imports for pre-existing Harbor projects
#
# Generated from `project_id` in locals.tf. After the first successful apply the
# projects live in state and this file (and the project_id fields) can be removed.
#
# To adopt a project created later in the Harbor UI, either add it to locals.tf with
# its `project_id`, or run: mise run app:tofu-import-harbor-project <name>
# ==============================================================================
import {
  for_each = { for k, v in local.projects : k => v if try(v.project_id, null) != null }
  to       = harbor_project.this[each.key]
  id       = "/projects/${each.value.project_id}"
}

import {
  for_each = { for k, v in local.projects : k => v.retention if try(v.retention.retention_id, null) != null }
  to       = harbor_retention_policy.this[each.key]
  id       = "/retentions/${each.value.retention_id}"
}
