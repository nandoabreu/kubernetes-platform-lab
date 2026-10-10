# K3s Workload Failure and Recovery

## Status

This runbook defines the Checkpoint 3 failure exercises but has not yet been executed on the libvirt host. Do not mark the checkpoint complete until the owner records the required service impact, detection signals, recovery actions, and recovery evidence for each exercise.

## Purpose and scope

Exercise the impact of losing the node that serves a single `whoami` replica, then verify that a deliberately spread three-replica Deployment keeps serving through the ClusterIP Service when one node is unavailable. Also observe ReplicaSet Pod replacement and, as a separate optional exercise, a container restart with an intentional Python traceback.

The VM failure uses `virsh destroy` to simulate abrupt power loss, followed by `virsh start` to restart the same VM and its existing disk. This does not delete or recreate the libvirt domain. Terraform destroy/re-provision, physical-host failure, and ingress-controller high availability are outside this checkpoint.

K3s installs one or more Traefik Pods as packaged components; the Checkpoint 2 validation observed one Traefik Pod on `k3s-1`. The primary workload availability signal in this runbook comes from a probe Pod calling the ClusterIP Service directly, so losing a Traefik Pod cannot be mistaken for losing the application Service. Ingress observations are recorded separately.

## Safety and prerequisites

- Run commands from the repository root on the libvirt host unless a command explicitly runs in a Pod.
- Complete the [K3s HA build and validation](k3s-ha-cluster.md) and the [workload routing runbook](k3s-workload-routing.md); all three nodes must be `Ready`, the stable API endpoint must work, and the `whoami` Ingress should return HTTP `200`.
- Keep the lab kubeconfig at `$HOME/.kube/k3s-lab.yaml` with mode `0600`; never display or commit it.
- Confirm the cluster can pull `curlimages/curl:8.12.1` and, if performing the optional container restart exercise, `python:3.12.12-alpine3.22`.
- These exercises intentionally interrupt workload traffic. Run them only when that interruption is acceptable and unrelated host workloads have enough resource headroom.
- Stop only one VM at a time. Three etcd members need two votes for quorum; stopping a second server before the first has recovered takes the cluster below quorum.
- `virsh destroy <domain>` immediately powers off that VM without deleting its domain or disks. Check the target name before running it; do not substitute `terraform destroy`, `virsh undefine`, or a different domain.
- Use the same outage and recovery sequence for the one-replica and three-replica exercises; do not start the next test until all three nodes and the API are healthy again.

> [!WARNING]
> `virsh destroy` abruptly powers off the selected VM. Confirm the VM name in the prompt and current node placement before executing it. The command preserves the libvirt domain and its disks; it is not a Terraform or libvirt resource deletion.

## Capture a healthy baseline

Start from the repository's three-replica manifest and confirm the stable API, all nodes, the workload, its endpoints, and Traefik placement:

```sh
make status
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes -o wide
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get deployment,pods,service,endpointslices -o wide
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n kube-system get pods -o wide
```

Confirm each node is `Ready`, etcd readiness checks pass, and all three `whoami` Pods are Ready before continuing. Record the node hosting each `whoami` Pod, the node hosting Traefik, the ready EndpointSlice addresses, and a successful host-side Ingress response.

## Run a continuous in-cluster Service probe

The probe calls `whoami.platform-demo.svc.cluster.local` directly and is pinned to a healthy node that will remain running during the selected VM outage. This separates application Service behaviour from host routing and the Traefik controller.

Do not start this probe during the baseline checks. In each failure exercise below, first select the VM to stop; then run the probe from a different, healthy node in Terminal A. Keep Terminal A open during the outage and use Terminal B for the VM command.

```sh
read -r -p 'VM to stop for this exercise (k3s-1, k3s-2, or k3s-3): ' failed_node
case "$failed_node" in k3s-1|k3s-2|k3s-3) ;; *) printf 'Unexpected VM name: %s\n' "$failed_node" >&2; exit 1 ;; esac
whoami_nodes=$(kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods -l app.kubernetes.io/name=whoami -o jsonpath='{range .items[*]}{.spec.nodeName}{" "}{end}')
case " $whoami_nodes " in *" $failed_node "*) ;; *) printf 'No whoami Pod is assigned to %s\n' "$failed_node" >&2; exit 1 ;; esac
read -r -p 'Healthy node for the Service probe: ' probe_node
case "$probe_node" in k3s-1|k3s-2|k3s-3) ;; *) printf 'Unexpected probe node: %s\n' "$probe_node" >&2; exit 1 ;; esac
test "$probe_node" != "$failed_node"
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes "$failed_node" "$probe_node"
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo run service-check --rm -i --restart=Never --image=curlimages/curl:8.12.1 --overrides="{\"spec\":{\"nodeName\":\"${probe_node}\"}}" --command -- sh -c 'while true; do printf "\n%s\n" "$(date -u +%FT%TZ)"; curl --connect-timeout 1 --max-time 3 --silent --show-error --write-out "\nHTTP %{http_code}\n" http://whoami.platform-demo.svc.cluster.local/; sleep 1; done'
```

