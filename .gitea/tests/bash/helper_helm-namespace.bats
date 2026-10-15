#!/usr/bin/env bats
# Tests for .gitea/scripts/helper_helm-namespace.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup

  # Source the script under test
  source "${PROJECT_ROOT}/.gitea/scripts/helper_helm-namespace.sh"
}

# ── resolve_namespace ────────────────────────────────────────────────

@test "resolve_namespace: 'stack' maps to 'argocd'" {
  run resolve_namespace "stack"
  assert_success
  assert_output "argocd"
}

@test "resolve_namespace: 'cilium' maps to 'kube-system'" {
  run resolve_namespace "cilium"
  assert_success
  assert_output "kube-system"
}

@test "resolve_namespace: 'coredns' maps to 'kube-system'" {
  run resolve_namespace "coredns"
  assert_success
  assert_output "kube-system"
}

@test "resolve_namespace: 'metrics-server' maps to 'kube-system'" {
  run resolve_namespace "metrics-server"
  assert_success
  assert_output "kube-system"
}

@test "resolve_namespace: unknown chart falls back to chart name" {
  run resolve_namespace "grafana"
  assert_success
  assert_output "grafana"
}

@test "resolve_namespace: another unknown chart echoes itself" {
  run resolve_namespace "my-custom-chart"
  assert_success
  assert_output "my-custom-chart"
}

@test "resolve_namespace: empty string returns empty" {
  run resolve_namespace ""
  assert_success
  assert_output ""
}
