#!/usr/bin/env bats
# Unit tests for host:deploy-compose, host:update-periphery, and their remote SSH scripts.

setup() {
  load 'test_helper/common-setup'
  _common_setup
}

@test "host:deploy-compose validates required arguments" {
  run "${MISE_TASKS_DIR}/host/deploy-compose"
  assert_failure
  assert_output --partial "--host (or TARGET_HOST) is required"

  run "${MISE_TASKS_DIR}/host/deploy-compose" --host ps02sn
  assert_failure
  assert_output --partial "--repo-dir (or REPO_DIR) is required"

  run "${MISE_TASKS_DIR}/host/deploy-compose" --host ps02sn --repo-dir /srv/repo
  assert_failure
  assert_output --partial "--service-path (or SERVICE_PATH) is required"
}

@test "host:deploy-compose streams remote-deploy-compose.sh over ssh" {
  local ssh_args_file="${BATS_TEST_TMPDIR}/ssh_args"
  local ssh_stdin_file="${BATS_TEST_TMPDIR}/ssh_stdin"
  _stub ssh "printf '%s\n' \"\$*\" > '${ssh_args_file}'; cat > '${ssh_stdin_file}'"

  run "${MISE_TASKS_DIR}/host/deploy-compose" \
    --host ps10rp \
    --repo-dir /opt/infra \
    --service-path hosts/ps10rp/komodo-periphery \
    --user deploy \
    --port 2222
  assert_success
  assert_output --partial "Successfully deployed hosts/ps10rp/komodo-periphery on ps10rp"

  local args
  args="$(cat "${ssh_args_file}")"
  assert_equal "${args}" "-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=30 -p 2222 deploy@ps10rp bash -s -- hosts/ps10rp/komodo-periphery /opt/infra"
  cmp -s "${ssh_stdin_file}" "${MISE_LIB_DIR}/remote-deploy-compose.sh"
}

@test "host:update-periphery validates required host and streams remote script over ssh" {
  run "${MISE_TASKS_DIR}/host/update-periphery"
  assert_failure
  assert_output --partial "--host (or TARGET_HOST) is required"

  local ssh_args_file="${BATS_TEST_TMPDIR}/ssh_args"
  local ssh_stdin_file="${BATS_TEST_TMPDIR}/ssh_stdin"
  _stub ssh "printf '%s\n' \"\$*\" > '${ssh_args_file}'; cat > '${ssh_stdin_file}'"

  run "${MISE_TASKS_DIR}/host/update-periphery" \
    --host pd04vm \
    --user root \
    --port 2200 \
    --core-address https://komodo.example.test
  assert_success
  assert_output --partial "Successfully updated Komodo Periphery on pd04vm"

  local args
  args="$(cat "${ssh_args_file}")"
  assert_equal "${args}" "-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=30 -p 2200 root@pd04vm bash -s -- https://komodo.example.test"
  cmp -s "${ssh_stdin_file}" "${MISE_LIB_DIR}/remote-update-periphery.sh"
}

@test "remote-deploy-compose: fails cleanly when target repo or service dir is missing" {
  export KEEP_PATH=1 INITIAL_SLEEP=0 POLL_SLEEP=0 MAX_WAIT=0 POST_UP_SLEEP=0

  run "${MISE_LIB_DIR}/remote-deploy-compose.sh" "hosts/ps10rp/svc" "${BATS_TEST_TMPDIR}/missing-repo"
  assert_failure
  assert_output --partial "Target repository directory '${BATS_TEST_TMPDIR}/missing-repo' not found"

  local repo_dir="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${repo_dir}"
  _stub pgrep "exit 1"
  _stub git "echo 'git pull ok'"

  run "${MISE_LIB_DIR}/remote-deploy-compose.sh" "hosts/ps10rp/missing-svc" "${repo_dir}"
  assert_failure
  assert_output --partial "Directory hosts/ps10rp/missing-svc does not exist under ${repo_dir}"
}

