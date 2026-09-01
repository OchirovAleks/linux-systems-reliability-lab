# Postmortem: Fleet Node 1 Web Service Outage

## Summary

On 2026-09-01, a controlled failure-injection exercise stopped
`reliability-web.service` on `fleet-node-1`. The node and its metrics endpoint
remained available while the web workload was unavailable for 77 seconds.

Prometheus detected the failed HTTP probe, transitioned the
`FleetWebServiceDown` alert from `pending` to `firing`, and cleared the alert
after service recovery. No customer traffic or production system was involved.

## Timeline

All timestamps use the `America/New_York` timezone configured on the node.

- **14:35:13** - `fleetctl stop fleet-node-1 --yes` stopped the web service.
- **14:35:13** - `fleetctl health` reported `WEB DOWN`, `METRICS UP`.
- **14:35:53** - Prometheus reported `FleetWebServiceDown` as `pending`.
- **~14:36:13** - The alert transitioned to `firing` after the 30-second threshold.
- **14:36:30** - `fleetctl start fleet-node-1 --yes` restored the service.
- **14:36:45** - The external HTTP probe received a successful response.
- **14:36:55** - The internal systemd health check completed successfully.
- **14:37:26** - Verification confirmed zero failed units and zero active alerts.

## Detection

The failure was detected through two independent paths:

- `fleetctl health` returned a non-zero exit code and reported `WEB DOWN`;
- Prometheus Blackbox Exporter set `probe_success` to `0`, activating the
  `FleetWebServiceDown` rule.

Node Exporter remained reachable, showing that the failure affected the
application layer rather than the entire node or network path.

## Root Cause

The service was intentionally stopped as part of a controlled reliability
exercise. systemd did not restart it because an administrative stop is not a
process failure and therefore does not trigger `Restart=on-failure`.

## Resolution

The service was restored with:

    ./scripts/fleetctl.py start fleet-node-1 --yes

Recovery was verified through HTTP probes, Node Exporter availability, the
systemd health timer, Prometheus alert state, and the complete lab verification
script.

## What Worked

- Fleet health checks isolated the failed workload from the healthy node.
- Metrics remained available during the application outage.
- The alert threshold avoided immediate alerting on a transient failure.
- Remote diagnostics collected system and service evidence before recovery.
- The service and alert recovered without restarting the node.

## Improvement Actions

- Include the active-alert count in `scripts/verify-lab.sh`.
- Document that alert resolution may require an additional evaluation cycle.
- Preserve application, node, and monitoring checks as independent signals.
- Add future exercises for node loss, CPU pressure, disk pressure, and network
  failure.