The responses identify the serving Pod hostname. Keep this command running during each failure exercise and use a second terminal for VM and Kubernetes observations. `Ctrl-C` stops and removes the temporary probe Pod.

## Exercise 1: one replica and abrupt node loss

Scale the Deployment to one replica without changing the repository manifest, wait for rollout, and note the VM hosting its Pod:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo scale deployment/whoami --replicas=1
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo rollout status deployment/whoami
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods -o wide
```

In Terminal A, start the Service probe described above. Enter the VM hosting the only `whoami` Pod as `failed_node`, then choose a different healthy node for `probe_node`; confirm the probe returns HTTP `200`. In Terminal B, enter the same `failed_node`, check that it is running, and then cut power to that one VM:

```sh
read -r -p 'Enter the same VM selected for the sole whoami Pod: ' failed_node
case "$failed_node" in k3s-1|k3s-2|k3s-3) ;; *) printf 'Unexpected VM name: %s\n' "$failed_node" >&2; exit 1 ;; esac
test "$(virsh domstate "$failed_node")" = running
virsh destroy "$failed_node"
test "$(virsh domstate "$failed_node")" = 'shut off'
```

In separate terminals, watch node and workload state while the in-cluster probe continues:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes --watch
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods -o wide --watch
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get events --sort-by=.metadata.creationTimestamp
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
```

Record when requests first fail, when the node becomes `NotReady`, when the old endpoint stops being ready, when a replacement Pod is scheduled, and when HTTP `200` returns. Do not assume fixed detection or eviction durations; observe the cluster events and wait for the replacement to become Ready. The API and two surviving etcd members should remain available while only one server is down.

### Recover the VM before continuing

In Terminal B, start the same libvirt domain:

```sh
test "$(virsh domstate "$failed_node")" = 'shut off'
virsh start "$failed_node"
test "$(virsh domstate "$failed_node")" = running
```

In Terminal C, watch for the node to return to `Ready`:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes --watch
```

After all three nodes are `Ready`, stop the watch with `Ctrl-C` and check API, workload, and endpoint health:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods,endpointslices -o wide
```

Confirm the API is healthy, the `whoami` Deployment has one Ready replica, the Service has a ready endpoint, and probe requests return HTTP `200` before starting the next exercise.

## Exercise 2: three spread replicas and one-node loss

