#!/usr/bin/env bash

set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script as root: sudo ./scripts/install-monitoring.sh" >&2
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONITORING_DIR="$PROJECT_DIR/monitoring"
ENV_FILE="$MONITORING_DIR/.env"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2 openssl
systemctl enable --now docker.service

if [[ ! -f "$ENV_FILE" ]]; then
    umask 077
    printf 'GRAFANA_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 16)" > "$ENV_FILE"
fi

cd "$MONITORING_DIR"
docker compose pull
docker compose up -d

echo "Monitoring stack started."
echo "Grafana user: admin"
echo "Grafana password is stored in $ENV_FILE with mode 0600."
echo "Read it locally with: sudo sed -n 's/^GRAFANA_ADMIN_PASSWORD=//p' $ENV_FILE"
