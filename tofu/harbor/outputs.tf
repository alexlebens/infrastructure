output "projects" {
  description = "Managed Harbor projects"
  value = {
    for k, v in harbor_project.this : k => {
      id         = v.id
      project_id = v.project_id
    }
  }
}
