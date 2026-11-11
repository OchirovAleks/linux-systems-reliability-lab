# Runbook: Kubernetes Workload Down

## Trigger

Use this runbook when the Kubernetes endpoint on NodePort `30080` is
unavailable or the `reliability-web` Deployment has unavailable replicas.

## Triage

Inspect the workload from the control-plane node:

    sudo k3s kubectl -n reliability-lab get deployment,pods,service -o wide
    sudo k3s kubectl -n reliability-lab describe deployment reliability-web
    sudo k3s kubectl -n reliability-lab get events --sort-by=.lastTimestamp

Inspect one failing Pod:

    sudo k3s kubectl -n reliability-lab describe pod POD_NAME
    sudo k3s kubectl -n reliability-lab logs POD_NAME

## Diagnosis

Check, in order:

- whether both Kubernetes Nodes are `Ready`;
- whether the Deployment has two desired and ready replicas;
- Pod status and restart count;
- scheduling or image errors in Pod events;
- readiness, liveness, and startup probe failures;
- whether the Service has ready endpoints;
- whether NodePort `30080` responds on either node.

Common states include `Pending`, `ErrImageNeverPull`, `CrashLoopBackOff`,
`OOMKilled`, and probe failures.

## Recovery

Reapply the checked-in desired state:

    ./scripts/deploy-kubernetes.sh

Restart Pods without changing the Deployment specification:

    sudo k3s kubectl -n reliability-lab rollout restart deployment/reliability-web
    sudo k3s kubectl -n reliability-lab rollout status deployment/reliability-web

If a node is unavailable, diagnose the K3s service and Linux host before
returning the node to scheduling.

## Verification

Run:

    ./scripts/verify-kubernetes.sh

Attach Pod descriptions, events, logs, node status, and the remediation steps
to the incident record.
