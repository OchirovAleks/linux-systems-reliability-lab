#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$PROJECT_DIR/scripts/fleetctl.py" health

for endpoint in \
    http://127.0.0.1:9090/-/ready \
    http://127.0.0.1:9093/-/ready \
    http://127.0.0.1:9115/-/healthy \
    http://127.0.0.1:3000/api/health; do
    curl --fail --silent --show-error --output /dev/null "$endpoint"
    echo "UP: $endpoint"
done

node_count="$(
    curl --fail --silent --show-error \
        --get \
        --data-urlencode 'query=sum(up{job="node"})' \
        http://127.0.0.1:9090/api/v1/query \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["result"][0]["value"][1])'
)"

web_count="$(
    curl --fail --silent --show-error \
        --get \
        --data-urlencode 'query=sum(probe_success{job="web"})' \
        http://127.0.0.1:9090/api/v1/query \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["result"][0]["value"][1])'
)"

if [[ "$node_count" != "2" || "$web_count" != "2" ]]; then
    echo "Unexpected Prometheus totals: nodes=$node_count web=$web_count" >&2
    exit 1
fi

active_alerts="$(
    curl --fail --silent --show-error \
        http://127.0.0.1:9090/api/v1/alerts \
        | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]["alerts"]))'
)"

if [[ "$active_alerts" != "0" ]]; then
    echo "Unexpected active Prometheus alerts: $active_alerts" >&2
    exit 1
fi

echo "Prometheus totals: nodes=$node_count web=$web_count"
echo "Active Prometheus alerts: $active_alerts"
echo "Lab verification passed."
