#!/usr/bin/env bats
# Tests for .mise/tasks/gitea/detect-helm

setup() {
  load 'test_helper/common-setup'
  _common_setup
  _init_fixture_repo

  # Baseline: two charts on main
  _fixture_write "clusters/cl01tl/helm/alpha/Chart.yaml" "name: alpha"
  _fixture_write "clusters/cl01tl/helm/beta/Chart.yaml" "name: beta"
  _fixture_write "clusters/cl01tl/helm/beta/scripts/run.sh" "echo hi"
  _fixture_write "clusters/cl01tl/helm/gamma/Chart.yaml" "name: gamma"
  _fixture_write "clusters/cl01tl/helm/gamma/tests/unit.bats" "# test"
  _fixture_write "clusters/other/helm/alpha/Chart.yaml" "name: alpha"
  _fixture_commit "baseline"
  BASE_SHA="$(git rev-parse HEAD)"
}

_run_detect() {
  run "${MISE_TASKS_DIR}/gitea/detect-helm" --event-name push --event-before "${BASE_SHA}" "$@"
}

@test "detect-helm-changes: single chart change produces matrix and no scripts" {
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value changes-detected)" "true"
  assert_equal "$(_output_value matrix)" '["alpha"]'
  assert_equal "$(_output_value charts)" "alpha"
  assert_equal "$(_output_value scripts-detected)" "false"
  assert_equal "$(_output_value script-matrix)" "[]"
}

@test "detect-helm-changes: charts with scripts/ or tests/ are added to script-matrix" {
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 1"
  _fixture_write "clusters/cl01tl/helm/gamma/values.yaml" "c: 1"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value matrix)" '["alpha","beta","gamma"]'
  assert_equal "$(_output_value charts)" "alpha beta gamma"
  assert_equal "$(_output_value scripts-detected)" "true"
  assert_equal "$(_output_value script-matrix)" '["beta","gamma"]'
}

@test "detect-helm-changes: deleted chart (no Chart.yaml) is excluded" {
  git rm -q -r "clusters/cl01tl/helm/alpha"
  _fixture_commit "remove alpha"

  _run_detect
  assert_success
  assert_equal "$(_output_value changes-detected)" "false"
  assert_equal "$(_output_value matrix)" "[]"
  assert_equal "$(_output_value charts)" ""
}

@test "detect-helm-changes: changes in another cluster are ignored" {
  _fixture_write "clusters/other/helm/alpha/values.yaml" "x: 1"
  _fixture_commit

  _run_detect
  assert_success
  assert_equal "$(_output_value changes-detected)" "false"
}

@test "detect-helm-changes: --cluster selects the other cluster" {
  _fixture_write "clusters/other/helm/alpha/values.yaml" "x: 1"
  _fixture_commit

  _run_detect --cluster other
  assert_success
  assert_equal "$(_output_value matrix)" '["alpha"]'
}

@test "detect-helm-changes: non-helm changes produce empty outputs" {
  _fixture_write "README.md" "docs"
  _fixture_commit

  _run_detect
  assert_success
  assert_output --partial "Did not find any valid helm charts to test"
  assert_equal "$(_output_value changes-detected)" "false"
  assert_equal "$(_output_value scripts-detected)" "false"
  assert_equal "$(_output_value script-matrix)" "[]"
}

@test "detect-helm-changes: pull_request mode diffs feature branch against base" {
  git checkout -q -b feature
  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 2"
  _fixture_commit

  run "${MISE_TASKS_DIR}/gitea/detect-helm" --event-name pull_request --base-branch main
  assert_success
  assert_equal "$(_output_value matrix)" '["beta"]'
  assert_equal "$(_output_value script-matrix)" '["beta"]'
}

@test "detect-helm-changes: works without GITHUB_OUTPUT" {
  unset GITHUB_OUTPUT
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_commit

  _run_detect
  assert_success
  assert_output --partial "Charts to test:"
}

@test "detect-helm-changes: unknown argument fails" {
  run "${MISE_TASKS_DIR}/gitea/detect-helm" --bogus
  assert_failure
  assert_output --partial "Unknown argument: --bogus"
}

