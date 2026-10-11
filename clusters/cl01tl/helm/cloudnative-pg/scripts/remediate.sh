#!/usr/bin/env bash
set -euo pipefail

MIN_RESTARTS="${MIN_RESTARTS:-5}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-3600}"
DRY_RUN="${DRY_RUN:-false}"

echo "=========================================================="
echo "Starting CloudNativePG Auto-Remediator at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Configuration: MIN_RESTARTS=${MIN_RESTARTS}, COOLDOWN_SECONDS=${COOLDOWN_SECONDS}, DRY_RUN=${DRY_RUN}"
echo "=========================================================="

parse_iso_to_epoch() {
    local iso="$1"
    if date --version &>/dev/null || date -d "@0" &>/dev/null; then
        date -d "$iso" +%s 2>/dev/null || echo 0
    else
        date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" "+%s" 2>/dev/null || echo 0
    fi
}

CLUSTERS_JSON=$(kubectl get clusters.postgresql.cnpg.io -A -o json 2>/dev/null || true)
if [ -z "$CLUSTERS_JSON" ] || [ "$(echo "$CLUSTERS_JSON" | jq '.items | length')" -eq 0 ]; then
    echo "No CNPG clusters found in the cluster."
    exit 0
fi

TOTAL_CLUSTERS=$(echo "$CLUSTERS_JSON" | jq '.items | length')
echo "Discovered ${TOTAL_CLUSTERS} CNPG cluster(s)."

echo "$CLUSTERS_JSON" | jq -c '.items[]' | while read -r cluster; do
    NS=$(echo "$cluster" | jq -r '.metadata.namespace')
    NAME=$(echo "$cluster" | jq -r '.metadata.name')
    PHASE=$(echo "$cluster" | jq -r '.status.phase // "Unknown"')
    PRIMARY=$(echo "$cluster" | jq -r '.status.currentPrimary // ""')
    LAST_REMEDIATED=$(echo "$cluster" | jq -r '.metadata.annotations["cnpg.io/last-remediated-at"] // ""')

    echo "--- Cluster: ${NS}/${NAME} (Phase: ${PHASE}, Primary: ${PRIMARY}) ---"

    # Safety Check 1: Primary exists
    if [ -z "$PRIMARY" ]; then
        echo "  [SKIP] No current primary reported. Skipping to avoid split-brain."
        continue
    fi

    # Safety Check 2: Primary is healthy
    PRIMARY_POD_JSON=$(kubectl get pod "$PRIMARY" -n "$NS" -o json 2>/dev/null || true)
    if [ -z "$PRIMARY_POD_JSON" ]; then
        echo "  [ABORT] Primary pod '${PRIMARY}' not found in namespace '${NS}'. Skipping."
        continue
    fi
    PRIMARY_READY=$(echo "$PRIMARY_POD_JSON" | jq -r '([.status.containerStatuses[]? | select(.ready == true)] | length) == (.status.containerStatuses? | length // 0)')
    PRIMARY_PHASE=$(echo "$PRIMARY_POD_JSON" | jq -r '.status.phase // ""')
    if [ "$PRIMARY_READY" != "true" ] || [ "$PRIMARY_PHASE" != "Running" ]; then
        echo "  [ABORT] Primary pod '${PRIMARY}' is not healthy (Phase: ${PRIMARY_PHASE}, Ready: ${PRIMARY_READY}). Skipping cluster."
        continue
    fi

    # Safety Check 3: Cooldown / Flap protection
    if [ -n "$LAST_REMEDIATED" ]; then
        LAST_SEC=$(parse_iso_to_epoch "$LAST_REMEDIATED")
        NOW_SEC=$(date "+%s")
        DIFF=$((NOW_SEC - LAST_SEC))
        if [ "$DIFF" -lt "$COOLDOWN_SECONDS" ]; then
            REMAINING=$((COOLDOWN_SECONDS - DIFF))
            echo "  [COOLDOWN] Cluster was remediated ${DIFF}s ago (< ${COOLDOWN_SECONDS}s). ${REMAINING}s remaining in cooldown. Skipping."
            continue
        fi
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
        echo "  All standby instances appear healthy."
        continue
    fi

    # Safety Check 4: Rate limit to 1 instance per cluster per run
    TARGET_STANDBY=$(echo "$STANDBYS" | jq -r '.[0].name')
    TARGET_STATUS=$(echo "$STANDBYS" | jq -r '.[0].status')
    TARGET_RESTARTS=$(echo "$STANDBYS" | jq -r '.[0].restarts')
    TARGET_READY=$(echo "$STANDBYS" | jq -r '.[0].ready')

    echo "  [TARGET] Found failing standby: ${TARGET_STANDBY} (Status: ${TARGET_STATUS}, Ready: ${TARGET_READY}, Restarts: ${TARGET_RESTARTS})"

    # Find associated PVCs
    PVCS_JSON=$(kubectl get pvc -n "$NS" -l "cnpg.io/cluster=${NAME}" -o json 2>/dev/null || true)
    TARGET_PVCS=()
    if [ -n "$PVCS_JSON" ]; then
        TARGET_PVCS=($(echo "$PVCS_JSON" | jq -r --arg inst "$TARGET_STANDBY" '
            [ .items[] | select(.metadata.labels["cnpg.io/instanceName"] == $inst or .metadata.name == $inst or .metadata.name == ($inst + "-wal")) | .metadata.name ] | .[]
        '))
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

        # Annotate cluster with timestamp for cooldown
        TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        echo "  Setting cooldown annotation cnpg.io/last-remediated-at=${TIMESTAMP}"
        kubectl annotate cluster "$NAME" -n "$NS" "cnpg.io/last-remediated-at=${TIMESTAMP}" --overwrite || true
        echo "  [REMEDIATED] Completed remediation for ${TARGET_STANDBY}. Operator will reprovision."
    fi
done

echo "=========================================================="
echo "CloudNativePG Auto-Remediator run finished at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=========================================================="
