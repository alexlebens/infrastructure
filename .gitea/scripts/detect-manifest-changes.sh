#!/usr/bin/env bash
set -euo pipefail

# Parse optional command-line flags
MAIN_DIR="${MAIN_DIR:-infrastructure}"
CLUSTER="${CLUSTER:-cl01tl}"
RENDER_ALL="${RENDER_ALL:-false}"
DIFF_TARGET="${DIFF_TARGET:-}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main-dir)
      MAIN_DIR="$2"
      shift 2
      ;;
    --cluster)
      CLUSTER="$2"
      shift 2
      ;;
    --render-all)
      RENDER_ALL="$2"
      shift 2
      ;;
    --diff-target)
      DIFF_TARGET="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--main-dir <dir>] [--cluster <cluster>] [--render-all <true|false>] [--diff-target <target>]"
      echo "Identifies which Helm chart directories require rendering and sets workflow outputs."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ ! -d "${MAIN_DIR}" ]; then
  # If running directly inside the infrastructure repo
  if [ -d "clusters/${CLUSTER}/helm" ]; then
    MAIN_DIR="."
  else
    echo "Error: Directory '${MAIN_DIR}' not found." >&2
    exit 1
  fi
fi

pushd "${MAIN_DIR}" > /dev/null

if [[ "${RENDER_ALL}" == "true" ]]; then
  echo ">> Full render requested, discovering all chart paths under clusters/${CLUSTER}/helm ..."
  RENDER_DIR=$(find "clusters/${CLUSTER}/helm" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort -u)
else
  echo ">> Checking for changes from ${DIFF_TARGET} ..."
  if [ -n "${DIFF_TARGET}" ]; then
    RENDER_DIR=$(git diff --name-only "${DIFF_TARGET}" | grep -E "^clusters/${CLUSTER}/helm/" | awk -F '/' '{print $4}' | sort -u || true)
  else
    echo ">> No diff target provided, falling back to HEAD^..HEAD"
    RENDER_DIR=$(git diff --name-only "HEAD^..HEAD" | grep -E "^clusters/${CLUSTER}/helm/" | awk -F '/' '{print $4}' | sort -u || true)
  fi
fi

RENDER_DIR=$(echo "${RENDER_DIR}" | xargs)

if [ -n "${RENDER_DIR}" ]; then
  echo ""
  echo ">> Directories to Render:"
  for D in ${RENDER_DIR}; do
    echo "  - ${D}"
  done

  RENDER_DIR_CSV=$(echo "${RENDER_DIR}" | tr ' ' ',')

  echo ""
  echo "----"

  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "changes-detected=true" >> "${GITHUB_OUTPUT}"
    echo "render-dir-csv=${RENDER_DIR_CSV}" >> "${GITHUB_OUTPUT}"
    echo "render-dir<<EOF" >> "${GITHUB_OUTPUT}"
    for D in ${RENDER_DIR}; do
      echo "${D}" >> "${GITHUB_OUTPUT}"
    done
    echo "EOF" >> "${GITHUB_OUTPUT}"
  fi
else
  echo ""
  echo ">> No chart changes detected"
  echo ""
  echo "----"

  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "changes-detected=false" >> "${GITHUB_OUTPUT}"
    echo "render-dir-csv=" >> "${GITHUB_OUTPUT}"
    echo "render-dir=" >> "${GITHUB_OUTPUT}"
  fi
fi

popd > /dev/null
