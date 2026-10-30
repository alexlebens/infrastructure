#!/usr/bin/env bats
# Tests for .gitea/scripts/pr-prepare-manifest-content.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup
  cd "${BATS_TEST_TMPDIR}"
}

@test "pr-prepare-manifest-content: standard update title, commit message and body" {
  run "${SCRIPTS_DIR}/pr-prepare-manifest-content.sh" \
    --event-name pull_request --actor alice --sha 0123456789abcdef \
    --ref-name main --changed-charts "grafana,loki"
  assert_success
  assert_equal "$(_output_value title)" "Automated Manifest Update"
  assert_equal "$(_output_value commit-msg)" "chore: Update manifests after change"

  run _output_multiline body
  assert_line --partial '**Trigger**: `pull_request` by `@alice`'
  assert_line --partial '**Commit**: `0123456` (on `main`)'
  assert_line --partial '**Charts Updated**: `grafana,loki`'
  refute_output --partial "expected to be automerged"
}

@test "pr-prepare-manifest-content: automerge variant adds automerge note" {
  run "${SCRIPTS_DIR}/pr-prepare-manifest-content.sh" --is-automerge true --sha abcdef0123
  assert_success
  assert_equal "$(_output_value title)" "Automated Manifest Update - Automerge"
  assert_equal "$(_output_value commit-msg)" "chore: Update manifests after automerge"
  run _output_multiline body
  assert_output --partial "_This PR is expected to be automerged._"
}

@test "pr-prepare-manifest-content: update-comment contains trigger details" {
  run "${SCRIPTS_DIR}/pr-prepare-manifest-content.sh" --actor bob --sha 1111111222 --changed-charts "a"
  assert_success
  run _output_multiline update-comment
  assert_line --regexp '^### Update Details \([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC\)$'
  assert_line --partial '`@bob`'
  assert_line --partial '`1111111`'
}

@test "pr-prepare-manifest-content: defaults come from GITHUB_* environment variables" {
  GITHUB_EVENT_NAME=schedule GITHUB_ACTOR=carol GITHUB_SHA=fedcba9876 GITHUB_REF_NAME=release \
    run "${SCRIPTS_DIR}/pr-prepare-manifest-content.sh"
  assert_success
  run _output_multiline body
  assert_line --partial '`schedule` by `@carol`'
  assert_line --partial '`fedcba9` (on `release`)'
}

@test "pr-prepare-manifest-content: discovers changed charts from manifest repo git status" {
  local m="${BATS_TEST_TMPDIR}/manifests"
  git init -q "${m}"
  mkdir -p "${m}/clusters/cl01tl/manifests/zeta" "${m}/clusters/cl01tl/manifests/alpha" "${m}/clusters/other/manifests/beta"
  echo a > "${m}/clusters/cl01tl/manifests/zeta/Deployment-zeta.yaml"
  echo a > "${m}/clusters/cl01tl/manifests/zeta/Service-zeta.yaml"
  echo a > "${m}/clusters/cl01tl/manifests/alpha/ConfigMap-alpha.yaml"
  echo a > "${m}/clusters/other/manifests/beta/ConfigMap-beta.yaml"

  run "${SCRIPTS_DIR}/pr-prepare-manifest-content.sh" --manifest-dir "${m}"
  assert_success
  run _output_multiline body
  assert_line --partial '**Charts Updated**: `alpha,zeta`'
}

@test "pr-prepare-manifest-content: explicit --changed-charts wins over git discovery" {
  local m="${BATS_TEST_TMPDIR}/manifests"
  git init -q "${m}"
  mkdir -p "${m}/clusters/cl01tl/manifests/zeta"
  echo a > "${m}/clusters/cl01tl/manifests/zeta/x.yaml"

  run "${SCRIPTS_DIR}/pr-prepare-manifest-content.sh" --manifest-dir "${m}" --changed-charts explicit
  assert_success
  run _output_multiline body
  assert_line --partial '**Charts Updated**: `explicit`'
}

@test "pr-prepare-manifest-content: unknown argument fails" {
  run "${SCRIPTS_DIR}/pr-prepare-manifest-content.sh" --nope
  assert_failure
  assert_output --partial "Unknown argument"
}
