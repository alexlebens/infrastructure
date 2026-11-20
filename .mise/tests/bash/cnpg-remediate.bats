#!/usr/bin/env bats
# Tests for clusters/cl01tl/helm/cloudnative-pg/scripts/remediate.sh

setup() {
  load 'test_helper/common-setup'
  _common_setup

  REMEDIATE_SCRIPT="${PROJECT_ROOT}/clusters/cl01tl/helm/cloudnative-pg/scripts/remediate.sh"
  MOCK_STATE="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${MOCK_STATE}"
  KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  : > "${KUBECTL_LOG}"
  : > "${CURL_LOG}"
  export MOCK_STATE KUBECTL_LOG CURL_LOG

  export NTFY_ENDPOINT="https://ntfy.example.invalid"
  export NTFY_TOPIC="cnpg"
  export MIN_RESTARTS="5"
  export COOLDOWN_SECONDS="3600"
  export MAX_CLUSTERS="2"
  export DRY_RUN="false"

  cat <<'EOF' > "${MOCK_BIN}/curl"
#!/usr/bin/env bash
echo "$*" >> "${CURL_LOG}"
EOF
  chmod +x "${MOCK_BIN}/curl"

  cat <<'EOF' > "${MOCK_BIN}/kubectl"
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
  get)
    shift
    if [ "${1:-}" = "--raw=/readyz?verbose" ]; then
      echo "[+]etcd ok"
      exit 0
    fi
    if [ "${1:-}" = "nodes" ]; then
      echo '{"items":[{"status":{"conditions":[{"type":"Ready","status":"True"}]}}]}'
      exit 0
    fi
    if [ "${1:-}" = "clusters.postgresql.cnpg.io" ]; then
      cat "${MOCK_STATE}/clusters.json"
      exit 0
    fi
    if [ "${1:-}" = "pod" ]; then
      POD_NAME="$2"
      cat "${MOCK_STATE}/pod-${POD_NAME}.json"
      exit 0
    fi
    if [ "${1:-}" = "pods" ]; then
      cat "${MOCK_STATE}/pods.json"
      exit 0
    fi
    if [ "${1:-}" = "pvc" ]; then
      if [ -f "${MOCK_STATE}/pvcs.json" ]; then
        cat "${MOCK_STATE}/pvcs.json"
      else
        echo '{"items":[]}'
      fi
      exit 0
    fi
    ;;
  delete|annotate)
    echo "$*" >> "${KUBECTL_LOG}"
    exit 0
    ;;
  create)
    echo "create $(tr '\n' ' ')" >> "${KUBECTL_LOG}"
    exit 0
    ;;
esac
echo "Unexpected kubectl invocation: $*" >&2
exit 1
EOF
  chmod +x "${MOCK_BIN}/kubectl"
}

write_healthy_primary_pod() {
  local name="${1:-db-cluster-1}"
  cat <<EOF > "${MOCK_STATE}/pod-${name}.json"
{
  "metadata": {"name": "${name}"},
  "status": {
    "phase": "Running",
    "containerStatuses": [{"name": "postgres", "ready": true, "restartCount": 0, "state": {"running": {}}}]
  }
}
EOF
}

@test "remediate: skips Upgrading Postgres major version even without currentPrimary and emits no ntfy alert" {
  cat <<'EOF' > "${MOCK_STATE}/clusters.json"
{
  "items": [{
    "metadata": {"name": "donetick-postgres-cluster", "namespace": "donetick", "annotations": {}},
    "status": {"phase": "Upgrading Postgres major version", "currentPrimary": ""}
  }]
}
EOF

  run bash "${REMEDIATE_SCRIPT}"
  assert_success
  assert_output --partial "[SKIP] Cluster is in transitional phase 'Upgrading Postgres major version'"
  [ ! -s "${CURL_LOG}" ]
  [ ! -s "${KUBECTL_LOG}" ]
}

