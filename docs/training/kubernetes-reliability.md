# Kubernetes Reliability Training Guide

This guide turns the lab into a controlled incident-response environment for
fleet operations practice. Each exercise follows the same operational loop:

1. introduce one failure;
2. observe the symptom without guessing the cause;
3. collect Kubernetes, event, metric, and alert evidence;
4. identify the failed layer;
5. recover the workload;
6. verify that service and monitoring returned to normal.

## Safety Model

Application-level incidents run only in the `reliability-training` namespace.
They do not modify the primary `reliability-lab` Deployment. The
`node-not-ready` exercise is different: it stops the K3s agent on
`fleet-node-1`, so run it only after the other scenarios and recover it before
ending the session.

Run one scenario at a time. Before and after a session, use:

```bash
./scripts/k8s-trainer.sh reset --yes
./scripts/verify-kubernetes.sh
```

The `--yes` flag is deliberately required for commands that change the lab.

## Investigation Workflow

Start a scenario:

```bash
./scripts/k8s-trainer.sh start SCENARIO --yes
```

Inspect the fleet and active training workloads:

```bash
./scripts/k8s-trainer.sh status
```

Collect detailed evidence:

```bash
./scripts/k8s-trainer.sh evidence SCENARIO
```

Also open the **Kubernetes Reliability Trainer** Grafana dashboard. Alerts
have pending periods, so a symptom can appear in Kubernetes before the related
alert begins firing.

Recover and verify:

```bash
./scripts/k8s-trainer.sh recover SCENARIO --yes
./scripts/verify-kubernetes.sh
```

## Scenario Reference

### 1. CrashLoopBackOff

```bash
./scripts/k8s-trainer.sh start crashloop --yes
```

Expected evidence:

- the container terminates with exit code `1`;
- Kubernetes repeatedly restarts it;
- Pod status eventually becomes `CrashLoopBackOff`;
- restart count rises;
- `KubernetesPodCrashLooping` and replica-mismatch alerts fire after their
  pending periods.

Operational lesson: distinguish a running Pod from a healthy application and
use previous container state, exit code, events, and logs together.

```bash
./scripts/k8s-trainer.sh evidence crashloop
./scripts/k8s-trainer.sh recover crashloop --yes
```

### 2. OOMKilled

```bash
./scripts/k8s-trainer.sh start oomkilled --yes
```

Expected evidence:

- memory use reaches the container limit;
- the kernel terminates the container;
- its previous termination reason is `OOMKilled`;
- the restart count rises;
- `KubernetesContainerOOMKilled` fires.

Operational lesson: separate Kubernetes resource limits from physical node
memory and confirm an out-of-memory diagnosis from termination state.

```bash
./scripts/k8s-trainer.sh evidence oomkilled
./scripts/k8s-trainer.sh recover oomkilled --yes
```

### 3. Unschedulable Pod

```bash
./scripts/k8s-trainer.sh start unschedulable --yes
```

Expected evidence:

- the Pod remains `Pending`;
- no node is assigned;
- scheduler events report insufficient CPU and memory;
- `KubernetesPodUnschedulable` and replica-mismatch alerts fire.

Operational lesson: a Pending Pod is not necessarily a networking or image
problem; scheduler events explain why placement failed.

```bash
./scripts/k8s-trainer.sh evidence unschedulable
./scripts/k8s-trainer.sh recover unschedulable --yes
```

### 4. Readiness Failure

```bash
./scripts/k8s-trainer.sh start readiness-failure --yes
```

Expected evidence:

- the container is `Running`;
- the Pod remains `0/1 Ready`;
- readiness-probe events show HTTP `404` responses;
- the Deployment has no available replica;
- the replica-mismatch alert fires.

Operational lesson: process health and traffic readiness are different states.
Kubernetes can keep a running container out of Service endpoints.

```bash
./scripts/k8s-trainer.sh evidence readiness-failure
./scripts/k8s-trainer.sh recover readiness-failure --yes
```

### 5. Missing Image

```bash
./scripts/k8s-trainer.sh start image-missing --yes
```

Expected evidence:

- the Pod does not start;
- status becomes `ErrImageNeverPull`;
- events show that the local image is absent;
- the Deployment has no available replica;
- the replica-mismatch alert fires.

Operational lesson: identify image distribution and pull-policy failures before
debugging application code.

```bash
./scripts/k8s-trainer.sh evidence image-missing
./scripts/k8s-trainer.sh recover image-missing --yes
```

### 6. Node NotReady

```bash
./scripts/k8s-trainer.sh start node-not-ready --yes
```

The control plane can take about one minute to mark a silent node `NotReady`.
Expected evidence:

- `fleet-node-1` changes from `Ready` to `NotReady`;
- node conditions show missed heartbeats;
- the main workload keeps one healthy replica on the control node;
- `KubernetesNodeNotReady` fires after its one-minute pending period.

Operational lesson: determine whether failure belongs to the application, the
container runtime, the Kubernetes agent, or the node itself, and evaluate the
remaining service capacity before remediation.

```bash
./scripts/k8s-trainer.sh evidence node-not-ready
./scripts/k8s-trainer.sh recover node-not-ready --yes
```

## End-of-Session Check

```bash
./scripts/k8s-trainer.sh reset --yes
./scripts/verify-kubernetes.sh
./scripts/verify-lab.sh
systemctl --failed --no-pager
```

Success means both nodes are `Ready`, the primary Deployment has two available
replicas, both NodePort paths answer successfully, all monitoring targets are
healthy, and no failed systemd unit remains.

For each exercise, record a short incident note with the symptom, evidence,
root cause, recovery action, verification, and one prevention idea. This is the
same reasoning pattern expected in an operations interview or production
incident review.
