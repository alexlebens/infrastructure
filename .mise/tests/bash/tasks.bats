#!/usr/bin/env bats
# Smoke tests for migrated CI/CD and check .mise tasks.

setup() {
  load 'test_helper/common-setup'
  _common_setup
}

@test "check:bash: --help prints usage" {
  run "${MISE_TASKS_DIR}/check/bash" --help
  assert_success
  assert_output --partial "Usage: mise run check:bash"
}

@test "check:docker: --help prints usage" {
  run "${MISE_TASKS_DIR}/check/docker" --help
  assert_success
  assert_output --partial "Usage: mise run check:docker"
}

@test "check:kubectl: --help prints usage" {
  run "${MISE_TASKS_DIR}/check/kubectl" --help
  assert_success
  assert_output --partial "Usage: mise run check:kubectl"
}

@test "check:python: --help prints usage" {
  run "${MISE_TASKS_DIR}/check/python" --help
  assert_success
  assert_output --partial "Usage: mise run check:python"
}

@test "check:tofu: --help prints usage" {
  run "${MISE_TASKS_DIR}/check/tofu" --help
  assert_success
  assert_output --partial "Usage: mise run check:tofu"
}

@test "check:workflows: --help prints usage" {
  run "${MISE_TASKS_DIR}/check/workflows" --help
  assert_success
  assert_output --partial "Usage: mise run check:workflows"
}

@test "tofu:fetch-secrets: --help prints usage" {
  run "${MISE_TASKS_DIR}/tofu/fetch-secrets" --help
  assert_success
  assert_output --partial "Usage: mise run tofu:fetch-secrets"
}

@test "tofu:plan: --help prints usage" {
  run "${MISE_TASKS_DIR}/tofu/plan" --help
  assert_success
  assert_output --partial "Usage: mise run tofu:plan"
}

@test "host:deploy-compose: --help prints usage" {
  run "${MISE_TASKS_DIR}/host/deploy-compose" --help
  assert_success
  assert_output --partial "Usage: mise run host:deploy-compose"
}

@test "host:update-periphery: --help prints usage" {
  run "${MISE_TASKS_DIR}/host/update-periphery" --help
  assert_success
  assert_output --partial "Usage: mise run host:update-periphery"
}

@test "gitea:argocd-diff: --help prints usage" {
  run "${MISE_TASKS_DIR}/gitea/argocd-diff" --help
  assert_success
  assert_output --partial "Usage: mise run gitea:argocd-diff"
}

@test "gitea:detect-docker: --help prints usage" {
  run "${MISE_TASKS_DIR}/gitea/detect-docker" --help
  assert_success
  assert_output --partial "Usage: mise run gitea:detect-docker"
}

@test "gitea:detect-helm: --help prints usage" {
  run "${MISE_TASKS_DIR}/gitea/detect-helm" --help
  assert_success
  assert_output --partial "Usage: mise run gitea:detect-helm"
}

@test "gitea:detect-manifest-mode: --help prints usage" {
  run "${MISE_TASKS_DIR}/gitea/detect-manifest-mode" --help
  assert_success
  assert_output --partial "Usage: mise run gitea:detect-manifest-mode"
}

@test "gitea:detect-manifests: --help prints usage" {
  run "${MISE_TASKS_DIR}/gitea/detect-manifests" --help
  assert_success
  assert_output --partial "Usage: mise run gitea:detect-manifests"
}

@test "gitea:detect-periphery: --help prints usage" {
  run "${MISE_TASKS_DIR}/gitea/detect-periphery" --help
  assert_success
  assert_output --partial "Usage: mise run gitea:detect-periphery"
}

@test "gitea:harbor-warm: --help prints usage" {
  run "${MISE_TASKS_DIR}/gitea/harbor-warm" --help
  assert_success
  assert_output --partial "Usage: mise run gitea:harbor-warm"
}

@test "gitea:prepare-manifest-pr: --help prints usage" {
  run "${MISE_TASKS_DIR}/gitea/prepare-manifest-pr" --help
  assert_success
  assert_output --partial "Usage: mise run gitea:prepare-manifest-pr"
}

@test "gitea:release-models: --help prints usage" {
  run "${MISE_TASKS_DIR}/gitea/release-models" --help
  assert_success
  assert_output --partial "Usage: mise run gitea:release-models"
}