@test "remediate: skips Setting up primary and Creating a new replica with no alert" {
  cat <<'EOF' > "${MOCK_STATE}/clusters.json"
{
  "items": [
    {
      "metadata": {"name": "c1-postgres-cluster", "namespace": "ns1", "annotations": {}},
      "status": {"phase": "Setting up primary", "currentPrimary": ""}
    },
    {
      "metadata": {"name": "c2-postgres-cluster", "namespace": "ns2", "annotations": {}},
      "status": {"phase": "Creating a new replica", "currentPrimary": "c2-postgres-cluster-1"}
    }
  ]
}
EOF

  run bash "${REMEDIATE_SCRIPT}"
  assert_success
  assert_output --partial "Cluster is in transitional phase 'Setting up primary'"
  assert_output --partial "Cluster is in transitional phase 'Creating a new replica'"
  [ ! -s "${CURL_LOG}" ]
  [ ! -s "${KUBECTL_LOG}" ]
}

@test "remediate: skips clusters with reconciliationLoop=disabled, hibernation=on, or nodeMaintenanceWindow.inProgress=true" {
  cat <<'EOF' > "${MOCK_STATE}/clusters.json"
{
  "items": [
    {
      "metadata": {"name": "c1", "namespace": "ns1", "annotations": {"cnpg.io/reconciliationLoop": "disabled"}},
      "status": {"phase": "Cluster in healthy state", "currentPrimary": ""}
    },
    {
      "metadata": {"name": "c2", "namespace": "ns2", "annotations": {"cnpg.io/hibernation": "on"}},
      "status": {"phase": "Cluster in healthy state", "currentPrimary": ""}
    },
    {
      "metadata": {"name": "c3", "namespace": "ns3", "annotations": {}},
      "spec": {"nodeMaintenanceWindow": {"inProgress": true}},
      "status": {"phase": "Cluster in healthy state", "currentPrimary": ""}
    }
  ]
}
EOF

  run bash "${REMEDIATE_SCRIPT}"
  assert_success
  assert_output --partial "Reconciliation loop is disabled"
  assert_output --partial "Cluster hibernation is active"
  assert_output --partial "Node maintenance window is in progress"
  [ ! -s "${CURL_LOG}" ]
  [ ! -s "${KUBECTL_LOG}" ]
}

@test "remediate: ignores Pending, ContainerCreating, PodInitializing, ImagePullBackOff, Terminating, low-restart, and recovered standbys" {
  write_healthy_primary_pod "db-cluster-1"
  cat <<'EOF' > "${MOCK_STATE}/clusters.json"
{
  "items": [{
    "metadata": {"name": "db-cluster", "namespace": "app", "annotations": {}},
    "status": {"phase": "Waiting for the instances to become active", "currentPrimary": "db-cluster-1"}
  }]
}
EOF
  cat <<'EOF' > "${MOCK_STATE}/pods.json"
{
  "items": [
    {
      "metadata": {"name": "db-cluster-1"},
      "status": {"phase": "Running", "containerStatuses": [{"ready": true, "restartCount": 0, "state": {"running": {}}}]}
    },
    {
      "metadata": {"name": "db-cluster-2"},
      "status": {"phase": "Pending", "containerStatuses": []}
    },
    {
      "metadata": {"name": "db-cluster-3"},
      "status": {"phase": "Pending", "containerStatuses": [{"ready": false, "restartCount": 0, "state": {"waiting": {"reason": "ContainerCreating"}}}]}
    },
    {
      "metadata": {"name": "db-cluster-4"},
      "status": {"phase": "Pending", "containerStatuses": [{"ready": false, "restartCount": 6, "state": {"waiting": {"reason": "PodInitializing"}}}]}
    },
    {
      "metadata": {"name": "db-cluster-5"},
      "status": {"phase": "Pending", "containerStatuses": [{"ready": false, "restartCount": 6, "state": {"waiting": {"reason": "ImagePullBackOff"}}}]}
    },
    {
      "metadata": {"name": "db-cluster-6", "deletionTimestamp": "2026-11-20T00:00:00Z"},
      "status": {"phase": "Running", "containerStatuses": [{"ready": false, "restartCount": 9, "state": {"waiting": {"reason": "CrashLoopBackOff"}}}]}
    },
    {
      "metadata": {"name": "db-cluster-7"},
      "status": {"phase": "Running", "containerStatuses": [{"ready": false, "restartCount": 4, "state": {"waiting": {"reason": "CrashLoopBackOff"}}}]}
    },
    {
      "metadata": {"name": "db-cluster-8"},
      "status": {"phase": "Running", "containerStatuses": [{"ready": true, "restartCount": 6, "state": {"running": {}}}]}
    }
  ]
}
EOF

  run bash "${REMEDIATE_SCRIPT}"
  assert_success
  assert_output --partial "All standby instances appear healthy."
  [ ! -s "${CURL_LOG}" ]
  [ ! -s "${KUBECTL_LOG}" ]
}

