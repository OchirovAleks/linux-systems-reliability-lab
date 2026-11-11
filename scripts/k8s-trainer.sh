#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRAINING_DIR="$PROJECT_DIR/kubernetes/training"
NAMESPACE="reliability-training"
WORKER_HOST="${K3S_WORKER:-192.168.252.3}"
SSH_KEY="${FLEET_SSH_KEY:-/home/ubuntu/.ssh/fleet_lab_ed25519}"
KUBECTL=(sudo k3s kubectl)

usage() {
    cat <<'EOF'
Usage:
  ./scripts/k8s-trainer.sh list
  ./scripts/k8s-trainer.sh start SCENARIO --yes
  ./scripts/k8s-trainer.sh status
  ./scripts/k8s-trainer.sh evidence [SCENARIO]
  ./scripts/k8s-trainer.sh recover SCENARIO --yes
  ./scripts/k8s-trainer.sh reset --yes

Scenarios:
  crashloop         Container repeatedly exits with status 1
  oomkilled         Container exceeds its memory limit
  unschedulable     Pod requests more CPU and memory than the cluster has
  readiness-failure Application runs but never becomes Ready
  image-missing     Pod references an image unavailable on the node
  node-not-ready    Stops the K3s agent on fleet-node-1
EOF
}

require_tools() {
    for command in k3s curl python3; do
        if ! command -v "$command" >/dev/null 2>&1; then
            echo "$command is required" >&2
            exit 1
        fi
    done
}

has_confirmation() {
    local argument
    for argument in "$@"; do
        if [[ "$argument" == "--yes" ]]; then
            return 0
        fi
    done
    return 1
}

require_confirmation() {
    if ! has_confirmation "$@"; then
        echo "This operation changes the training environment; add --yes" >&2
        exit 2
    fi
}

manifest_for() {
    case "$1" in
        crashloop|oomkilled|unschedulable|readiness-failure|image-missing)
            printf '%s/%s.yaml\n' "$TRAINING_DIR" "$1"
            ;;
        node-not-ready)
            return 1
            ;;
        *)
            echo "unknown scenario: $1" >&2
            return 2
            ;;
    esac
}

ensure_training_namespace() {
    "${KUBECTL[@]}" apply -f "$TRAINING_DIR/namespace.yaml" >/dev/null
}

show_alerts() {
    echo
    echo "Kubernetes Prometheus alerts:"
    curl --fail --silent --show-error \
        http://127.0.0.1:9090/api/v1/alerts \
        | python3 -c '
import json
import sys

alerts = json.load(sys.stdin)["data"]["alerts"]
selected = [
    alert for alert in alerts
    if alert.get("labels", {}).get("alertname", "").startswith("Kubernetes")
]
if not selected:
    print("none")
for alert in selected:
    labels = alert["labels"]
    state = alert["state"]
    name = labels.get("alertname", "unknown")
    namespace = labels.get("namespace", "-")
    pod = labels.get("pod", "-")
    node = labels.get("node", "-")
    deployment = labels.get("deployment", "-")
    print(
        f"{state:<8} {name} namespace={namespace} "
        f"deployment={deployment} pod={pod} node={node}"
    )
'
}

start_scenario() {
    local scenario="$1"
    local manifest

    require_confirmation "$@"
    ensure_training_namespace

    if [[ "$scenario" == "node-not-ready" ]]; then
        if [[ ! -f "$SSH_KEY" ]]; then
            echo "fleet SSH key not found: $SSH_KEY" >&2
            exit 1
        fi
        ssh -o BatchMode=yes -i "$SSH_KEY" "ubuntu@$WORKER_HOST" \
            sudo -n systemctl stop k3s-agent
        echo "Scenario started: node-not-ready"
        echo "The Kubernetes control plane may take about one minute to mark the node NotReady."
        return
    fi

    manifest="$(manifest_for "$scenario")"
    "${KUBECTL[@]}" apply -f "$manifest"
    echo "Scenario started: $scenario"
    echo "Use './scripts/k8s-trainer.sh evidence $scenario' to investigate."
}

recover_scenario() {
    local scenario="$1"
    local manifest

    require_confirmation "$@"

    if [[ "$scenario" == "node-not-ready" ]]; then
        if [[ ! -f "$SSH_KEY" ]]; then
            echo "fleet SSH key not found: $SSH_KEY" >&2
            exit 1
        fi
        ssh -o BatchMode=yes -i "$SSH_KEY" "ubuntu@$WORKER_HOST" \
            sudo -n systemctl start k3s-agent
        "${KUBECTL[@]}" wait --for=condition=Ready node/fleet-node-1 --timeout=180s
        echo "Scenario recovered: node-not-ready"
        return
    fi

    manifest="$(manifest_for "$scenario")"
    "${KUBECTL[@]}" delete -f "$manifest" --ignore-not-found=true
    echo "Scenario recovered: $scenario"
}

show_status() {
    "${KUBECTL[@]}" get nodes -o wide
    echo
    "${KUBECTL[@]}" -n "$NAMESPACE" get deployments,pods -o wide 2>/dev/null \
        || echo "No active training namespace or scenarios."
    show_alerts
}

collect_evidence() {
    local scenario="${1:-}"

    "${KUBECTL[@]}" get nodes -o wide
    echo
    "${KUBECTL[@]}" -n "$NAMESPACE" get deployments,pods -o wide 2>/dev/null \
        || true
    echo
    "${KUBECTL[@]}" -n "$NAMESPACE" get events \
        --sort-by=.lastTimestamp 2>/dev/null || true

    if [[ "$scenario" == "node-not-ready" ]]; then
        echo
        "${KUBECTL[@]}" describe node fleet-node-1
    elif [[ -n "$scenario" ]]; then
        manifest_for "$scenario" >/dev/null
        echo
        "${KUBECTL[@]}" -n "$NAMESPACE" describe deployment "$scenario" \
            2>/dev/null || true
        echo
        "${KUBECTL[@]}" -n "$NAMESPACE" describe pods \
            -l "reliability-lab/scenario=$scenario" 2>/dev/null || true
        echo
        "${KUBECTL[@]}" -n "$NAMESPACE" logs \
            -l "reliability-lab/scenario=$scenario" --tail=30 \
            --all-containers=true 2>/dev/null || true
    fi

    show_alerts
}

reset_training() {
    require_confirmation "$@"

    if [[ -f "$SSH_KEY" ]]; then
        ssh -o BatchMode=yes -i "$SSH_KEY" "ubuntu@$WORKER_HOST" \
            sudo -n systemctl start k3s-agent
        "${KUBECTL[@]}" wait --for=condition=Ready node/fleet-node-1 \
            --timeout=180s
    fi

    "${KUBECTL[@]}" delete namespace "$NAMESPACE" \
        --ignore-not-found=true --wait=true
    ensure_training_namespace
    echo "Training environment reset."
}

require_tools

command="${1:-help}"
scenario="${2:-}"

case "$command" in
    list)
        usage
        ;;
    start)
        [[ -n "$scenario" ]] || { usage >&2; exit 2; }
        start_scenario "$scenario" "${@:3}"
        ;;
    status)
        show_status
        ;;
    evidence)
        collect_evidence "$scenario"
        ;;
    recover)
        [[ -n "$scenario" ]] || { usage >&2; exit 2; }
        recover_scenario "$scenario" "${@:3}"
        ;;
    reset)
        reset_training "${@:2}"
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
