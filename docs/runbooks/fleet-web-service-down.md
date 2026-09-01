# Runbook: Fleet Web Service Down

## Trigger

Use this runbook when:

- `FleetWebServiceDown` is firing in Prometheus or Alertmanager;
- `fleetctl health` reports `WEB DOWN` for one or more nodes;
- a customer-facing HTTP check fails.

## Impact

The affected node remains online, but its web workload is unavailable. Other
fleet nodes may continue serving normally.

## Triage

List fleet health from the control node:

    ./scripts/fleetctl.py health

Collect evidence from the affected node:

    ./scripts/fleetctl.py diagnose fleet-node-1

Confirm the alert state:

    curl -s http://127.0.0.1:9090/api/v1/alerts

## Diagnosis

Review the following evidence before changing the node:

- `systemctl is-active reliability-web`;
- failed systemd units;
- root filesystem capacity;
- available memory;
- listening ports `8080` and `9100`;
- recent `reliability-web` journal entries.

If the service is inactive and no broader node failure is present, continue
with service recovery. If SSH and Node Exporter are also unavailable, treat the
incident as a node or network failure and escalate.

## Recovery

Start an intentionally stopped service:

    ./scripts/fleetctl.py start fleet-node-1 --yes

Restart an unhealthy running service:

    ./scripts/fleetctl.py restart fleet-node-1 --yes

## Verification

Run the complete lab verification:

    ./scripts/verify-lab.sh

Confirm that the Prometheus alert returns to the `inactive` state and that
Alertmanager no longer lists an active alert.

## Escalation

Escalate when:

- the service fails repeatedly after recovery;
- the node is unreachable over SSH;
- Node Exporter is also unavailable;
- kernel, storage, memory, or network errors are present;
- multiple nodes exhibit the same failure pattern.

Attach `fleetctl diagnose` output, relevant journal entries, alert timestamps,
and the remediation actions already attempted.
