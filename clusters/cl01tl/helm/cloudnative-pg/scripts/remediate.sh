#!/usr/bin/env bash
set -euo pipefail

MIN_RESTARTS="${MIN_RESTARTS:-5}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-3600}"
MAX_CLUSTERS="${MAX_CLUSTERS:-2}"
DRY_RUN="${DRY_RUN:-false}"

echo "=========================================================="
echo "Starting CloudNativePG Auto-Remediator at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Configuration: MIN_RESTARTS=${MIN_RESTARTS}, COOLDOWN_SECONDS=${COOLDOWN_SECONDS}, MAX_CLUSTERS=${MAX_CLUSTERS}, DRY_RUN=${DRY_RUN}"
echo "=========================================================="

parse_iso_to_epoch() {
    local iso="$1"
    if date --version &>/dev/null || date -d "@0" &>/dev/null; then
        date -d "$iso" +%s 2>/dev/null || echo 0
    else
        date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" "+%s" 2>/dev/null || echo 0
    fi
}

send_ntfy() {
    local title="$1"
    local message="$2"
    local priority="${3:-3}"
    local tags="${4:-database}"

    if [ -z "${NTFY_ENDPOINT:-}" ] || [ -z "${NTFY_TOPIC:-}" ]; then
        return 0
    fi

    echo "  [NTFY] Sending notification: ${title} (priority: ${priority})"
    local auth_header=()
    if [ -n "${NTFY_TOKEN:-}" ]; then
        auth_header=(-H "Authorization: Bearer ${NTFY_TOKEN}")
    fi

    curl -s -S \
        --max-time 10 \
        "${auth_header[@]}" \
        -H "X-Title: ${title}" \
        -H "X-Priority: ${priority}" \
        -H "X-Tags: ${tags}" \
        -d "${message}" \
        "${NTFY_ENDPOINT}/${NTFY_TOPIC}" >/dev/null || true
}

emit_k8s_event() {
    local ns="$1"
    local name="$2"
    local reason="$3"
    local type="$4" # Normal or Warning
    local message="$5"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    echo "  [EVENT] Emitting Kubernetes ${type} event (${reason}): ${message}"
    cat <<EOF | kubectl create -f - 2>/dev/null || true
apiVersion: v1
kind: Event
metadata:
  generateName: cnpg-remediator-
  namespace: ${ns}
involvedObject:
  apiVersion: postgresql.cnpg.io/v1
  kind: Cluster
  name: ${name}
  namespace: ${ns}
reason: ${reason}
message: "${message}"
type: ${type}
firstTimestamp: "${now}"
lastTimestamp: "${now}"
count: 1
source:
  component: cloudnative-pg-remediator
EOF
}

check_etcd_and_cluster_health() {
    echo "Checking Kubernetes cluster health and etcd quorum..."

    # Check 1: API Server health and etcd status via /readyz?verbose
    local readyz_output readyz_rc=0
    readyz_output=$(kubectl get --raw='/readyz?verbose' 2>&1) || readyz_rc=$?

    if [ "$readyz_rc" -eq 0 ] && [ -n "$readyz_output" ]; then
        if echo "$readyz_output" | grep -q "[-]etcd"; then
            echo "  [ABORT] etcd health check failed in /readyz. Aborting remediation." >&2
            return 1
        fi
        if ! echo "$readyz_output" | grep -qE "\[\+\]etcd(-readiness)? ok"; then
            echo "  [ABORT] etcd readiness was not confirmed in /readyz. Aborting remediation." >&2
            return 1
        fi
        echo "  ✔ API Server reports etcd is healthy and ready."
    else
        # Fallback to simple /readyz if verbose is unavailable
        local readyz_fallback fallback_rc=0
        readyz_fallback=$(kubectl get --raw='/readyz' 2>&1) || fallback_rc=$?
        if [ "$fallback_rc" -ne 0 ] || [ "$readyz_fallback" != "ok" ]; then
            echo "  [ABORT] Kubernetes /readyz check failed ('${readyz_fallback}'). Aborting remediation." >&2
            return 1
        fi
        echo "  ✔ Kubernetes /readyz check passed."
    fi

    # Check 2: Control plane nodes quorum
    local nodes_json
    nodes_json=$(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o json 2>/dev/null || true)

    if [ -n "$nodes_json" ]; then
        local total_cp ready_cp required_quorum
        total_cp=$(echo "$nodes_json" | jq '.items | length // 0')
        if [ "$total_cp" -gt 0 ]; then
            ready_cp=$(echo "$nodes_json" | jq '[.items[] | select(.status.conditions[]? | select(.type == "Ready" and .status == "True"))] | length')
            required_quorum=$(( (total_cp / 2) + 1 ))

            echo "  Control plane nodes: ${ready_cp}/${total_cp} Ready (Quorum requires: ${required_quorum})"

            if [ "$ready_cp" -lt "$required_quorum" ]; then
                echo "  [ABORT] Control plane has lost etcd quorum (${ready_cp}/${total_cp} Ready). Aborting remediation." >&2
                return 1
            fi
            echo "  ✔ Control plane quorum is healthy (${ready_cp}/${total_cp} Ready)."
        fi
    fi

    return 0
}

