#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${RELIABILITY_IMAGE:-reliability-web:0.1.0}"
WORKER="${K3S_WORKER:-192.168.252.3}"
SSH_KEY="${FLEET_SSH_KEY:-/home/ubuntu/.ssh/fleet_lab_ed25519}"
IMAGE_ARCHIVE="$(mktemp /tmp/reliability-web-image.XXXXXX.tar)"
REMOTE_ARCHIVE="/tmp/reliability-web-image.tar"

cleanup() {
    rm -f "$IMAGE_ARCHIVE"
    ssh -o BatchMode=yes -i "$SSH_KEY" "ubuntu@$WORKER" \
        "rm -f '$REMOTE_ARCHIVE'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for command in docker k3s ssh scp; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "$command is required" >&2
        exit 1
    fi
done

if [[ ! -f "$SSH_KEY" ]]; then
    echo "fleet SSH key not found: $SSH_KEY" >&2
    exit 1
fi

echo "Building $IMAGE..."
sudo docker build \
    --file "$PROJECT_DIR/container/Dockerfile" \
    --tag "$IMAGE" \
    "$PROJECT_DIR"

sudo docker save "$IMAGE" | dd of="$IMAGE_ARCHIVE" status=none

echo "Importing $IMAGE on the control-plane node..."
sudo k3s ctr images import "$IMAGE_ARCHIVE"

echo "Importing $IMAGE on $WORKER..."
scp -o BatchMode=yes -i "$SSH_KEY" \
    "$IMAGE_ARCHIVE" "ubuntu@$WORKER:$REMOTE_ARCHIVE"
ssh -o BatchMode=yes -i "$SSH_KEY" "ubuntu@$WORKER" \
    "sudo -n k3s ctr images import '$REMOTE_ARCHIVE'"

echo "Kubernetes image imported on both nodes."
