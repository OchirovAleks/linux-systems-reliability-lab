#!/usr/bin/env bash

set -euo pipefail

KUBECTL=(sudo k3s kubectl)
NAMESPACE="reliability-lab"
SELECTOR="app.kubernetes.io/name=reliability-web"

if ! command -v k3s >/dev/null 2>&1; then
    echo "k3s is required" >&2
    exit 1
fi

"${KUBECTL[@]}" wait --for=condition=Ready nodes --all --timeout=120s
"${KUBECTL[@]}" -n "$NAMESPACE" rollout status \
    deployment/reliability-web --timeout=120s

pod_json="$("${KUBECTL[@]}" -n "$NAMESPACE" get pods -l "$SELECTOR" -o json)"
python3 -c '
import json
import sys

data = json.load(sys.stdin)
pods = [
    pod for pod in data["items"]
    if "deletionTimestamp" not in pod["metadata"]
]
if len(pods) != 2:
    raise SystemExit(f"expected 2 pods, found {len(pods)}")

nodes = set()
for pod in pods:
    name = pod["metadata"]["name"]
    node = pod["spec"].get("nodeName")
    ready = any(
        condition["type"] == "Ready" and condition["status"] == "True"
        for condition in pod.get("status", {}).get("conditions", [])
    )
    if not ready:
        raise SystemExit(f"pod is not ready: {name}")
    nodes.add(node)

if len(nodes) != 2:
    raise SystemExit(f"expected pods on 2 nodes, found: {sorted(nodes)}")

print(f"Kubernetes pods ready on nodes: {sorted(nodes)}")
' <<<"$pod_json"

for endpoint in \
    http://192.168.252.2:30080/ \
    http://192.168.252.3:30080/; do
    curl --fail --silent --show-error --output /dev/null \
        --connect-timeout 2 --max-time 5 "$endpoint"
    echo "UP: $endpoint"
done

kubernetes_web_count="$(
    curl --fail --silent --show-error \
        --get \
        --data-urlencode 'query=sum(probe_success{job="kubernetes-web"})' \
        http://127.0.0.1:9090/api/v1/query \
        | python3 -c 'import json,sys; result=json.load(sys.stdin)["data"]["result"]; print(result[0]["value"][1] if result else "missing")'
)"

if [[ "$kubernetes_web_count" != "2" ]]; then
    echo "Unexpected Kubernetes HTTP probe total: $kubernetes_web_count" >&2
    exit 1
fi

echo "Prometheus Kubernetes HTTP probes: $kubernetes_web_count"

"${KUBECTL[@]}" -n "$NAMESPACE" get deployment,pods,service,poddisruptionbudget -o wide
echo "Kubernetes lab verification passed."
