#!/usr/bin/env bats
# Tests for .gitea/scripts/detect-manifest-mode.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup

  WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${WORK}"
  cd "${WORK}"
}

# Creates a bare "origin" with a `manifests` branch and clones it into
# ${WORK}/infrastructure-manifests.
_init_manifest_clone() {
  local origin="${BATS_TEST_TMPDIR}/origin.git"
  local seed="${BATS_TEST_TMPDIR}/seed"
  git init -q --bare "${origin}"
  git init -q "${seed}"
  git -C "${seed}" commit -q --allow-empty -m "init"
  git -C "${seed}" branch -M manifests
  git -C "${seed}" remote add origin "${origin}"
  git -C "${seed}" push -q origin manifests
  if [ "${1:-}" = "with-existing-branch" ]; then
    git -C "${seed}" checkout -q -b auto/update-manifests
    git -C "${seed}" commit -q --allow-empty -m "previous automated update"
    git -C "${seed}" push -q origin auto/update-manifests
  fi
  git clone -q --branch manifests "${origin}" "${WORK}/infrastructure-manifests"
}

@test "detect-manifest-mode: schedule renders everything" {
  run "${SCRIPTS_DIR}/detect-manifest-mode.sh" --event-name schedule
  assert_success
  assert_equal "$(_output_value render-all)" "true"
  assert_equal "$(_output_value is-automerge)" "false"
  assert_equal "$(_output_value diff-target)" ""
  assert_equal "$(_output_value trigger-info)" "Triggered by: schedule"
  assert_equal "$(_output_value ntfy-title)" "Manifests Rendered (schedule)"
  assert_equal "$(_output_value branch-name)" "auto/update-manifests"
}

@test "detect-manifest-mode: workflow_dispatch renders everything" {
  run "${SCRIPTS_DIR}/detect-manifest-mode.sh" --event-name workflow_dispatch
  assert_success
  assert_equal "$(_output_value render-all)" "true"
  assert_equal "$(_output_value ntfy-title)" "Manifests Rendered (workflow_dispatch)"
}

@test "detect-manifest-mode: merged PR renders only the last commit" {
  run "${SCRIPTS_DIR}/detect-manifest-mode.sh" --event-name pull_request \
    --pr-title "feat(grafana): bump" --pr-number 42 --is-automerge false
  assert_success
  assert_output --partial "Mode: PR Merged (Standard)"
  assert_equal "$(_output_value render-all)" "false"
  assert_equal "$(_output_value is-automerge)" "false"
  assert_equal "$(_output_value diff-target)" "HEAD^..HEAD"
  assert_equal "$(_output_value trigger-info)" "Source PR: feat(grafana): bump"
  assert_equal "$(_output_value ntfy-title)" "feat(grafana): bump"
  assert_equal "$(_output_value pr-title)" "feat(grafana): bump"
  assert_equal "$(_output_value branch-name)" "auto/update-manifests"
}

@test "detect-manifest-mode: automerge PR uses a dedicated per-PR branch" {
  run "${SCRIPTS_DIR}/detect-manifest-mode.sh" --event-name pull_request \
    --pr-title "chore(deps): update" --pr-number 77 --is-automerge true
  assert_success
  assert_output --partial "Mode: PR Merged (Automerge)"
  assert_equal "$(_output_value is-automerge)" "true"
  assert_equal "$(_output_value branch-name)" "auto/update-manifests-automerge-77"
}

@test "detect-manifest-mode: is-automerge is ignored for non-PR events" {
  run "${SCRIPTS_DIR}/detect-manifest-mode.sh" --event-name schedule --is-automerge true --pr-number 5
  assert_success
  assert_equal "$(_output_value is-automerge)" "false"
  assert_equal "$(_output_value branch-name)" "auto/update-manifests"
}

@test "detect-manifest-mode: reads configuration from environment variables" {
  EVENT_NAME=pull_request PR_TITLE="env title" PR_NUMBER=9 IS_AUTOMERGE=true \
    BRANCH_NAME_BASE="custom/base" \
    run "${SCRIPTS_DIR}/detect-manifest-mode.sh"
  assert_success
  assert_equal "$(_output_value branch-name)" "custom/base-automerge-9"
  assert_equal "$(_output_value pr-title)" "env title"
}

@test "detect-manifest-mode: missing manifest dir warns but still emits outputs" {
  run "${SCRIPTS_DIR}/detect-manifest-mode.sh" --event-name schedule --manifest-dir nope
  assert_success
  assert_output --partial "Warning: Manifest directory 'nope' not found"
  assert_equal "$(_output_value branch-name)" "auto/update-manifests"
}

@test "detect-manifest-mode: creates new branch when it does not exist on origin" {
  _init_manifest_clone

  run "${SCRIPTS_DIR}/detect-manifest-mode.sh" --event-name schedule
  assert_success
  assert_output --partial "does not exist, creating"
  run git -C infrastructure-manifests rev-parse --abbrev-ref HEAD
  assert_output "auto/update-manifests"
  run git -C infrastructure-manifests config user.name
  assert_output "gitea-bot"
}

@test "detect-manifest-mode: checks out and rebases existing remote branch" {
  _init_manifest_clone with-existing-branch

  run "${SCRIPTS_DIR}/detect-manifest-mode.sh" --event-name schedule
  assert_success
  assert_output --partial "exists, pulling changes"
  run git -C infrastructure-manifests rev-parse --abbrev-ref HEAD
  assert_output "auto/update-manifests"
  run git -C infrastructure-manifests log -1 --format=%s
  assert_output "previous automated update"
}

@test "detect-manifest-mode: automerge creates per-PR branch in manifest clone" {
  _init_manifest_clone with-existing-branch

  run "${SCRIPTS_DIR}/detect-manifest-mode.sh" --event-name pull_request --pr-number 12 --is-automerge true
  assert_success
  run git -C infrastructure-manifests rev-parse --abbrev-ref HEAD
  assert_output "auto/update-manifests-automerge-12"
  # Branches off the base (manifests), not the shared update branch
  run git -C infrastructure-manifests log -1 --format=%s
  assert_output "init"
}

@test "detect-manifest-mode: unknown argument fails" {
  run "${SCRIPTS_DIR}/detect-manifest-mode.sh" --nope
  assert_failure
  assert_output --partial "Unknown argument"
}
