#!/usr/bin/env bats
# Tests for .gitea/scripts/helper_helm-render.sh
#
# `helm` is stubbed to emit a fixed multi-document manifest; `yq` (mikefarah v4)
# is used for real since the split/namespace-injection logic depends on it.

setup() {
  load 'test_helper/common-setup'
  _common_setup

  if ! yq --version 2>/dev/null | grep -q mikefarah; then
    skip "mikefarah/yq v4 is required (run .gitea/scripts/install-yq.sh)"
  fi

  export HELM_LOG="${BATS_TEST_TMPDIR}/helm.log"
  export HELM_FIXTURE="${BATS_TEST_TMPDIR}/rendered.yaml"
  cat > "${HELM_FIXTURE}" <<'EOF'
---
# Source: demo/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo # trailing comment
spec:
  replicas: 1
---
# Source: demo/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: demo
  namespace: explicit-ns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: demo-reader
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.com
---
EOF

  # helm stub: logs argv; `template` prints the fixture (or fails if HELM_FAIL=1)
  _stub helm '
echo "$*" >> "${HELM_LOG}"
if [ "$1" = "template" ]; then
  [ "${HELM_FAIL:-0}" = "1" ] && { echo "boom" >&2; exit 1; }
  cat "${HELM_FIXTURE}"
fi
exit 0
'

  CHART_DIR="${BATS_TEST_TMPDIR}/charts/demo"
  mkdir -p "${CHART_DIR}"
  echo "name: demo" > "${CHART_DIR}/Chart.yaml"
  echo "replicas: 1" > "${CHART_DIR}/values.yaml"
  OUT_DIR="${BATS_TEST_TMPDIR}/out"

  source "${SCRIPTS_DIR}/helper_helm-namespace.sh"
  source "${SCRIPTS_DIR}/helper_helm-render.sh"
}

@test "render_helm_chart: requires --chart and --chart-path" {
  run render_helm_chart --chart demo
  assert_failure
  assert_output --partial "--chart and --chart-path are required"
}

@test "render_helm_chart: rejects unknown arguments" {
  run render_helm_chart --chart demo --chart-path "${CHART_DIR}" --bogus
  assert_failure
  assert_output --partial "Unknown argument to render_helm_chart: --bogus"
}

@test "render_helm_chart: passes namespace, values and api-versions to helm template" {
  run render_helm_chart --chart stack --chart-path "${CHART_DIR}" --api-versions "a/v1,b/v2"
  assert_success
  run cat "${HELM_LOG}"
  assert_output "template stack ${CHART_DIR} -f ${CHART_DIR}/values.yaml --include-crds --namespace argocd --api-versions a/v1,b/v2"
}

@test "render_helm_chart: omits -f when chart has no values.yaml" {
  rm "${CHART_DIR}/values.yaml"
  run render_helm_chart --chart demo --chart-path "${CHART_DIR}"
  assert_success
  run cat "${HELM_LOG}"
  assert_output "template demo ${CHART_DIR} --include-crds --namespace demo"
}

@test "render_helm_chart: --build-deps runs helm dependency build" {
  run render_helm_chart --chart demo --chart-path "${CHART_DIR}" --build-deps
  assert_success
  run head -n 1 "${HELM_LOG}"
  assert_output "dependency build --skip-refresh"
}

@test "render_helm_chart: persists raw output when --raw-output-file is set" {
  run render_helm_chart --chart demo --chart-path "${CHART_DIR}" --raw-output-file "${OUT_DIR}/raw/demo.yaml"
  assert_success
  assert [ -s "${OUT_DIR}/raw/demo.yaml" ]
  run grep -c "kind:" "${OUT_DIR}/raw/demo.yaml"
  assert_output "4"
}

@test "render_helm_chart: splits manifests into <Kind>-<name>.yaml files" {
  run render_helm_chart --chart demo --chart-path "${CHART_DIR}" --split-output-dir "${OUT_DIR}/split"
  assert_success
  run ls "${OUT_DIR}/split"
  assert_output "ClusterRole-demo-reader.yaml
CustomResourceDefinition-widgets.example.com.yaml
Deployment-demo.yaml
Service-demo.yaml"
}

@test "render_helm_chart: injects namespace only into namespaced resources lacking one" {
  run render_helm_chart --chart demo --chart-path "${CHART_DIR}" --split-output-dir "${OUT_DIR}/split"
  assert_success

  run yq '.metadata.namespace' "${OUT_DIR}/split/Deployment-demo.yaml"
  assert_output "demo"
  run yq '.metadata.namespace' "${OUT_DIR}/split/Service-demo.yaml"
  assert_output "explicit-ns"
  run yq '.metadata.namespace' "${OUT_DIR}/split/ClusterRole-demo-reader.yaml"
  assert_output "null"
  run yq '.metadata.namespace' "${OUT_DIR}/split/CustomResourceDefinition-widgets.example.com.yaml"
  assert_output "null"
}

@test "render_helm_chart: strips comments from split manifests" {
  run render_helm_chart --chart demo --chart-path "${CHART_DIR}" --split-output-dir "${OUT_DIR}/split"
  assert_success
  run grep -r "#" "${OUT_DIR}/split"
  assert_failure
}

@test "render_helm_chart: --cleanup-raw removes persisted raw file after split" {
  run render_helm_chart --chart demo --chart-path "${CHART_DIR}" \
    --raw-output-file "${OUT_DIR}/raw.yaml" --split-output-dir "${OUT_DIR}/split" --cleanup-raw
  assert_success
  assert [ ! -e "${OUT_DIR}/raw.yaml" ]
  assert [ -f "${OUT_DIR}/split/Deployment-demo.yaml" ]
}

@test "render_helm_chart: helm template failure returns non-zero and removes raw file" {
  HELM_FAIL=1 run render_helm_chart --chart demo --chart-path "${CHART_DIR}" --raw-output-file "${OUT_DIR}/raw.yaml"
  assert_failure
  assert_output --partial "Failed helm template for demo"
  assert [ ! -e "${OUT_DIR}/raw.yaml" ]
}