@test "detect-helm-changes: --help prints usage" {
  run "${MISE_TASKS_DIR}/gitea/detect-helm" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "detect-helm-changes: skips charts unchanged since last successful PR job" {
  git checkout -q -b "renovate/multi-chart"
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 1"
  _fixture_commit "commit 1: alpha and beta"
  local sha1
  sha1="$(git rev-parse HEAD)"

  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 2"
  _fixture_commit "commit 2: only beta changed"

  _stub curl "
    if [[ \"\$*\" == *\"/actions/runs?branch=renovate%2Fmulti-chart\"* ]]; then
      printf '{\"workflow_runs\":[{\"id\":101,\"head_sha\":\"%s\",\"workflow_id\":\"test-chart.yaml\"}]}\n' '${sha1}'
    elif [[ \"\$*\" == *\"/actions/runs/101/jobs\"* ]]; then
      printf '{\"jobs\":[{\"name\":\"test-chart (alpha)\",\"status\":\"completed\",\"conclusion\":\"success\"},{\"name\":\"test-chart (beta)\",\"status\":\"completed\",\"conclusion\":\"failure\"},{\"name\":\"test-chart-scripts (beta)\",\"status\":\"completed\",\"conclusion\":\"success\"}]}\n'
    else
      exit 1
    fi
  "

  GITEA_TOKEN="tok" PUBLIC_URL="https://gitea.example.test" REPO="owner/repo" HEAD_BRANCH="renovate/multi-chart" CURRENT_RUN_ID="102" \
    run "${MISE_TASKS_DIR}/gitea/detect-helm" --event-name pull_request --base-branch main

  assert_success
  assert_output --partial "Skipping charts unchanged since last successful run:"
  assert_equal "$(_output_value changes-detected)" "true"
  assert_equal "$(_output_value matrix)" '["beta"]'
  assert_equal "$(_output_value scripts-detected)" "true"
  assert_equal "$(_output_value script-matrix)" '["beta"]'
}

@test "detect-helm-changes: skips test-chart independently from test-chart-scripts" {
  git checkout -q -b "feat/scripts"
  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 1"
  _fixture_commit "commit 1"
  local sha1
  sha1="$(git rev-parse HEAD)"

  _fixture_write "README.md" "docs"
  _fixture_commit "commit 2: unrelated"

  _stub curl "
    if [[ \"\$*\" == *\"/actions/runs?\"* ]]; then
      printf '{\"workflow_runs\":[{\"id\":201,\"head_sha\":\"%s\",\"workflow_id\":\".gitea/workflows/test-chart.yaml\"}]}\n' '${sha1}'
    elif [[ \"\$*\" == *\"/actions/runs/201/jobs\"* ]]; then
      printf '{\"jobs\":[{\"name\":\"test-chart (beta)\",\"status\":\"completed\",\"conclusion\":\"success\"},{\"name\":\"test-chart-scripts (beta)\",\"status\":\"completed\",\"conclusion\":\"failure\"}]}\n'
    fi
  "

  GITEA_TOKEN="tok" PUBLIC_URL="https://gitea.example.test" REPO="owner/repo" HEAD_BRANCH="feat/scripts" CURRENT_RUN_ID="202" \
    run "${MISE_TASKS_DIR}/gitea/detect-helm" --event-name pull_request --base-branch main

  assert_success
  assert_equal "$(_output_value changes-detected)" "false"
  assert_equal "$(_output_value matrix)" "[]"
  assert_equal "$(_output_value scripts-detected)" "true"
  assert_equal "$(_output_value script-matrix)" '["beta"]'
}

@test "detect-helm-changes: re-tests charts when merge-base with base branch changes" {
  git checkout -q -b "feat/rebase"
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_commit "commit 1"
  local sha1
  sha1="$(git rev-parse HEAD)"

  git checkout -q main
  _fixture_write "README.md" "main moved"
  _fixture_commit "main advance"

  git checkout -q "feat/rebase"
  git merge -q --no-edit main

  _stub curl "
    if [[ \"\$*\" == *\"/actions/runs?\"* ]]; then
      printf '{\"workflow_runs\":[{\"id\":301,\"head_sha\":\"%s\",\"workflow_id\":\"test-chart.yaml\"}]}\n' '${sha1}'
    elif [[ \"\$*\" == *\"/actions/runs/301/jobs\"* ]]; then
      printf '{\"jobs\":[{\"name\":\"test-chart (alpha)\",\"status\":\"completed\",\"conclusion\":\"success\"}]}\n'
    fi
  "

  GITEA_TOKEN="tok" PUBLIC_URL="https://gitea.example.test" REPO="owner/repo" HEAD_BRANCH="feat/rebase" CURRENT_RUN_ID="302" \
    run "${MISE_TASKS_DIR}/gitea/detect-helm" --event-name pull_request --base-branch main

  assert_success
  assert_equal "$(_output_value changes-detected)" "true"
  assert_equal "$(_output_value matrix)" '["alpha"]'
}

@test "detect-helm-changes: --no-skip-passed disables API filtering and API errors fall back gracefully" {
  git checkout -q -b "feat/fallback"
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_commit "commit 1"

  _stub curl "exit 22"

  GITEA_TOKEN="tok" PUBLIC_URL="https://gitea.example.test" REPO="owner/repo" HEAD_BRANCH="feat/fallback" CURRENT_RUN_ID="401" \
    run "${MISE_TASKS_DIR}/gitea/detect-helm" --event-name pull_request --base-branch main

  assert_success
  assert_output --partial "Warning: Failed to query Gitea Actions runs API"
  assert_equal "$(_output_value matrix)" '["alpha"]'

  run "${MISE_TASKS_DIR}/gitea/detect-helm" --event-name pull_request --base-branch main --no-skip-passed
  assert_success
  assert_equal "$(_output_value matrix)" '["alpha"]'
}

@test "detect-helm-changes: recognizes Gitea native status=success on jobs" {
  git checkout -q -b "feat/gitea-status"
  _fixture_write "clusters/cl01tl/helm/alpha/values.yaml" "a: 1"
  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 1"
  _fixture_commit "commit 1"
  local sha1
  sha1="$(git rev-parse HEAD)"

  _fixture_write "clusters/cl01tl/helm/beta/values.yaml" "b: 2"
  _fixture_commit "commit 2"

  _stub curl "
    if [[ \"\$*\" == *\"/actions/runs?branch=\"* ]]; then
      printf '{\"workflow_runs\":[]}\n'
    elif [[ \"\$*\" == *\"/actions/runs?event=pull_request\"* ]]; then
      printf '{\"workflow_runs\":[{\"id\":501,\"head_sha\":\"%s\",\"workflow_id\":\"test-chart.yaml\"}]}\n' '${sha1}'
    elif [[ \"\$*\" == *\"/actions/runs/501/jobs\"* ]]; then
      printf '{\"jobs\":[{\"name\":\"test-chart (alpha)\",\"status\":\"success\"}]}\n'
    fi
  "

  GITEA_TOKEN="tok" PUBLIC_URL="https://gitea.example.test" REPO="owner/repo" HEAD_BRANCH="feat/gitea-status" CURRENT_RUN_ID="502" \
    run "${MISE_TASKS_DIR}/gitea/detect-helm" --event-name pull_request --base-branch main

  assert_success
  assert_equal "$(_output_value matrix)" '["beta"]'
}
