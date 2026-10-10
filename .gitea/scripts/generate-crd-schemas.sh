#!/usr/bin/env bash
set -euo pipefail

# Extracts CRD OpenAPI schemas from a live Kubernetes cluster and converts them
# to JSON schema files that kubeconform can use for validation.
#
# Requires: kubectl (configured), python3, pyyaml

SCHEMA_DIR="${SCHEMA_DIR:-${HOME}/.schemas}"
BIN_DIR="${HOME}/.local/bin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --schema-dir)
      SCHEMA_DIR="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--schema-dir <dir>]"
      echo "Extracts CRD schemas from the cluster and converts them to JSON for kubeconform."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "${SCHEMA_DIR}" "${BIN_DIR}"

# Download openapi2jsonschema.py if not present
if [ ! -f "${BIN_DIR}/openapi2jsonschema.py" ]; then
  echo ">> Downloading openapi2jsonschema.py ..."
  wget -qO "${BIN_DIR}/openapi2jsonschema.py" "https://raw.githubusercontent.com/yannh/kubeconform/master/scripts/openapi2jsonschema.py"
  chmod +x "${BIN_DIR}/openapi2jsonschema.py"
fi

echo ">> Extracting CRD definitions from cluster ..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

# Get all CRDs from the cluster and split into individual files
CRD_COUNT=0
for CRD_NAME in $(kubectl get crds -o jsonpath='{.items[*].metadata.name}'); do
  kubectl get crd "${CRD_NAME}" -o yaml > "${TMP_DIR}/${CRD_NAME}.yaml"
  CRD_COUNT=$((CRD_COUNT + 1))
done

if [ "${CRD_COUNT}" -eq 0 ]; then
  echo ">> No CRDs found in cluster. Skipping schema generation."
  exit 0
fi

echo ">> Extracted ${CRD_COUNT} CRDs from cluster"

echo ">> Converting CRD schemas to JSON ..."
cd "${TMP_DIR}"
export FILENAME_FORMAT='{kind}_{version}'
for crd_file in "${TMP_DIR}"/*.yaml; do
  python3 "${BIN_DIR}/openapi2jsonschema.py" "file://${crd_file}" || true
done

mv ./*.json "${SCHEMA_DIR}/" 2>/dev/null || true

SCHEMA_COUNT=$(find "${SCHEMA_DIR}" -name '*.json' | wc -l | xargs)
echo ">> Schemas generated successfully in ${SCHEMA_DIR}:"
echo ">> Generated ${SCHEMA_COUNT} JSON schemas"
echo "----"