Add a temporary topology spread constraint under `spec.template.spec` in the `Deployment/whoami` in `kubernetes/demo/whoami.yaml`, then restore three replicas. This is the same hard spread rule shown in the [Checkpoint 2 placement follow-up](k3s-workload-routing.md#placement-rule-follow-up):

```yaml
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: whoami
```

Review the temporary source change and apply it:

```sh
git diff -- kubernetes/demo/whoami.yaml
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" apply -f kubernetes/demo/whoami.yaml
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo rollout status deployment/whoami
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods -o wide
```

Do not begin the failure until the three Ready `whoami` Pods are on three different nodes. Record which node hosts the single Traefik Pod. In Terminal A, start the Service probe described above, select the VM to stop and a different healthy probe node, and confirm responses identify all three replicas before the outage.

In a second terminal, enter the same `failed_node` selected above, confirm it is running, then abruptly stop it with `virsh destroy` as in Exercise 1. Continue watching node, Pod, EndpointSlice, API, and probe state. After the unavailable node is detected, record that the Service still returns HTTP `200` from the two remaining Ready replicas, the outage window if any, and what happens to the Pod previously assigned to the failed node. Do not require a replacement Pod to become Ready while a node is unavailable; the hard spread constraint may leave it Pending until the failed node returns.

If the failed node hosts Traefik, test host-side Ingress separately through a ServiceLB listener on a surviving node and record any gateway interruption as an ingress-controller limitation, not as failure of the in-cluster ClusterIP Service. The Checkpoint 2 validation observed one Traefik Pod, so this exercise does not claim ingress-controller high availability:

```sh
read -r -p 'Surviving ServiceLB listener IP (10.77.0.11, .12, or .13): ' ingress_node_ip
case "$ingress_node_ip" in 10.77.0.11|10.77.0.12|10.77.0.13) ;; *) printf 'Unexpected listener IP: %s\n' "$ingress_node_ip" >&2; exit 1 ;; esac
curl --connect-timeout 2 --max-time 5 --silent --show-error --resolve "whoami.k3s-lab.test:80:${ingress_node_ip}" --output /dev/null --write-out 'HTTP %{http_code}\n' http://whoami.k3s-lab.test/
```

Choose a listener IP other than the failed VM's address. A successful HTTP `200` confirms the separate host Ingress path; a connection error while Traefik's only Pod is unavailable does not contradict healthy ClusterIP responses from the two remaining `whoami` replicas.

Recover the VM as described in Exercise 1 and wait for all nodes and the API to become healthy. Confirm the third `whoami` replica is Ready and the Service has three ready endpoints before continuing.

## Exercise 3: Pod replacement and container restart

With the three-node cluster healthy and three `whoami` replicas Ready, delete one healthy `whoami` Pod and observe its ReplicaSet replacement:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods -o wide
read -r -p 'Pod name to delete: ' pod_name
test -n "$pod_name"
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo describe pod "$pod_name"
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo delete pod "$pod_name"
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods -o wide --watch
```

Record that this creates a new Pod object with a new name; it is not a restart of the old container. Wait for all three replicas to become Ready and stop the watch with `Ctrl-C`.

To observe a real container restart and a traceback without changing the `whoami` application or adding a Service, run this optional isolated Pod. Its process deliberately raises a Python exception; Kubernetes restarts the container inside the same Pod because its restart policy is `Always`:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo run crash-demo --image=python:3.12.12-alpine3.22 --restart=Always --command -- python -u -c 'import time; time.sleep(5); raise RuntimeError("intentional Checkpoint 3 crash")'
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pod crash-demo --watch
```

After `RESTARTS` becomes greater than zero, inspect the current Pod description and the previous container logs:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pod crash-demo -o custom-columns='NAME:.metadata.name,UID:.metadata.uid,RESTARTS:.status.containerStatuses[0].restartCount,PHASE:.status.phase'
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo describe pod crash-demo
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo logs crash-demo --previous
```

The Python traceback and non-zero exit are intentional. This demonstrates kubelet container restart within the same Pod; the separate `whoami` deletion above demonstrates ReplicaSet creation of a new Pod. Remove the temporary crash Pod after capturing the evidence:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo delete pod crash-demo
```

The crash-demo Pod is optional evidence and does not gate the Checkpoint 3 exit criteria. A Kubernetes Service is not needed for it because Services route traffic but do not restart processes.

## Restore the Checkpoint 2 workload configuration

Remove the temporary topology spread block from `kubernetes/demo/whoami.yaml`, set `spec.replicas: 3`, and review the resulting source diff. Do not discard unrelated local changes. Apply the restored manifest and confirm the final cluster state:

```sh
git diff -- kubernetes/demo/whoami.yaml
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" apply -f kubernetes/demo/whoami.yaml
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo rollout status deployment/whoami
virsh list --all
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes -o wide
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods,services,endpointslices -o wide
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
```

Confirm all three VMs are running, all three K3s nodes are `Ready`, the API and etcd readiness checks pass, and the `whoami` Deployment has three Ready replicas and three ready Service endpoints. The optional host Ingress should return HTTP `200` again if it was interrupted during the node test.

After recording the evidence, if you are ending the lab session, gracefully stop the VMs using the [Terraform VM runbook](terraform-libvirt-vms.md#stop-the-vms).

## Checkpoint 3 evidence and completion

For both node failures, record the selected VM and its `whoami` placement, failure method, service impact, failed dependency, detection signal and timings, recovery action and owner, replacement scheduling, endpoint state, and evidence of restored HTTP responses. Preserve terminal output or sanitized notes outside Git; do not include kubeconfig contents, tokens, or unrelated host data.

Checkpoint 3 is complete only after the one-replica outage and recovery, three spread replica service-continuity test, Pod replacement, and all-node recovery are exercised and the evidence is recorded. The optional crash-demo adds container restart and traceback evidence but is not required for the checkpoint.

## Next step

After the owner reviews and records the Checkpoint 3 evidence, continue with the [roadmap](../roadmap.md) for the clean replay requirements of Checkpoint 4. These exercises demonstrate node-level recovery on VMs sharing one host, not physical-host high availability.
