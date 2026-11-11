#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECTL=(sudo k3s kubectl)

if ! command -v k3s >/dev/null 2>&1; then
    echo "k3s is required; run ./scripts/install-k3s.sh first" >&2
    exit 1
fi

"${KUBECTL[@]}" apply -f "$PROJECT_DIR/kubernetes/namespace.yaml"
"${KUBECTL[@]}" apply -f "$PROJECT_DIR/kubernetes/deployment.yaml"
"${KUBECTL[@]}" apply -f "$PROJECT_DIR/kubernetes/service.yaml"
"${KUBECTL[@]}" apply -f "$PROJECT_DIR/kubernetes/pod-disruption-budget.yaml"

"${KUBECTL[@]}" -n reliability-lab rollout status \
    deployment/reliability-web --timeout=180s
"${KUBECTL[@]}" -n reliability-lab get pods -o wide
"${KUBECTL[@]}" -n reliability-lab get service reliability-web
