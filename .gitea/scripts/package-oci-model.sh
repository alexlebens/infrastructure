#!/usr/bin/env bash
set -euo pipefail

MODELS_FILE="${MODELS_FILE:-models/models.yaml}"
HARBOR_HOST="${HARBOR_HOST:-harbor.alexlebens.dev}"
HARBOR_PROJECT="${HARBOR_PROJECT:-models}"
HARBOR_USER="${HARBOR_USER:-}"
HARBOR_SECRET="${HARBOR_SECRET:-}"
HF_TOKEN="${HF_TOKEN:-}"
FORCE_PUSH="${FORCE_PUSH:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --models-file)
      MODELS_FILE="$2"
      shift 2
      ;;
    --harbor-host)
      HARBOR_HOST="$2"
      shift 2
      ;;
    --harbor-project)
      HARBOR_PROJECT="$2"
      shift 2
      ;;
    --force)
      FORCE_PUSH="true"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--models-file <path>] [--harbor-host <fqdn>] [--harbor-project <project>] [--force]"
      echo "Packages Hugging Face GGUF models declared in models/models.yaml as OCI images and pushes them to Harbor."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

for cmd in crane yq jq curl tar; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: Required command '${cmd}' is not installed." >&2
    exit 1
  fi
done

if [[ ! -f "${MODELS_FILE}" ]]; then
  echo "Error: Models file '${MODELS_FILE}' not found." >&2
  exit 1
fi

if [[ -n "${HARBOR_USER}" && -n "${HARBOR_SECRET}" ]]; then
  echo ">> Authenticating to Harbor (${HARBOR_HOST}) ..."
  echo "${HARBOR_SECRET}" | crane auth login "${HARBOR_HOST}" -u "${HARBOR_USER}" --password-stdin
fi

MODELS_JSON=$(yq -o=json '.models' "${MODELS_FILE}" | jq -c '.')
MODEL_COUNT=$(echo "${MODELS_JSON}" | jq 'length')

if [[ "${MODEL_COUNT}" -eq 0 ]]; then
  echo "Error: No models found in '${MODELS_FILE}'." >&2
  exit 1
fi

echo ">> Found ${MODEL_COUNT} model(s) in ${MODELS_FILE} to process."
echo ""

SUMMARY_ROWS=()
WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

