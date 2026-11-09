#!/usr/bin/env bash
set -euo pipefail

MODELS_FILE="${MODELS_FILE:-images/models/models.yaml}"
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
      echo "Packages Hugging Face GGUF models or full repository snapshots declared in images/models/models.yaml as OCI images and pushes them to Harbor."
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
  TYPE=$(echo "${MODEL_ITEM}" | jq -r '.type // "single-file"')
  HF_REPO=$(echo "${MODEL_ITEM}" | jq -r '.hf_repo')
  TAG=$(echo "${MODEL_ITEM}" | jq -r '.tag')
  DESC=$(echo "${MODEL_ITEM}" | jq -r '.description // ""')

  IMAGE_REF="${HARBOR_HOST}/${HARBOR_PROJECT}/${NAME}:${TAG}"

  CURL_AUTH=()
  if [[ -n "${HF_TOKEN}" ]]; then
    CURL_AUTH=(-H "Authorization: Bearer ${HF_TOKEN}")
  fi

  if [[ "${TYPE}" == "snapshot" || "${TYPE}" == "repo" ]]; then
    echo "================================================================================"
    echo ">> Model (Snapshot): ${NAME}:${TAG}"
    echo ">> Source Repo:      ${HF_REPO}"
    echo ">> Target OCI:       ${IMAGE_REF}"
    echo "================================================================================"

    # Fetch latest commit SHA from Hugging Face API
    API_URL="https://huggingface.co/api/models/${HF_REPO}"
    UPSTREAM_SHA=$(curl -sL "${CURL_AUTH[@]}" "${API_URL}" | jq -r '.sha // empty' 2>/dev/null || true)
    if [[ -n "${UPSTREAM_SHA}" ]]; then
      echo ">> Upstream Hugging Face Commit SHA: ${UPSTREAM_SHA}"
    fi

    # Check if image already exists in Harbor
    if [[ "${FORCE_PUSH}" != "true" ]]; then
      EXISTING_MANIFEST=$(crane manifest "${IMAGE_REF}" 2>/dev/null || true)
      if [[ -n "${EXISTING_MANIFEST}" ]]; then
        EXISTING_DIGEST=$(crane digest "${IMAGE_REF}" 2>/dev/null || true)
        EXISTING_COMMIT_SHA=$(echo "${EXISTING_MANIFEST}" | jq -r '.annotations["io.huggingface.sha256"] // .annotations["io.huggingface.commit"] // empty' 2>/dev/null || true)

        if [[ -z "${UPSTREAM_SHA}" || -z "${EXISTING_COMMIT_SHA}" || "${UPSTREAM_SHA}" == "${EXISTING_COMMIT_SHA}" ]]; then
          echo ">> [SKIP] ${IMAGE_REF} already exists in Harbor (${EXISTING_DIGEST}). Use --force to rebuild."
          SUMMARY_ROWS+=("| \`${NAME}\` | \`${TAG}\` | \`${HF_REPO} (snapshot)\` | 🟢 Up-to-date | \`${IMAGE_REF}@${EXISTING_DIGEST}\` |")
          echo ""
          continue
        else
          echo ">> Upstream Commit SHA changed (${EXISTING_COMMIT_SHA} -> ${UPSTREAM_SHA}); rebuilding ..."
        fi
      fi
    fi

    MODEL_TMP_DIR="${WORK_DIR}/${NAME}-${TAG}"
    TARGET_DIR="${MODEL_TMP_DIR}/huggingface"
    mkdir -p "${TARGET_DIR}"

    echo ">> Downloading repository snapshot from ${HF_REPO} ..."
    PYTHON_EXEC="python3"
    if command -v uv >/dev/null 2>&1; then
      PYTHON_EXEC="uv run python3"
    elif ! python3 -c "import huggingface_hub" >/dev/null 2>&1; then
      python3 -m pip install --quiet --no-cache-dir --break-system-packages huggingface_hub || \
      python3 -m pip install --quiet --no-cache-dir huggingface_hub
    fi

    ${PYTHON_EXEC} -c "
import os, sys
from huggingface_hub import snapshot_download

token = os.environ.get('HF_TOKEN') or None
repo = sys.argv[1]
target = sys.argv[2]
snapshot_download(repo_id=repo, local_dir=target, token=token, max_workers=8)
" "${HF_REPO}" "${TARGET_DIR}"

    DIR_SIZE=$(du -sh "${TARGET_DIR}" | awk '{print $1}')
    echo ">> Downloaded snapshot for ${HF_REPO} (${DIR_SIZE})"

    echo ">> Streaming directory tree into OCI image ${IMAGE_REF} ..."
    tar -C "${MODEL_TMP_DIR}" -cf - "huggingface" | crane append --oci-empty-base -f - -t "${IMAGE_REF}"

    echo ">> Applying OCI platform and metadata annotations ..."
    crane mutate "${IMAGE_REF}" \
      --set-platform "linux/amd64" \
      -a "org.opencontainers.image.title=${NAME}" \
      -a "org.opencontainers.image.version=${TAG}" \
      -a "org.opencontainers.image.description=${DESC}" \
      -a "org.opencontainers.image.source=https://huggingface.co/${HF_REPO}" \
      -a "io.huggingface.repo=${HF_REPO}" \
      -a "io.huggingface.commit=${UPSTREAM_SHA:-unknown}" \
      -a "io.huggingface.sha256=${UPSTREAM_SHA:-unknown}" \
      -t "${IMAGE_REF}"

    FINAL_DIGEST=$(crane digest "${IMAGE_REF}")
    echo ">> Successfully pushed ${IMAGE_REF}@${FINAL_DIGEST}"
    SUMMARY_ROWS+=("| \`${NAME}\` | \`${TAG}\` | \`${HF_REPO} (snapshot)\` | 🚀 Pushed | \`${IMAGE_REF}@${FINAL_DIGEST}\` |")

    rm -rf "${MODEL_TMP_DIR}"
    echo ""

  else
    HF_FILE=$(echo "${MODEL_ITEM}" | jq -r '.hf_file')
    HF_URL="https://huggingface.co/${HF_REPO}/resolve/main/${HF_FILE}"
    FILENAME="$(basename "${HF_FILE}")"

    echo "================================================================================"
    echo ">> Model:       ${NAME}:${TAG}"
    echo ">> Source:      ${HF_REPO} (${HF_FILE})"
    echo ">> Target OCI:  ${IMAGE_REF}"
    echo "================================================================================"

    # Fetch upstream SHA256 from Hugging Face headers (X-Linked-Etag) if available
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
  fi
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
