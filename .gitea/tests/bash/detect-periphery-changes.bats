#!/usr/bin/env bats
# Tests for .gitea/scripts/detect-periphery-changes.sh
#
# Uses an isolated fixture repository so results do not depend on which hosts
# currently exist in the real repository.

setup() {
  load 'test_helper/common-setup'
  _common_setup
  _init_fixture_repo

  _fixture_write "hosts/ps02sn/komodo-periphery/compose.yaml" "services: {}"
  _fixture_write "hosts/ps10rp/komodo-periphery/compose.yaml" "services: {}"
  _fixture_write "hosts/pd05wd/komodo-periphery/compose.yaml" "services: {}"
  _fixture_write "hosts/ps08rp/blocky/compose.yaml" "services: {}"
  _fixture_write "clusters/cl01tl/helm/komodo/Chart.yaml" "name: komodo"
  _fixture_write "clusters/cl01tl/helm/other/Chart.yaml" "name: other"
  _fixture_commit "baseline"
  BASE_SHA="$(git rev-parse HEAD)"
}

_run_detect() {
  run "${SCRIPTS_DIR}/detect-periphery-changes.sh" --event-name push --event-before "${BASE_SHA}" "$@"
}

@test "detect-periphery-changes: komodo-periphery compose change enables only that host" {
  _fixture_write "hosts/ps08rp/blocky/compose.yaml" "changed"
  _fixture_write "hosts/ps10rp/komodo-periphery/compose.yaml" "changed"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value systemd)" "false"
  assert_equal "$(_output_value compose-hosts)" '["ps10rp"]'
}

@test "detect-periphery-changes: multiple periphery hosts are sorted and de-duplicated" {
  _fixture_write "hosts/ps10rp/komodo-periphery/compose.yaml" "changed"
  _fixture_write "hosts/ps10rp/komodo-periphery/.env.example" "X=1"
  _fixture_write "hosts/ps02sn/komodo-periphery/compose.yaml" "changed"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value compose-hosts)" '["ps02sn","ps10rp"]'
}

@test "detect-periphery-changes: komodo chart change enables systemd hosts only" {
  _fixture_write "clusters/cl01tl/helm/komodo/values.yaml" "x: 1"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value systemd)" "true"
  assert_equal "$(_output_value compose-hosts)" "[]"
}

@test "detect-periphery-changes: update-remote-periphery-systemd.sh change enables systemd hosts" {
  _fixture_write ".gitea/scripts/update-remote-periphery-systemd.sh" "#!/bin/bash"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value systemd)" "true"
  assert_equal "$(_output_value compose-hosts)" "[]"
}

@test "detect-periphery-changes: deploy-remote-compose.sh change discovers all periphery hosts" {
  _fixture_write ".gitea/scripts/deploy-remote-compose.sh" "#!/bin/bash"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value systemd)" "false"
  assert_equal "$(_output_value compose-hosts)" '["pd05wd","ps02sn","ps10rp"]'
}

@test "detect-periphery-changes: workflow change enables systemd and all compose hosts" {
  _fixture_write ".gitea/workflows/update-komodo-periphery.yaml" "name: x"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value systemd)" "true"
  assert_equal "$(_output_value compose-hosts)" '["pd05wd","ps02sn","ps10rp"]'
}

@test "detect-periphery-changes: unrelated chart change enables nothing" {
  _fixture_write "clusters/cl01tl/helm/other/values.yaml" "x: 1"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value systemd)" "false"
  assert_equal "$(_output_value compose-hosts)" "[]"
}

@test "detect-periphery-changes: removed periphery directory is not deployed" {
  git rm -q -r hosts/pd05wd/komodo-periphery
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value compose-hosts)" "[]"
}

@test "detect-periphery-changes: lookalike paths do not trigger systemd updates" {
  _fixture_write "clusters/cl01tl/helm/komodo-extra/Chart.yaml" "name: komodo-extra"
  _fixture_write ".gitea/scripts/update-remote-periphery-systemd.sh.bak" "x"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value systemd)" "false"
}

@test "detect-periphery-changes: unknown argument fails" {
  run "${SCRIPTS_DIR}/detect-periphery-changes.sh" --nope
  assert_failure
  assert_output --partial "Unknown argument"
}
