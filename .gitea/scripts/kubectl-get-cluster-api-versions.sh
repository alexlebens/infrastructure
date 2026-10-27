#!/usr/bin/env bash
set -euo pipefail

FINGERPRINT_ONLY=false
CACHE_FILE=""

# Parse optional command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fingerprint)
      FINGERPRINT_ONLY=true
      shift
      ;;
    --cache-file)
      CACHE_FILE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--fingerprint] [--cache-file <path>]"
      echo "Fetches Kubernetes cluster API versions and CRD kinds, outputting them formatted for Helm."
      echo "Options:"
      echo "  --fingerprint        Compute and output the cluster version and CRD fingerprint hash"
      echo "  --cache-file <path>  Read from cache file if present and non-empty, otherwise fetch and save to cache"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"

compute_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

if [ "${FINGERPRINT_ONLY}" = true ]; then
  echo ">> Computing cluster API and CRD fingerprint ..."
  VERSION_INFO=$(kubectl get --raw /version 2>/dev/null || kubectl version -o json 2>/dev/null || true)
  CRD_INFO=$(kubectl get crd -o go-template='{{if .items}}{{range .items}}{{.metadata.name}}:{{.metadata.generation}}{{"\n"}}{{end}}{{else}}{{.metadata.name}}:{{.metadata.generation}}{{"\n"}}{{end}}' 2>/dev/null | sort || true)
  FINGERPRINT=$(printf "%s\n%s" "${VERSION_INFO}" "${CRD_INFO}" | compute_sha256)

  echo ">> Cluster Fingerprint: ${FINGERPRINT}"
  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "fingerprint=${FINGERPRINT}" >> "${GITHUB_OUTPUT}"
  fi
  exit 0
fi

if [ -n "${CACHE_FILE}" ] && [ -f "${CACHE_FILE}" ] && [ -s "${CACHE_FILE}" ]; then
  echo ">> Using cached API versions from ${CACHE_FILE} ..."
  API_VERSIONS=$(cat "${CACHE_FILE}")
  echo ">> API Versions (cached):"
  echo "${API_VERSIONS}"
  echo ""
  echo "----"
  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "api-versions=${API_VERSIONS}" >> "${GITHUB_OUTPUT}"
  fi
  exit 0
fi

echo ">> Querying Kubernetes cluster API versions and CRD kinds ..."
CLUSTER_API_VERSIONS=$(kubectl api-versions | tr '\n' ',')
CLUSTER_CRD_KINDS=$(kubectl get crd -o go-template='{{if .items}}{{range .items}}{{$g := .spec.group}}{{$k := .spec.names.kind}}{{range .spec.versions}}{{if .served}}{{$g}}/{{.name}}/{{$k}}{{"\n"}}{{end}}{{end}}{{end}}{{else}}{{$g := .spec.group}}{{$k := .spec.names.kind}}{{range .spec.versions}}{{if .served}}{{$g}}/{{.name}}/{{$k}}{{"\n"}}{{end}}{{end}}{{end}}' | paste -sd, -)

# Merge versions and kinds
API_VERSIONS="${CLUSTER_API_VERSIONS},${CLUSTER_CRD_KINDS}"

# Format and deduplicate for helm
API_VERSIONS=$(echo "${API_VERSIONS}" | awk -F, '{for(i=1;i<=NF;i++) if($i!="") print $i}' | sort -u | paste -sd, -)

if [ -n "${CACHE_FILE}" ]; then
  mkdir -p "$(dirname "${CACHE_FILE}")"
  echo "${API_VERSIONS}" > "${CACHE_FILE}"
  echo ">> Saved API versions to cache file: ${CACHE_FILE}"
fi

echo ">> API Versions:"
echo "${API_VERSIONS}"

echo ""
echo "----"

if [ -n "${GITHUB_OUTPUT}" ]; then
  echo "api-versions=${API_VERSIONS}" >> "${GITHUB_OUTPUT}"
fi
