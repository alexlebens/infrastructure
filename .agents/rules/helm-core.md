# Helm Infrastructure Standards

- Never scaffold a Helm chart from scratch; always run `mise run new-chart <name> [namespace]`.
- Always validate Helm chart changes with `mise run check-chart <name>` (or
  `--step <repos|build|lint|render|trivy|kubeconform|all>`).
- Never introduce `.trivyignore` rules to bypass misconfigurations (such as missing `resources.requests`, dropped
  capabilities, or seccomp profiles); resolve them in `values.yaml`. Only allow ignores for unavoidable container
  runtime constraints, accompanied by an explicit inline comment explaining why.
- Ensure all template filenames strictly use kebab-case resource kind naming (e.g., `config-map.yaml`, never
  `config.yaml`).
- When creating, refactoring, or standardizing Helm charts, load the `helm-chart-authoring` skill.
- Whenever adding, removing, or modifying a Helm chart or schedule, update the corresponding documentation in `docs/`
  following `docs/.agents/rules/docs-core.md`.
