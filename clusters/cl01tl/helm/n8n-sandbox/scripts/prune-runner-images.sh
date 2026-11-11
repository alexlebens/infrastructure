#!/usr/bin/env bash
set -eo pipefail

echo "Discovering active n8n runner pods in namespace ${NAMESPACE:-n8n-sandbox}..."
RUNNERS=$(kubectl get pods -n "${NAMESPACE:-n8n-sandbox}" -l app.kubernetes.io/name=n8n-sandbox,app.kubernetes.io/component=privileged-runner -o jsonpath='{.items[*].metadata.name}')

if [ -z "$RUNNERS" ]; then
  echo "No n8n runner pods found."
  exit 0
fi

for POD in $RUNNERS; do
  echo "Pruning unused docker images on $POD (runner)..."
  kubectl exec -n "${NAMESPACE:-n8n-sandbox}" "$POD" -c runner -- docker image prune -a -f || {
    echo "Warning: Failed to prune images on $POD, continuing..."
  }
done

echo "Runner image prune sweep completed successfully."
