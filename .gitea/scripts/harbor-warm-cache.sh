#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
CHART="${CHART:-}"
CLUSTER="${CLUSTER:-cl01tl}"
MANIFEST_PATH="${MANIFEST_PATH:-}"
HARBOR_HOST="${HARBOR_HOST:-harbor.alexlebens.dev}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chart)
      CHART="$2"
      shift 2
      ;;
    --cluster)
      CLUSTER="$2"
      shift 2
      ;;
    --manifest|--manifest-path|--manifest-dir)
      MANIFEST_PATH="$2"
      shift 2
      ;;
    --harbor-host)
      HARBOR_HOST="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--chart <chart>] [--cluster <cluster>] [--manifest <path>] [--harbor-host <fqdn>]"
      echo "Extracts container images from rendered manifests and validates/warms them through Harbor proxy cache."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "${CHART}" ] && [ -z "${MANIFEST_PATH}" ]; then
  echo "Error: --chart or --manifest is required." >&2
  exit 1
fi

if [ -z "${MANIFEST_PATH}" ]; then
  MANIFEST_PATH="clusters/${CLUSTER}/manifests/${CHART}"
fi

if [ ! -e "${MANIFEST_PATH}" ]; then
  echo "Error: Manifest path '${MANIFEST_PATH}' not found." >&2
  exit 1
fi

echo ">> Extracting container images from manifests in ${MANIFEST_PATH} ..."

