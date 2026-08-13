#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script as root: sudo ./scripts/install.sh" >&2
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_USER="reliability-web"
INSTALL_DIR="/opt/reliability-web"

echo "Installing Reliability Lab services..."

if ! getent group "$SERVICE_USER" >/dev/null; then
    groupadd --system "$SERVICE_USER"
fi

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd \
        --system \
        --gid "$SERVICE_USER" \
        --home-dir /nonexistent \
        --shell /usr/sbin/nologin \
        "$SERVICE_USER"
fi

install -d \
    -o root \
    -g "$SERVICE_USER" \
    -m 0750 \
    "$INSTALL_DIR"

install \
    -o root \
    -g "$SERVICE_USER" \
    -m 0640 \
    "$PROJECT_DIR/index.html" \
    "$INSTALL_DIR/index.html"

install \
    -o root \
    -g "$SERVICE_USER" \
    -m 0750 \
    "$PROJECT_DIR/check-health.sh" \
    "$INSTALL_DIR/check-health.sh"

install -m 0644 \
    "$PROJECT_DIR/systemd/reliability-web.service" \
    /etc/systemd/system/reliability-web.service

install -m 0644 \
    "$PROJECT_DIR/systemd/reliability-health.service" \
    /etc/systemd/system/reliability-health.service

install -m 0644 \
    "$PROJECT_DIR/systemd/reliability-health.timer" \
    /etc/systemd/system/reliability-health.timer

systemctl daemon-reload
systemctl enable reliability-web.service
systemctl enable reliability-health.timer
systemctl restart reliability-web.service
systemctl restart reliability-health.timer

echo "Installation complete."
