#!/usr/bin/env bats
# Tests for .gitea/scripts/detect-periphery-changes.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup

  TEST_OUTPUT_FILE="${BATS_TEST_TMPDIR}/github_output"
  : > "${TEST_OUTPUT_FILE}"
  export GITHUB_OUTPUT="${TEST_OUTPUT_FILE}"

  MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"

  cd "${PROJECT_ROOT}"
}

_mock_git_diff() {
  local diff_output="$1"
  cat > "${MOCK_BIN}/git" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "diff" ]]; then
  printf "%s\n" "${diff_output}"
fi
EOF
  chmod +x "${MOCK_BIN}/git"
}

@test "detect-periphery-changes: push to hosts/ps10rp/komodo-periphery (e.g. Tailscale bump) enables only ps10rp" {
  _mock_git_diff "hosts/ps08rp/blocky/compose.yaml
hosts/ps09rp/blocky/compose.yaml
hosts/ps10rp/komodo-periphery/compose.yaml"

  run "${PROJECT_ROOT}/.gitea/scripts/detect-periphery-changes.sh" \
    --event-name "push"
  assert_success

  run cat "${TEST_OUTPUT_FILE}"
  assert_line "systemd=false"
  assert_line 'compose-hosts=["ps10rp"]'
}

@test "detect-periphery-changes: push to clusters/cl01tl/helm/komodo enables systemd hosts" {
  _mock_git_diff "clusters/cl01tl/helm/komodo/Chart.yaml"

  run "${PROJECT_ROOT}/.gitea/scripts/detect-periphery-changes.sh" \
    --event-name "push"
  assert_success

  run cat "${TEST_OUTPUT_FILE}"
  assert_line "systemd=true"
  assert_line "compose-hosts=[]"
}

@test "detect-periphery-changes: push to deploy-remote-compose.sh discovers all compose periphery hosts" {
  _mock_git_diff ".gitea/scripts/deploy-remote-compose.sh"

  run "${PROJECT_ROOT}/.gitea/scripts/detect-periphery-changes.sh" \
    --event-name "push"
  assert_success

  run cat "${TEST_OUTPUT_FILE}"
  assert_line "systemd=false"
  assert_line 'compose-hosts=["ps02sn","ps10rp"]'
}
