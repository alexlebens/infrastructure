#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse optional command-line flags
CHART="${CHART:-}"
CLUSTER="${CLUSTER:-cl01tl}"
MANIFEST_FILE=""
FAIL_ON="${FAIL_ON:-CRITICAL}"
GITEA_TOKEN="${GITEA_TOKEN:-}"
PR_NUMBER="${PR_NUMBER:-}"

MAIN_DIR="${MAIN_DIR:-.}"
IGNORE_FILE="${IGNORE_FILE:-}"

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
    --main-dir)
      MAIN_DIR="$2"
      shift 2
      ;;
    --manifest)
      MANIFEST_FILE="$2"
      shift 2
      ;;
    --ignorefile)
      IGNORE_FILE="$2"
      shift 2
      ;;
    --fail-on)
      FAIL_ON="$2"
      shift 2
      ;;
    --gitea-token)
      GITEA_TOKEN="$2"
      shift 2
      ;;
    --pr-number)
      PR_NUMBER="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--chart <chart>] [--cluster <cluster>] [--main-dir <dir>] [--manifest <file>] [--ignorefile <file>] [--fail-on <CRITICAL|HIGH>] [--gitea-token <token>] [--pr-number <num>]"
      echo "Runs Trivy misconfiguration scan on rendered manifests, publishes advisory summary and PR comments, and enforces severity gate."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "${CHART}" ] && [ -z "${MANIFEST_FILE}" ]; then
  echo "Error: --chart (or CHART env var) or --manifest is required." >&2
  exit 1
fi

MANIFEST_FILE="${MANIFEST_FILE:-rendered-raw/${CHART}.yaml}"

if [ ! -f "${MANIFEST_FILE}" ]; then
  echo "Error: Manifest file '${MANIFEST_FILE}' not found." >&2
  exit 1
fi

# Detect ignore file if not explicitly set
if [ -z "${IGNORE_FILE}" ]; then
  CHART_IGNORE="${MAIN_DIR}/clusters/${CLUSTER}/helm/${CHART}/.trivyignore"
  if [ -n "${CHART}" ] && [ -f "${CHART_IGNORE}" ]; then
    IGNORE_FILE="${CHART_IGNORE}"
  elif [ -f "${MAIN_DIR}/.trivyignore" ]; then
    IGNORE_FILE="${MAIN_DIR}/.trivyignore"
  fi
fi

REPORT_JSON="$(mktemp)"

cleanup() {
  rm -f "${REPORT_JSON:-}"
}
trap cleanup EXIT

echo ">> Running Trivy scan for: ${CHART:-$(basename "${MANIFEST_FILE}")} ..."

# Generate machine-readable JSON in a single pass
if [ -n "${IGNORE_FILE}" ] && [ -f "${IGNORE_FILE}" ]; then
  echo ">> Using ignore file: ${IGNORE_FILE}"
  trivy config --ignorefile "${IGNORE_FILE}" "${MANIFEST_FILE}" --format json > "${REPORT_JSON}" 2>/dev/null || true
else
  trivy config "${MANIFEST_FILE}" --format json > "${REPORT_JSON}" 2>/dev/null || true
fi