@test "remediate: deletes CrashLoopBackOff standby with restarts >= MIN_RESTARTS during Waiting for the instances to become active" {
  write_healthy_primary_pod "db-cluster-1"
  cat <<'EOF' > "${MOCK_STATE}/clusters.json"
{
  "items": [{
    "metadata": {"name": "db-cluster", "namespace": "app", "annotations": {}},
    "status": {"phase": "Waiting for the instances to become active", "currentPrimary": "db-cluster-1"}
  }]
}
EOF
  cat <<'EOF' > "${MOCK_STATE}/pods.json"
{
  "items": [
    {
      "metadata": {"name": "db-cluster-1"},
      "status": {"phase": "Running", "containerStatuses": [{"ready": true, "restartCount": 0, "state": {"running": {}}}]}
    },
    {
      "metadata": {"name": "db-cluster-2"},
      "status": {"phase": "Running", "containerStatuses": [{"ready": false, "restartCount": 5, "state": {"waiting": {"reason": "CrashLoopBackOff"}}}]}
    }
  ]
}
EOF
  cat <<'EOF' > "${MOCK_STATE}/pvcs.json"
{
  "items": [
    {"metadata": {"name": "db-cluster-1", "labels": {"cnpg.io/instanceName": "db-cluster-1"}}},
    {"metadata": {"name": "db-cluster-2", "labels": {"cnpg.io/instanceName": "db-cluster-2"}}},
    {"metadata": {"name": "db-cluster-2-wal", "labels": {"cnpg.io/instanceName": "db-cluster-2"}}}
  ]
}
EOF

  run bash "${REMEDIATE_SCRIPT}"
  assert_success
  assert_output --partial "[TARGET] Found failing standby: db-cluster-2 (Status: CrashLoopBackOff, Ready: 0/1, Restarts: 5)"
  assert_output --partial "[REMEDIATED] Completed remediation for db-cluster-2"

  run cat "${KUBECTL_LOG}"
  assert_output --partial "delete pod db-cluster-2 -n app --wait=false"
  assert_output --partial "delete pvc db-cluster-2 -n app --wait=false"
  assert_output --partial "delete pvc db-cluster-2-wal -n app --wait=false"
  refute_output --partial "db-cluster-1"
  assert_output --partial "annotate cluster db-cluster -n app"
  assert_output --partial "reason: StandbyRemediated"

  run cat "${CURL_LOG}"
  assert_output --partial "X-Title: CNPG Standby Remediated: app/db-cluster"
  assert_output --partial "X-Priority: 3"
}

@test "remediate: blocks remediation and sends priority 5 ntfy when primary is unhealthy" {
  cat <<'EOF' > "${MOCK_STATE}/clusters.json"
{
  "items": [{
    "metadata": {"name": "db-cluster", "namespace": "app", "annotations": {}},
    "status": {"phase": "Cluster in healthy state", "currentPrimary": "db-cluster-1"}
  }]
}
EOF
  cat <<'EOF' > "${MOCK_STATE}/pod-db-cluster-1.json"
{
  "metadata": {"name": "db-cluster-1"},
  "status": {"phase": "Pending", "containerStatuses": []}
}
EOF

  run bash "${REMEDIATE_SCRIPT}"
  assert_success
  assert_output --partial "[ABORT] Primary pod 'db-cluster-1' is not healthy"

  run cat "${KUBECTL_LOG}"
  refute_output --partial "delete pod"
  assert_output --partial "reason: PrimaryUnhealthy"

  run cat "${CURL_LOG}"
  assert_output --partial "X-Title: CNPG Primary Unhealthy: app/db-cluster"
  assert_output --partial "X-Priority: 5"
}