for (( i=0; i<MODEL_COUNT; i++ )); do
  MODEL_ITEM=$(echo "${MODELS_JSON}" | jq -c ".[$i]")
  NAME=$(echo "${MODEL_ITEM}" | jq -r '.name')
  HF_REPO=$(echo "${MODEL_ITEM}" | jq -r '.hf_repo')
  HF_FILE=$(echo "${MODEL_ITEM}" | jq -r '.hf_file')
  TAG=$(echo "${MODEL_ITEM}" | jq -r '.tag')
  DESC=$(echo "${MODEL_ITEM}" | jq -r '.description // ""')

  IMAGE_REF="${HARBOR_HOST}/${HARBOR_PROJECT}/${NAME}:${TAG}"
  HF_URL="https://huggingface.co/${HF_REPO}/resolve/main/${HF_FILE}"
  FILENAME="$(basename "${HF_FILE}")"

  echo "================================================================================"
  echo ">> Model:       ${NAME}:${TAG}"
  echo ">> Source:      ${HF_REPO} (${HF_FILE})"
  echo ">> Target OCI:  ${IMAGE_REF}"
  echo "================================================================================"

  # Fetch upstream SHA256 from Hugging Face headers (X-Linked-Etag) if available
  CURL_AUTH=()
  if [[ -n "${HF_TOKEN}" ]]; then
    CURL_AUTH=(-H "Authorization: Bearer ${HF_TOKEN}")
  fi

  UPSTREAM_SHA=$(curl -sI "${CURL_AUTH[@]}" "${HF_URL}" | tr -d '\r' | awk 'tolower($1) == "x-linked-etag:" {gsub(/"/, "", $2); print $2}' | head -n 1 || true)
  if [[ -n "${UPSTREAM_SHA}" ]]; then
    echo ">> Upstream Hugging Face SHA256: ${UPSTREAM_SHA}"
  fi

  # Check if image already exists in Harbor
  if [[ "${FORCE_PUSH}" != "true" ]]; then
    EXISTING_MANIFEST=$(crane manifest "${IMAGE_REF}" 2>/dev/null || true)
    if [[ -n "${EXISTING_MANIFEST}" ]]; then
      EXISTING_DIGEST=$(crane digest "${IMAGE_REF}" 2>/dev/null || true)
      EXISTING_FILE_SHA=$(echo "${EXISTING_MANIFEST}" | jq -r '.annotations["io.huggingface.sha256"] // empty' 2>/dev/null || true)

      if [[ -z "${UPSTREAM_SHA}" || -z "${EXISTING_FILE_SHA}" || "${UPSTREAM_SHA}" == "${EXISTING_FILE_SHA}" ]]; then
        echo ">> [SKIP] ${IMAGE_REF} already exists in Harbor (${EXISTING_DIGEST}). Use --force to rebuild."
        SUMMARY_ROWS+=("| \`${NAME}\` | \`${TAG}\` | \`${HF_REPO}/${HF_FILE}\` | 🟢 Up-to-date | \`${IMAGE_REF}@${EXISTING_DIGEST}\` |")
        echo ""
        continue
      else
        echo ">> Upstream SHA256 changed (${EXISTING_FILE_SHA} -> ${UPSTREAM_SHA}); rebuilding ..."
      fi
    fi
  fi

  MODEL_TMP_DIR="${WORK_DIR}/${NAME}-${TAG}"
  mkdir -p "${MODEL_TMP_DIR}"
  LOCAL_FILE="${MODEL_TMP_DIR}/${FILENAME}"

  echo ">> Downloading ${HF_URL} ..."
  curl -fL --retry 3 --retry-delay 5 "${CURL_AUTH[@]}" -o "${LOCAL_FILE}" "${HF_URL}"

  FILE_SIZE=$(du -h "${LOCAL_FILE}" | awk '{print $1}')
  if command -v sha256sum >/dev/null 2>&1; then
    LOCAL_SHA=$(sha256sum "${LOCAL_FILE}" | awk '{print $1}')
  else
    LOCAL_SHA=$(shasum -a 256 "${LOCAL_FILE}" | awk '{print $1}')
  fi
  echo ">> Downloaded ${FILENAME} (${FILE_SIZE}, sha256: ${LOCAL_SHA})"

  if [[ -n "${UPSTREAM_SHA}" && "${UPSTREAM_SHA}" =~ ^[a-f0-9]{64}$ && "${LOCAL_SHA}" != "${UPSTREAM_SHA}" ]]; then
    echo "Error: SHA256 mismatch for ${FILENAME}! Expected ${UPSTREAM_SHA}, got ${LOCAL_SHA}" >&2
    exit 1
  fi

  echo ">> Streaming ${FILENAME} into OCI image ${IMAGE_REF} ..."
  tar -C "${MODEL_TMP_DIR}" -cf - "${FILENAME}" | crane append --oci-empty-base -f - -t "${IMAGE_REF}"

  echo ">> Applying OCI platform and metadata annotations ..."
  crane mutate "${IMAGE_REF}" \
    --set-platform "linux/amd64" \
    -a "org.opencontainers.image.title=${NAME}" \
    -a "org.opencontainers.image.version=${TAG}" \
    -a "org.opencontainers.image.description=${DESC}" \
    -a "org.opencontainers.image.source=https://huggingface.co/${HF_REPO}" \
    -a "io.huggingface.repo=${HF_REPO}" \
    -a "io.huggingface.file=${HF_FILE}" \
    -a "io.huggingface.sha256=${LOCAL_SHA}" \
    -t "${IMAGE_REF}"

  FINAL_DIGEST=$(crane digest "${IMAGE_REF}")
  echo ">> Successfully pushed ${IMAGE_REF}@${FINAL_DIGEST}"

  SUMMARY_ROWS+=("| \`${NAME}\` | \`${TAG}\` | \`${HF_REPO}/${HF_FILE}\` | 🚀 Pushed | \`${IMAGE_REF}@${FINAL_DIGEST}\` |")

  # Clean up downloaded model before processing the next one to conserve runner disk space
  rm -rf "${MODEL_TMP_DIR}"
  echo ""
done

SUMMARY_TABLE="### OCI Model Packaging Summary

| Model | Tag | Source (Hugging Face) | Status | Pushed Reference (with Digest) |
| :--- | :--- | :--- | :--- | :--- |"

for ROW in "${SUMMARY_ROWS[@]}"; do
  SUMMARY_TABLE="${SUMMARY_TABLE}
${ROW}"
done

echo "${SUMMARY_TABLE}"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "${SUMMARY_TABLE}"
    echo ""
  } >> "${GITHUB_STEP_SUMMARY}"
fi
