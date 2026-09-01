#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$PROJECT_DIR/ansible"
SSH_KEY="/home/ubuntu/.ssh/fleet_lab_ed25519"

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "ansible-playbook is required" >&2
    exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
    echo "fleet SSH key not found: $SSH_KEY" >&2
    exit 1
fi

cd "$ANSIBLE_DIR"
ansible-playbook playbook.yml --diff "$@"