# Run preflight cluster health check
if ! check_etcd_and_cluster_health; then
    echo "Cluster health check failed. Exiting immediately to prevent remediation during cluster degradation." >&2
    send_ntfy "Kubernetes Control-Plane / etcd Unhealthy" "Kubernetes /readyz or etcd quorum check failed. CloudNativePG auto-remediation aborted to protect databases." 5 "rotating_light"
    exit 1
fi
echo ""

CLUSTERS_JSON=$(kubectl get clusters.postgresql.cnpg.io -A -o json 2>/dev/null || true)
if [ -z "$CLUSTERS_JSON" ] || [ "$(echo "$CLUSTERS_JSON" | jq '.items | length')" -eq 0 ]; then
    echo "No CNPG clusters found in the cluster."
    exit 0
fi

TOTAL_CLUSTERS=$(echo "$CLUSTERS_JSON" | jq '.items | length')
echo "Discovered ${TOTAL_CLUSTERS} CNPG cluster(s)."

REMEDIATED_COUNT=0
while read -r cluster; do
    NS=$(echo "$cluster" | jq -r '.metadata.namespace')
    NAME=$(echo "$cluster" | jq -r '.metadata.name')
    PHASE=$(echo "$cluster" | jq -r '.status.phase // "Unknown"')
    PRIMARY=$(echo "$cluster" | jq -r '.status.currentPrimary // ""')
    LAST_REMEDIATED=$(echo "$cluster" | jq -r '.metadata.annotations["cnpg.io/last-remediated-at"] // ""')
    LAST_INSTANCE=$(echo "$cluster" | jq -r '.metadata.annotations["cnpg.io/last-remediated-instance"] // ""')
    REMEDIATION_COUNT=$(echo "$cluster" | jq -r '.metadata.annotations["cnpg.io/remediation-count"] // "0"')
    PERSISTENT_ALERT_SENT=$(echo "$cluster" | jq -r '.metadata.annotations["cnpg.io/persistent-alert-sent"] // "false"')

    echo "--- Cluster: ${NS}/${NAME} (Phase: ${PHASE}, Primary: ${PRIMARY}) ---"

    # Safety Check 1: Primary exists
    if [ -z "$PRIMARY" ]; then
        echo "  [SKIP] No current primary reported. Skipping to avoid split-brain."
        send_ntfy "CNPG Primary Missing: ${NS}/${NAME}" "Cluster ${NS}/${NAME} reported no current primary. Auto-remediation blocked to avoid split-brain. Human investigation needed." 5 "rotating_light"
        emit_k8s_event "$NS" "$NAME" "PrimaryMissing" "Warning" "Cluster has no primary reported. Auto-remediation skipped."
        continue
    fi

    # Safety Check 2: Primary is healthy
    PRIMARY_POD_JSON=$(kubectl get pod "$PRIMARY" -n "$NS" -o json 2>/dev/null || true)
    if [ -z "$PRIMARY_POD_JSON" ]; then
        echo "  [ABORT] Primary pod '${PRIMARY}' not found in namespace '${NS}'. Skipping."
        send_ntfy "CNPG Primary Missing: ${NS}/${NAME}" "Primary pod '${PRIMARY}' not found in namespace '${NS}'. Auto-remediation blocked." 5 "rotating_light"
        emit_k8s_event "$NS" "$NAME" "PrimaryNotFound" "Warning" "Primary pod '${PRIMARY}' not found. Auto-remediation blocked."
        continue
    fi
    PRIMARY_READY=$(echo "$PRIMARY_POD_JSON" | jq -r '([.status.containerStatuses[]? | select(.ready == true)] | length) == (.status.containerStatuses? | length // 0)')
    PRIMARY_PHASE=$(echo "$PRIMARY_POD_JSON" | jq -r '.status.phase // ""')
    if [ "$PRIMARY_READY" != "true" ] || [ "$PRIMARY_PHASE" != "Running" ]; then
        echo "  [ABORT] Primary pod '${PRIMARY}' is not healthy (Phase: ${PRIMARY_PHASE}, Ready: ${PRIMARY_READY}). Skipping cluster."
        send_ntfy "CNPG Primary Unhealthy: ${NS}/${NAME}" "Primary pod '${PRIMARY}' is unhealthy (Phase: ${PRIMARY_PHASE}, Ready: ${PRIMARY_READY}). Auto-remediation blocked to avoid split-brain." 5 "rotating_light"
        emit_k8s_event "$NS" "$NAME" "PrimaryUnhealthy" "Warning" "Primary pod '${PRIMARY}' is unhealthy (Phase: ${PRIMARY_PHASE}, Ready: ${PRIMARY_READY}). Auto-remediation blocked."
        continue
    fi

    # Query instance pods for this cluster
    PODS_JSON=$(kubectl get pods -n "$NS" -l "cnpg.io/cluster=${NAME},cnpg.io/podRole=instance" -o json 2>/dev/null || true)
    if [ -z "$PODS_JSON" ]; then
        echo "  No instance pods found for cluster."
        continue
    fi

    # Find failing standbys (strictly excluding the primary)
    STANDBYS=$(echo "$PODS_JSON" | jq -c --arg p "$PRIMARY" --argjson min "$MIN_RESTARTS" '
        [ .items[] | select(.metadata.name != $p) ] |
        [ .[] |
          . as $pod |
          (if $pod.metadata.deletionTimestamp then "Terminating"
           elif ($pod.status.containerStatuses[]?.state.waiting.reason) then
             [$pod.status.containerStatuses[]?.state.waiting.reason][0]
           elif ($pod.status.containerStatuses[]?.state.terminated.reason) then
             [$pod.status.containerStatuses[]?.state.terminated.reason][0]
           else ($pod.status.phase // "Unknown") end
          ) as $status |
          ([$pod.status.containerStatuses[]?.restartCount // 0] | add // 0) as $restarts |
          ([$pod.status.containerStatuses[]? | select(.ready == true)] | length) as $ready_count |
          ($pod.status.containerStatuses? | length // 0) as $total_count |
          select(
            ($status != "Running" and $status != "Completed") or
            ($ready_count < $total_count and $restarts >= $min) or
            ($restarts >= $min and ($status == "CrashLoopBackOff" or $status == "Error"))
          ) |
          {
            name: $pod.metadata.name,
            status: $status,
            ready: "\($ready_count)/\($total_count)",
            restarts: $restarts
          }
        ] | sort_by(-.restarts)
    ')

    FAILING_COUNT=$(echo "$STANDBYS" | jq 'length')
    if [ "$FAILING_COUNT" -eq 0 ]; then
        echo "  ✔ All standby instances appear healthy."
        if [ "$PERSISTENT_ALERT_SENT" = "true" ]; then
            kubectl annotate cluster "$NAME" -n "$NS" "cnpg.io/persistent-alert-sent=false" --overwrite || true
            emit_k8s_event "$NS" "$NAME" "StandbyRecovered" "Normal" "All standby instances are now healthy."
        fi
        continue
    fi

    TARGET_STANDBY=$(echo "$STANDBYS" | jq -r '.[0].name')
    TARGET_STATUS=$(echo "$STANDBYS" | jq -r '.[0].status')
    TARGET_RESTARTS=$(echo "$STANDBYS" | jq -r '.[0].restarts')
    TARGET_READY=$(echo "$STANDBYS" | jq -r '.[0].ready')

    echo "  [TARGET] Found failing standby: ${TARGET_STANDBY} (Status: ${TARGET_STATUS}, Ready: ${TARGET_READY}, Restarts: ${TARGET_RESTARTS})"

    # Safety Check 3: Cooldown & Persistent Failure Check
    if [ -n "$LAST_REMEDIATED" ]; then
        LAST_SEC=$(parse_iso_to_epoch "$LAST_REMEDIATED")
        NOW_SEC=$(date "+%s")
        DIFF=$((NOW_SEC - LAST_SEC))
        if [ "$DIFF" -lt "$COOLDOWN_SECONDS" ]; then
            REMAINING=$((COOLDOWN_SECONDS - DIFF))
            echo "  [COOLDOWN] Cluster was remediated ${DIFF}s ago (< ${COOLDOWN_SECONDS}s). ${REMAINING}s remaining in cooldown."
            echo "  [PERSISTENT FAILURE] Standby '${TARGET_STANDBY}' is still failing despite recent remediation!"

            if [ "$PERSISTENT_ALERT_SENT" != "true" ]; then
                send_ntfy "CNPG Standby Still Failing: ${NS}/${NAME}" "Standby instance '${TARGET_STANDBY}' was remediated at ${LAST_REMEDIATED} (previous target: ${LAST_INSTANCE:-unknown}) but remains in failure state (${TARGET_STATUS}, ${TARGET_RESTARTS} restarts). Further auto-remediation suspended during cooldown." 4 "warning"
                emit_k8s_event "$NS" "$NAME" "StandbyStillFailing" "Warning" "Standby instance '${TARGET_STANDBY}' was remediated at ${LAST_REMEDIATED} but remains failing (${TARGET_STATUS})."
                kubectl annotate cluster "$NAME" -n "$NS" "cnpg.io/persistent-alert-sent=true" --overwrite || true
            fi
            continue
        fi
    fi

    # Check for Flapping / Repeat Remediation
    INT_REMEDIATION_COUNT=$(( ${REMEDIATION_COUNT:-0} ))
    NEXT_REMEDIATION_COUNT=$(( INT_REMEDIATION_COUNT + 1 ))

    if [ "$INT_REMEDIATION_COUNT" -gt 0 ]; then
        echo "  [FLAPPING DETECTED] Cluster has already been remediated ${INT_REMEDIATION_COUNT} time(s)."
        send_ntfy "CNPG Flapping Standby: ${NS}/${NAME}" "Cluster ${NS}/${NAME} requires repeat remediation (cycle #${NEXT_REMEDIATION_COUNT}). Standby '${TARGET_STANDBY}' repeatedly failing." 4 "warning"
        emit_k8s_event "$NS" "$NAME" "RemediationFlapping" "Warning" "Cluster requires repeat remediation (cycle #${NEXT_REMEDIATION_COUNT}) for standby ${TARGET_STANDBY}."
    fi

    # Find associated PVCs
    PVCS_JSON=$(kubectl get pvc -n "$NS" -l "cnpg.io/cluster=${NAME}" -o json 2>/dev/null || true)
    TARGET_PVCS=()
    if [ -n "$PVCS_JSON" ]; then
        readarray -t TARGET_PVCS < <(echo "$PVCS_JSON" | jq -r --arg inst "$TARGET_STANDBY" '
            [ .items[] | select(.metadata.labels["cnpg.io/instanceName"] == $inst or .metadata.name == $inst or .metadata.name == ($inst + "-wal")) | .metadata.name ] | .[]
        ')
    fi

    echo "  Target PVCs: ${TARGET_PVCS[*]:-(none found)}"

    if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY-RUN] Would delete Pod '${TARGET_STANDBY}' and PVCs: ${TARGET_PVCS[*]:-}"
    else
        echo "  Executing remediation..."
        # Delete Pod
        echo "  Deleting Pod: ${TARGET_STANDBY}"
        kubectl delete pod "$TARGET_STANDBY" -n "$NS" --wait=false || true

        # Delete PVCs
        if [ ${#TARGET_PVCS[@]} -gt 0 ]; then
            for pvc in "${TARGET_PVCS[@]}"; do
                echo "  Deleting PVC: ${pvc}"
                kubectl delete pvc "$pvc" -n "$NS" --wait=false || true
            done
        fi

        # Annotate cluster with timestamp, instance, and count
        TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        echo "  Setting remediation annotations (count=${NEXT_REMEDIATION_COUNT}, timestamp=${TIMESTAMP})"
        kubectl annotate cluster "$NAME" -n "$NS" \
            "cnpg.io/last-remediated-at=${TIMESTAMP}" \
            "cnpg.io/last-remediated-instance=${TARGET_STANDBY}" \
            "cnpg.io/remediation-count=${NEXT_REMEDIATION_COUNT}" \
            "cnpg.io/persistent-alert-sent=false" \
            --overwrite || true

        # Emit normal event and send ntfy notification
        send_ntfy "CNPG Standby Remediated: ${NS}/${NAME}" "Deleted failing standby pod '${TARGET_STANDBY}' (Restarts: ${TARGET_RESTARTS}) and associated PVCs (${TARGET_PVCS[*]}). CloudNativePG operator will reprovision." 3 "white_check_mark"
        emit_k8s_event "$NS" "$NAME" "StandbyRemediated" "Normal" "Cleaned up failing standby pod '${TARGET_STANDBY}' and associated PVCs (${TARGET_PVCS[*]}). Reprovisioning initiated."

        echo "  [REMEDIATED] Completed remediation for ${TARGET_STANDBY}. Operator will reprovision."
    fi

    REMEDIATED_COUNT=$((REMEDIATED_COUNT + 1))
    echo ""

    if [ "$MAX_CLUSTERS" -gt 0 ] && [ "$REMEDIATED_COUNT" -ge "$MAX_CLUSTERS" ]; then
        echo "Reached maximum clusters to remediate per run limit (${REMEDIATED_COUNT}/${MAX_CLUSTERS}). Stopping execution for this cycle."
        break
    fi
done < <(echo "$CLUSTERS_JSON" | jq -c '.items[]')

echo "=========================================================="
echo "CloudNativePG Auto-Remediator run finished at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=========================================================="