@test "remote-deploy-compose: pulls, recreates stack, waits out pgrep timeout, and succeeds" {
  local repo_dir="${BATS_TEST_TMPDIR}/repo"
  local service_dir="hosts/ps10rp/komodo-periphery"
  local call_log="${BATS_TEST_TMPDIR}/calls.log"
  mkdir -p "${repo_dir}/${service_dir}"

  _stub pgrep "exit 0"
  _stub git "printf 'git %s\n' \"\$*\" >> '${call_log}'"
  _stub docker "
    printf 'docker %s\n' \"\$*\" >> '${call_log}'
    if [[ \"\$*\" == *'-q'* ]]; then
      exit 0
    fi
  "

  export KEEP_PATH=1 INITIAL_SLEEP=0 POLL_SLEEP=1 MAX_WAIT=1 POST_UP_SLEEP=0
  run "${MISE_LIB_DIR}/remote-deploy-compose.sh" "${service_dir}" "${repo_dir}"
  assert_success
  assert_output --partial "Timed out after 1s waiting for docker compose operations"

  run cat "${call_log}"
  assert_line --index 0 "git pull"
  assert_line --index 1 "docker compose pull"
  assert_line --index 2 "docker compose down"
  assert_line --index 3 "docker compose up -d"
  assert_line --index 4 "docker compose ps"
  assert_line --index 5 "docker compose ps --filter status=restarting --filter status=exited --filter status=dead -q"
  assert_line --index 6 "docker compose logs --tail=8"
}

@test "remote-deploy-compose: exits non-zero and prints container logs when unhealthy containers remain" {
  local repo_dir="${BATS_TEST_TMPDIR}/repo"
  local service_dir="hosts/ps10rp/komodo-periphery"
  local call_log="${BATS_TEST_TMPDIR}/calls.log"
  mkdir -p "${repo_dir}/${service_dir}"

  _stub pgrep "exit 1"
  _stub git "true"
  _stub docker "
    printf 'docker %s\n' \"\$*\" >> '${call_log}'
    if [[ \"\$*\" == *'-q'* ]]; then
      echo 'abc123def456'
    fi
  "

  export KEEP_PATH=1 INITIAL_SLEEP=0 POLL_SLEEP=0 MAX_WAIT=0 POST_UP_SLEEP=0
  run "${MISE_LIB_DIR}/remote-deploy-compose.sh" "${service_dir}" "${repo_dir}"
  assert_failure
  assert_output --partial "One or more containers failed to start or crashed!"

  run cat "${call_log}"
  assert_line "docker compose logs --tail=25"
}

@test "remote-update-periphery: configures drop-in, runs setup script, and verifies systemd service" {
  local call_log="${BATS_TEST_TMPDIR}/calls.log"
  local override_content="${BATS_TEST_TMPDIR}/override.conf"

  _stub pgrep "exit 1"
  _stub curl "echo 'print(\"setup-periphery\")'"
  _stub periphery "echo 'periphery 1.18.0'"
  _stub sudo "
    printf 'sudo %s\n' \"\$*\" >> '${call_log}'
    if [[ \"\$2\" == 'tee' ]]; then
      cat > '${override_content}'
    elif [[ \"\$2\" == 'python3' ]]; then
      cat >/dev/null
    fi
  "

  export INITIAL_SLEEP=0 POLL_SLEEP=0 MAX_WAIT=0 POST_INSTALL_SLEEP=0
  run "${MISE_LIB_DIR}/remote-update-periphery.sh" "https://komodo.example.test"
  assert_success
  assert_output --partial "periphery 1.18.0"

  assert_equal "$(cat "${override_content}")" $'[Service]\nKillMode=process'

  run cat "${call_log}"
  assert_line --index 0 "sudo -n mkdir -p /etc/systemd/system/periphery.service.d"
  assert_line --index 1 "sudo -n tee /etc/systemd/system/periphery.service.d/override.conf"
  assert_line --index 2 "sudo -n systemctl daemon-reload"
  assert_line --index 3 "sudo -n python3 - --core-address=https://komodo.example.test"
  assert_line --index 4 "sudo -n systemctl is-active periphery.service"
  assert_line --index 5 "sudo -n journalctl -u periphery -n 6 --no-pager"
}
