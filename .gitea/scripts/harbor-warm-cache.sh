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

# Extract image fields from rendered YAML manifests using yq
IMAGES=$(yq eval-all '.. | .image? | select(. != null)' "${MANIFEST_PATH}"/*.yaml 2>/dev/null | grep -v '^\-\-\-$' | sort -u || true)

if [ -z "${IMAGES}" ]; then
  echo ">> No container images found in ${CHART} manifests."
  exit 0
fi

echo ">> Discovered images:"
for IMG in ${IMAGES}; do
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED_IMAGES=()
WARMED_ROWS=()

for IMG in ${IMAGES}; do
  PROXY_IMG=$(resolve_harbor_proxy_image "${IMG}")

  if [ -z "${PROXY_IMG}" ]; then
    echo ">> [INFO] Image '${IMG}' does not use a mirrored registry; validating directly..."
    TARGET_IMG="${IMG}"
  else
    echo ">> [WARM] Image '${IMG}' -> '${PROXY_IMG}'"
    TARGET_IMG="${PROXY_IMG}"
  fi

  # Warm and validate remote image via crane without pulling/storing image layers on the runner.
  # Clusters include both x86_64 nodes and Raspberry Pi 4 (linux/arm64) nodes.
  # Fetching both platforms ensures Harbor caches the required manifests for each node architecture.
  WARM_FAILED=false
  SUPPORTED_PLATFORMS=()

  for PLATFORM in "linux/amd64" "linux/arm64"; do
    if crane manifest --platform "${PLATFORM}" "${TARGET_IMG}" >/dev/null 2>&1; then
      SUPPORTED_PLATFORMS+=("${PLATFORM}")
    fi
  done

  # If multi-arch check did not match specific platforms, test general digest
  if [ ${#SUPPORTED_PLATFORMS[@]} -eq 0 ]; then
    if crane digest "${TARGET_IMG}" >/dev/null 2>&1; then
      SUPPORTED_PLATFORMS+=("default")
    else
      WARM_FAILED=true
    fi
  fi

  # Parse clean details for PR comment:
  # Strip sha digest if present (@sha256:...)
  IMG_NO_DIGEST="${IMG%%@*}"

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
    IMAGE_TAG="latest"
  fi

  PLATFORMS_STR=$(IFS=", "; echo "${SUPPORTED_PLATFORMS[*]}")

  if [ "${WARM_FAILED}" = true ]; then
    echo ">> Failed to validate image: ${TARGET_IMG}" >&2
    FAILED_IMAGES+=("${IMG}")
    WARMED_ROWS+=("| \`${IMAGE_NAME}\` | \`${IMAGE_TAG}\` | \`${REGISTRY_HOST}\` | ❌ Failed | - |")
  else
    echo ">> Successfully validated and warmed: ${TARGET_IMG}"
    WARMED_ROWS+=("| \`${IMAGE_NAME}\` | \`${IMAGE_TAG}\` | \`${REGISTRY_HOST}\` | ✅ Warmed | \`${PLATFORMS_STR}\` |")
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