# Extract image fields from rendered YAML manifests using yq.
# Exclude CustomResourceDefinitions and ensure only scalar strings are selected.
RAW_IMAGES=$(yq eval-all 'select(.kind != "CustomResourceDefinition") | .. | .image? | select(tag == "!!str")' "${MANIFEST_PATH}"/*.yaml 2>/dev/null | grep -v '^\-\-\-$' | sort -u || true)

IMAGES=()
while IFS= read -r line; do
  if [[ -n "${line}" && "${line}" != "null" && ! "${line}" =~ [[:space:]] ]]; then
    IMAGES+=("${line}")
  fi
done <<< "${RAW_IMAGES}"

if [ ${#IMAGES[@]} -eq 0 ]; then
  echo ">> No container images found in ${CHART} manifests."
  exit 0
fi

echo ">> Discovered images:"
for IMG in "${IMAGES[@]}"; do
  echo "  - ${IMG}"
done
echo ""

# Function to map an image reference to its Harbor proxy-cache endpoint
# Aligning with Talos registry mirror configuration:
#   docker.io / registry-1.docker.io -> proxy-hub.docker
#   ghcr.io                          -> proxy-ghcr.io
#   quay.io                          -> proxy-quay.io
#   registry.k8s.io                  -> proxy-registry.k8s
#   gcr.io                           -> proxy-gcr.io
resolve_harbor_proxy_image() {
  local RAW_IMG="$1"
  local REPO_AND_TAG=""
  local REGISTRY=""
  local PROXY_PROJECT=""

  # Separate registry host from repository path
  if [[ "${RAW_IMG}" =~ ^([a-zA-Z0-9._-]+:[0-9]+|[a-zA-Z0-9._-]+\.[a-zA-Z]{2,})/(.*)$ ]]; then
    REGISTRY="${BASH_REMATCH[1]}"
    REPO_AND_TAG="${BASH_REMATCH[2]}"
  else
    REGISTRY="docker.io"
    REPO_AND_TAG="${RAW_IMG}"
  fi

  case "${REGISTRY}" in
    docker.io|registry-1.docker.io)
      PROXY_PROJECT="proxy-hub.docker"
      # If repository has no slash (e.g. busybox:latest), prefix with library/
      if [[ "${REPO_AND_TAG}" != *"/"* ]]; then
        REPO_AND_TAG="library/${REPO_AND_TAG}"
      fi
      ;;
    ghcr.io)
      PROXY_PROJECT="proxy-ghcr.io"
      ;;
    quay.io)
      PROXY_PROJECT="proxy-quay.io"
      ;;
    registry.k8s.io)
      PROXY_PROJECT="proxy-registry.k8s"
      ;;
    gcr.io)
      PROXY_PROJECT="proxy-gcr.io"
      ;;
    "${HARBOR_HOST}")
      # Already pointing to Harbor directly
      echo "${RAW_IMG}"
      return 0
      ;;
    *)
      # Unmirrored registry - return empty or direct
      echo ""
      return 0
      ;;
  esac

  echo "${HARBOR_HOST}/${PROXY_PROJECT}/${REPO_AND_TAG}"
}

# Function to query the Harbor REST API to check if an artifact (by digest or tag) is cached locally
check_harbor_cache_state() {
  local harbor_host="$1"
  local project="$2"
  local repo_encoded="$3"
  local tag="$4"
  local digest="$5"

  # Fast check 1: direct lookup by digest if provided (exact pod image target)
  if [[ -n "${digest}" && "${digest}" != "null" ]]; then
    local code
    code=$(curl -s -k -o /dev/null -w "%{http_code}" "https://${harbor_host}/api/v2.0/projects/${project}/repositories/${repo_encoded}/artifacts/${digest}" 2>/dev/null || echo "000")
    if [[ "${code}" == "200" ]]; then
      return 0
    fi
  elif [[ -n "${tag}" && "${tag}" != "null" ]]; then
    # Fallback to direct lookup by tag only when no digest is specified
    local code
    code=$(curl -s -k -o /dev/null -w "%{http_code}" "https://${harbor_host}/api/v2.0/projects/${project}/repositories/${repo_encoded}/artifacts/${tag}" 2>/dev/null || echo "000")
    if [[ "${code}" == "200" ]]; then
      return 0
    fi
  fi

  # Comprehensive check: query repository artifacts for matching root digest or child manifest reference digest
  local artifacts_url="https://${harbor_host}/api/v2.0/projects/${project}/repositories/${repo_encoded}/artifacts?with_tag=true&page_size=100"
  local response
  response=$(curl -s -k -f "${artifacts_url}" 2>/dev/null || true)

  if [[ -z "${response}" || "${response}" == "null" || "${response}" == "[]" ]]; then
    return 1
  fi

  local matched
  matched=$(echo "${response}" | jq -r \
    --arg tag "${tag}" \
    --arg digest "${digest}" '
    if type != "array" then
      "false"
    elif ($digest != "" and any(.[]; .digest == $digest or (.references // [])[]?.child_digest == $digest)) then
      "true"
    elif ($digest == "" and $tag != "" and any(.[]; (.tags // [])[]?.name == $tag)) then
      "true"
    else
      "false"
    end
  ' 2>/dev/null || echo "false")

  if [[ "${matched}" == "true" ]]; then
    return 0
  fi

  # If digest is a multi-arch index, check if any of its child platform manifests are cached in Harbor
  if [[ -n "${digest}" && "${digest}" != "null" ]]; then
    local repo_decoded="${repo_encoded//%2F//}"
    local child_digests
    child_digests=$(echo "${response}" | jq -r '.[].references[]?.child_digest // empty' 2>/dev/null || true)
    if [[ -n "${child_digests}" ]]; then
      local index_children
      index_children=$(crane manifest "${harbor_host}/${project}/${repo_decoded}@${digest}" 2>/dev/null | jq -r '.manifests[]?.digest // empty' 2>/dev/null || true)
      if [[ -n "${index_children}" ]]; then
        for child in ${index_children}; do
          if echo "${child_digests}" | grep -qx "${child}"; then
            return 0
          fi
        done
      fi
    fi
  fi

  return 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED_IMAGES=()
WARMED_ROWS=()

for IMG in "${IMAGES[@]}"; do
  # Parse clean details:
  # Strip sha digest if present (@sha256:...)
  IMG_NO_DIGEST="${IMG%%@*}"
  IMAGE_DIGEST=""
  if [[ "${IMG}" == *"@"* ]]; then
    IMAGE_DIGEST="${IMG##*@}"
  fi

  # Parse registry vs repo/image
  if [[ "${IMG_NO_DIGEST}" =~ ^([a-zA-Z0-9._-]+:[0-9]+|[a-zA-Z0-9._-]+\.[a-zA-Z]{2,})/(.*)$ ]]; then
    REGISTRY_HOST="${BASH_REMATCH[1]}"
    IMAGE_PATH="${BASH_REMATCH[2]}"
  else
    REGISTRY_HOST="docker.io"
    IMAGE_PATH="${IMG_NO_DIGEST}"
  fi

  # Parse image name and tag
  if [[ "${IMAGE_PATH}" == *":"* ]]; then
    IMAGE_NAME="${IMAGE_PATH%%:*}"
    IMAGE_TAG="${IMAGE_PATH##*:}"
  else
    IMAGE_NAME="${IMAGE_PATH}"
    IMAGE_TAG=""
  fi

  # Determine repository path and proxy project for Harbor REST API
  PROXY_PROJECT=""
  IMAGE_REPO="${IMAGE_NAME}"
  case "${REGISTRY_HOST}" in
    docker.io|registry-1.docker.io)
      PROXY_PROJECT="proxy-hub.docker"
      if [[ "${IMAGE_REPO}" != *"/"* ]]; then
        IMAGE_REPO="library/${IMAGE_REPO}"
      fi
      ;;
    ghcr.io)
      PROXY_PROJECT="proxy-ghcr.io"
      ;;
    quay.io)
      PROXY_PROJECT="proxy-quay.io"
      ;;
    registry.k8s.io)
      PROXY_PROJECT="proxy-registry.k8s"
      ;;
    gcr.io)
      PROXY_PROJECT="proxy-gcr.io"
      ;;
  esac

  # Construct exact reference used by containerd/kubelet
  if [ -n "${IMAGE_DIGEST}" ]; then
    EXACT_REF="${IMAGE_REPO}@${IMAGE_DIGEST}"
  else
    EXACT_REF="${IMAGE_REPO}:${IMAGE_TAG:-latest}"
  fi

  if [ -n "${PROXY_PROJECT}" ]; then
    WARM_TARGET="${HARBOR_HOST}/${PROXY_PROJECT}/${EXACT_REF}"
    echo ">> [WARM] Exact Image '${IMG}' -> '${WARM_TARGET}'"
  else
    WARM_TARGET="${REGISTRY_HOST}/${EXACT_REF}"
    echo ">> [INFO] Image '${IMG}' does not use a mirrored registry; validating directly..."
  fi

  # Check if the exact image digest or tag is already cached in Harbor before warming
  ALREADY_CACHED=false
  if [ -n "${PROXY_PROJECT}" ]; then
    ENCODED_REPO="${IMAGE_REPO//\//%2F}"
    echo ">> Checking Harbor cache state for ${PROXY_PROJECT}/${IMAGE_REPO} (digest: ${IMAGE_DIGEST:-none}, tag: ${IMAGE_TAG:-none}) via REST API ..."
    if check_harbor_cache_state "${HARBOR_HOST}" "${PROXY_PROJECT}" "${ENCODED_REPO}" "${IMAGE_TAG}" "${IMAGE_DIGEST}"; then
      ALREADY_CACHED=true
      echo ">> Cache state: Already cached in Harbor"
    else
      echo ">> Cache state: Not cached in Harbor (will pull and warm)"
    fi
  else
    ALREADY_CACHED=true
  fi

  # Warm and validate remote image via crane.
  # Clusters include both x86_64 nodes and Raspberry Pi 4 (linux/arm64) nodes.
  # Fetching both platforms ensures Harbor caches the required manifests and layer blobs for each node architecture.
  WARM_FAILED=false
  SUPPORTED_PLATFORMS=()

  if [ -n "${PROXY_PROJECT}" ]; then
    # Warm tagged reference manifest as well if a tag was provided alongside digest
    if [[ -n "${IMAGE_TAG}" && -n "${IMAGE_DIGEST}" ]]; then
      crane manifest "${HARBOR_HOST}/${PROXY_PROJECT}/${IMAGE_REPO}:${IMAGE_TAG}" >/dev/null 2>&1 || true
    fi

    # Warm root manifest for exact target
    crane manifest "${WARM_TARGET}" >/dev/null 2>&1 || true

    for PLATFORM in "linux/amd64" "linux/arm64"; do
      if crane manifest --platform "${PLATFORM}" "${WARM_TARGET}" >/dev/null 2>&1; then
        SUPPORTED_PLATFORMS+=("${PLATFORM}")
        echo ">> Warming ${PLATFORM} layers for ${WARM_TARGET} ..."
        crane export --platform "${PLATFORM}" "${WARM_TARGET}" - >/dev/null 2>&1 || true
      fi
    done

    # If multi-arch check did not match specific platforms, test general digest
    if [ ${#SUPPORTED_PLATFORMS[@]} -eq 0 ]; then
      if crane manifest "${WARM_TARGET}" >/dev/null 2>&1; then
        SUPPORTED_PLATFORMS+=("default")
        echo ">> Warming default layers for ${WARM_TARGET} ..."
        crane export "${WARM_TARGET}" - >/dev/null 2>&1 || true
      else
        WARM_FAILED=true
      fi
    fi
  else
    # Direct validation for unmirrored registries
    for PLATFORM in "linux/amd64" "linux/arm64"; do
      if crane manifest --platform "${PLATFORM}" "${WARM_TARGET}" >/dev/null 2>&1; then
        SUPPORTED_PLATFORMS+=("${PLATFORM}")
      fi
    done

    if [ ${#SUPPORTED_PLATFORMS[@]} -eq 0 ]; then
      if crane digest "${WARM_TARGET}" >/dev/null 2>&1; then
        SUPPORTED_PLATFORMS+=("default")
      else
        WARM_FAILED=true
      fi
    fi
  fi

  PLATFORMS_STR=$(IFS=", "; echo "${SUPPORTED_PLATFORMS[*]}")

  # Display tag in comment: if empty, show truncated digest
  DISPLAY_TAG="${IMAGE_TAG}"
  if [[ -z "${DISPLAY_TAG}" && -n "${IMAGE_DIGEST}" ]]; then
    DISPLAY_TAG="${IMAGE_DIGEST:0:19}..."
  fi

  if [ "${WARM_FAILED}" = true ]; then
    echo ">> Failed to validate image: ${WARM_TARGET}" >&2
    FAILED_IMAGES+=("${IMG}")
    WARMED_ROWS+=("| \`${IMAGE_NAME}\` | \`${DISPLAY_TAG}\` | \`${REGISTRY_HOST}\` | 🔴 Failed | - |")
  else
    if [ "${ALREADY_CACHED}" = true ]; then
      echo ">> Image was already cached in Harbor: ${WARM_TARGET}"
      WARMED_ROWS+=("| \`${IMAGE_NAME}\` | \`${DISPLAY_TAG}\` | \`${REGISTRY_HOST}\` | 🟢 Cached | \`${PLATFORMS_STR}\` |")
    else
      echo ">> Image was pulled into Harbor: ${WARM_TARGET}"
      WARMED_ROWS+=("| \`${IMAGE_NAME}\` | \`${DISPLAY_TAG}\` | \`${REGISTRY_HOST}\` | 🟡 Pulled | \`${PLATFORMS_STR}\` |")
    fi
  fi
  echo ""
done

# Build Markdown Comment & Summary
TAG="<!-- harbor-warm-${CHART} -->"
COMMENT_BODY="${TAG}
### Harbor Image Cache: \`${CHART}\`

| Image | Tag | Registry | Status | Platforms |
| :--- | :--- | :--- | :--- | :--- |"

for ROW in "${WARMED_ROWS[@]}"; do
  COMMENT_BODY="${COMMENT_BODY}
${ROW}"
done

# Publish to Action UI Summary
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "${COMMENT_BODY}"
    echo ""
  } >> "${GITHUB_STEP_SUMMARY}"
fi

# Publish to Gitea PR Comment
SERVER_URL="${PUBLIC_URL:-${GITHUB_SERVER_URL:-${GITEA_SERVER_URL:-}}}"
REPO="${GITHUB_REPOSITORY:-${GITEA_REPOSITORY:-}}"

if [ -n "${GITEA_TOKEN:-}" ] && [ -n "${PR_NUMBER:-}" ] && [ -n "${SERVER_URL}" ] && [ -n "${REPO}" ]; then
  echo ">> Posting Harbor cache status to PR #${PR_NUMBER} ..."
  source "${SCRIPT_DIR}/helper_pr-comment-upsert.sh"
  upsert_pr_comment "${TAG}" "${COMMENT_BODY}"
fi

if [ ${#FAILED_IMAGES[@]} -ne 0 ]; then
  echo ">> One or more images failed validation / warming in Harbor:" >&2
  for FAILED in "${FAILED_IMAGES[@]}"; do
    echo "  - ${FAILED}" >&2
  done
  exit 1
fi

echo ">> All container images for ${CHART} verified and warmed successfully in Harbor."