# Parse findings from JSON report in a single pass
read -r CRITICAL_COUNT HIGH_COUNT MEDIUM_COUNT LOW_COUNT < <(jq -r '
  [.Results[]?.Misconfigurations[]?] as $m |
  [
    ($m | map(select(.Severity == "CRITICAL")) | length),
    ($m | map(select(.Severity == "HIGH")) | length),
    ($m | map(select(.Severity == "MEDIUM")) | length),
    ($m | map(select(.Severity == "LOW")) | length)
  ] | @tsv' "${REPORT_JSON}" 2>/dev/null || echo "0 0 0 0")
TOTAL_FINDINGS=$(( CRITICAL_COUNT + HIGH_COUNT + MEDIUM_COUNT + LOW_COUNT ))

echo ""
echo ">> Summary for ${CHART}: ${CRITICAL_COUNT} Critical, ${HIGH_COUNT} High, ${MEDIUM_COUNT} Medium, ${LOW_COUNT} Low (${TOTAL_FINDINGS} total)"

if [ "${TOTAL_FINDINGS}" -gt 0 ]; then
  echo ">> Misconfigurations detected:"
  jq -r '.Results[]?.Misconfigurations[]? | "  - [\(.Severity)] \(.ID): \(.Title // .Message)"' "${REPORT_JSON}" 2>/dev/null || true
fi

# Build Markdown Report
TAG="<!-- trivy-scan-${CHART} -->"
MARKDOWN_REPORT="${TAG}
### Trivy Security Scan: \`${CHART}\`"

if [ "${TOTAL_FINDINGS}" -eq 0 ]; then
  STATUS_TEXT="**Passed** — No security misconfigurations detected."
  MARKDOWN_REPORT="${MARKDOWN_REPORT}
${STATUS_TEXT}"
else
  if [ "${CRITICAL_COUNT}" -gt 0 ]; then
    STATUS_TEXT="**Failed Gate** — Found ${CRITICAL_COUNT} Critical misconfiguration(s) requiring resolution."
  else
    STATUS_TEXT="**Passed Gate with Advisories** (0 Critical, ${HIGH_COUNT} High, ${MEDIUM_COUNT} Medium, ${LOW_COUNT} Low)"
  fi

  TABLE_ROWS=$(jq -r '
    [
      .Results[]? as $r |
      ($r.Misconfigurations // [])[]? |
      "| " +
      (if .Severity == "CRITICAL" then "🔴 **CRITICAL**"
       elif .Severity == "HIGH" then "🟠 **HIGH**"
       elif .Severity == "MEDIUM" then "🟡 **MEDIUM**"
       else "⚪ " + .Severity end) +
      " | [`" + .ID + "`](" + (.PrimaryURL // ("https://avd.aquasec.com/appshield/" + (.ID | ascii_downcase))) + ") | `" +
      ($r.Target // .Title // "manifest") + "` | " +
      ((.Title // .Message // "") | gsub("\r?\n"; " ") | gsub("\\|"; "/")) + " |"
    ] | join("\n")
  ' "${REPORT_JSON}" 2>/dev/null || true)

  MARKDOWN_REPORT="${MARKDOWN_REPORT}
${STATUS_TEXT}

| Severity | Rule ID | Resource | Message |
| :--- | :--- | :--- | :--- |
${TABLE_ROWS}"
fi

# Publish to Action UI Summary
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "" >> "${GITHUB_STEP_SUMMARY}"
  echo "${MARKDOWN_REPORT}" >> "${GITHUB_STEP_SUMMARY}"
fi

# Publish to Gitea PR Comment
SERVER_URL="${PUBLIC_URL:-${GITHUB_SERVER_URL:-${GITEA_SERVER_URL:-}}}"
REPO="${GITHUB_REPOSITORY:-${GITEA_REPOSITORY:-}}"

if [ -n "${GITEA_TOKEN}" ] && [ -n "${PR_NUMBER}" ] && [ -n "${SERVER_URL}" ] && [ -n "${REPO}" ]; then
  echo ">> Publishing Trivy advisory to PR #${PR_NUMBER} ..."
  source "${SCRIPT_DIR}/helper_pr-comment-upsert.sh"
  upsert_pr_comment "${TAG}" "${MARKDOWN_REPORT}"
fi

# Severity Gate Check
if [ "${FAIL_ON}" = "CRITICAL" ] && [ "${CRITICAL_COUNT}" -gt 0 ]; then
  echo ""
  echo ">> Security check failed: ${CRITICAL_COUNT} CRITICAL misconfiguration(s) detected in ${CHART}." >&2
  exit 1
elif [ "${FAIL_ON}" = "HIGH" ] && [ $(( CRITICAL_COUNT + HIGH_COUNT )) -gt 0 ]; then
  echo ""
  echo ">> Security check failed: $(( CRITICAL_COUNT + HIGH_COUNT )) HIGH/CRITICAL misconfiguration(s) detected in ${CHART}." >&2
  exit 1
fi

echo ""
echo ">> Trivy scan passed gate for ${CHART}."
echo "----"
