# Helm Infrastructure Standards

- Never scaffold a Helm chart from scratch; always run `mise run new-chart <name> [namespace]`.
- Always validate Helm chart changes with `mise run check-chart <name>` (or
  `--step <repos|build|lint|render|trivy|kubeconform|all>`).
- When creating, refactoring, or standardizing Helm charts, load the `helm-chart-authoring` skill.
- Whenever adding, removing, or modifying a Helm chart or schedule, update the corresponding documentation in `docs/`
  following `docs/.agents/rules/docs-core.md`.
