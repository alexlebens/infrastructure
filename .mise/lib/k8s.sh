#!/usr/bin/env bash
# Sourceable helper library for Kubernetes cluster discovery and API version resolution.
#
# Provides:
#   k8s_get_fingerprint - Compute SHA256 of cluster version and CRDs
#   k8s_get_api_versions [cache_file] - Resolve comma-separated API versions/kinds for Helm
#   k8s_get_crd_hash - Compute SHA256 of cluster CRD names and generations
#
# Usage:
#   source "${REPO_ROOT}/.mise/lib/k8s.sh"
#   API_VERSIONS=$(k8s_get_api_versions ~/.cache/k8s-api-versions/api-versions.txt)
#   CRD_HASH=$(k8s_get_crd_hash)

if [[ -n "${_MISE_LIB_K8S_LOADED:-}" ]]; then
  return 0
fi
_MISE_LIB_K8S_LOADED=1

_K8S_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)"
# shellcheck source=./log.sh
source "${_K8S_LIB_DIR}/log.sh"

_k8s_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

k8s_get_fingerprint() {
  if ! command -v kubectl >/dev/null 2>&1; then
    return 1
  fi
  local VERSION_INFO CRD_INFO
  VERSION_INFO=$(kubectl get --raw /version 2>/dev/null || kubectl version -o json 2>/dev/null || true)
  CRD_INFO=$(kubectl get crd -o go-template='{{if .items}}{{range .items}}{{.metadata.name}}:{{.metadata.generation}}{{"\n"}}{{end}}{{else}}{{.metadata.name}}:{{.metadata.generation}}{{"\n"}}{{end}}' 2>/dev/null | sort || true)
  printf "%s\n%s" "${VERSION_INFO}" "${CRD_INFO}" | _k8s_sha256
}

k8s_get_crd_hash() {
  if ! command -v kubectl >/dev/null 2>&1; then
    return 1
  fi
  kubectl get crds -o jsonpath='{range .items[*]}{.metadata.name}:{.metadata.generation}{"\n"}{end}' 2>/dev/null | _k8s_sha256
}

k8s_get_api_versions() {
  local CACHE_FILE="${1:-}"

  if [ -n "${CACHE_FILE}" ] && [ -f "${CACHE_FILE}" ] && [ -s "${CACHE_FILE}" ]; then
    cat "${CACHE_FILE}"
    return 0
  fi

  if ! command -v kubectl >/dev/null 2>&1; then
    return 1
  fi

  # Verify cluster connectivity
  if ! kubectl version --request-timeout=3s >/dev/null 2>&1; then
    return 1
  fi

  local CLUSTER_API_VERSIONS CLUSTER_CRD_KINDS MERGED_VERSIONS
  CLUSTER_API_VERSIONS=$(kubectl api-versions 2>/dev/null | tr '\n' ',' || true)
  CLUSTER_CRD_KINDS=$(kubectl get crd -o go-template='{{if .items}}{{range .items}}{{$g := .spec.group}}{{$k := .spec.names.kind}}{{range .spec.versions}}{{if .served}}{{$g}}/{{.name}}/{{$k}}{{"\n"}}{{end}}{{end}}{{end}}{{else}}{{$g := .spec.group}}{{$k := .spec.names.kind}}{{range .spec.versions}}{{if .served}}{{$g}}/{{.name}}/{{$k}}{{"\n"}}{{end}}{{end}}{{end}}' 2>/dev/null | paste -sd, - || true)

  MERGED_VERSIONS="${CLUSTER_API_VERSIONS},${CLUSTER_CRD_KINDS}"
  MERGED_VERSIONS=$(echo "${MERGED_VERSIONS}" | awk -F, '{for(i=1;i<=NF;i++) if($i!="") print $i}' | sort -u | paste -sd, -)

  if [ -n "${CACHE_FILE}" ] && [ -n "${MERGED_VERSIONS}" ]; then
    mkdir -p "$(dirname "${CACHE_FILE}")"
    echo "${MERGED_VERSIONS}" > "${CACHE_FILE}"
  fi

  echo "${MERGED_VERSIONS}"
}
