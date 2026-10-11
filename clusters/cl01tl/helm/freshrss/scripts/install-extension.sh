#!/bin/sh
set -eu

if [ -z "${EXTENSION_NAME:-}" ]; then
  echo "Error: EXTENSION_NAME is required" >&2
  exit 1
fi

if [ -z "${EXTENSION_REPO:-}" ]; then
  echo "Error: EXTENSION_REPO is required" >&2
  exit 1
fi

if [ -z "${EXTENSION_VERSION:-}" ]; then
  echo "Error: EXTENSION_VERSION is required" >&2
  exit 1
fi

# Determine version tracker file (preserving backwards compatibility with legacy version files)
if [ -z "${VERSION_FILE:-}" ]; then
  case "${EXTENSION_NAME}" in
    xExtension-ReadingTime)
      VERSION_FILE="/ext/.readingtime-version"
      ;;
    xExtension-AF-Readability)
      VERSION_FILE="/ext/.readability-version"
      ;;
    xExtension-FeedDigest)
      VERSION_FILE="/ext/.feeddigest-version-v3"
      ;;
    *)
      VERSION_FILE="/ext/.${EXTENSION_NAME}-version"
      ;;
  esac
fi

if [ -f "${VERSION_FILE}" ] && [ "$(cat "${VERSION_FILE}")" = "${EXTENSION_VERSION}" ]; then
  echo ">> ${EXTENSION_NAME} version ${EXTENSION_VERSION} already installed."
  exit 0
fi

echo ">> Installing ${EXTENSION_NAME} (${EXTENSION_VERSION}) from ${EXTENSION_REPO} ..."

rm -rf /tmp/ext-unzipped /tmp/ext.zip
mkdir -p /tmp/ext-unzipped "/ext/${EXTENSION_NAME}"

wget -qO /tmp/ext.zip "https://github.com/${EXTENSION_REPO}/archive/${EXTENSION_VERSION}.zip"
unzip -q /tmp/ext.zip -d /tmp/ext-unzipped

source_dir=""
for d in /tmp/ext-unzipped/*; do
  if [ -d "$d" ]; then
    source_dir="$d"
    break
  fi
done

if [ -z "$source_dir" ]; then
  echo "Error: Failed to find extracted directory in archive" >&2
  exit 1
fi

# Detect whether the extension is in a repository subdirectory (monorepo) or repository root
if [ -d "${source_dir}/${EXTENSION_NAME}" ]; then
  src_dir="${source_dir}/${EXTENSION_NAME}"
else
  src_dir="${source_dir}"
fi

rm -rf "/ext/${EXTENSION_NAME:?}"/*
cp -r "${src_dir}/." "/ext/${EXTENSION_NAME}/"

# Extension-specific patches
if [ "${EXTENSION_NAME}" = "xExtension-FeedDigest" ] && [ -f "/ext/${EXTENSION_NAME}/metadata.json" ]; then
  sed -i 's/"name": "Feed Digest"/"name": "FeedDigest"/g' "/ext/${EXTENSION_NAME}/metadata.json"
fi

rm -rf /tmp/ext-unzipped /tmp/ext.zip
echo "${EXTENSION_VERSION}" > "${VERSION_FILE}"

echo ">> Successfully installed ${EXTENSION_NAME} (${EXTENSION_VERSION})."
