# K3s Workload Failure and Recovery

## Status

The owner completed the required Checkpoint 3 exercises on the libvirt host on 2026-10-11. The observed service impact, node detection, Pod replacement, and recovery evidence are recorded below. The optional one-shot crash-demo procedure was added after the owner observed intermittent `kubectl logs --previous` retrieval during a repeated crash loop; that revised optional procedure has not yet been run.

## Recorded Checkpoint 3 results

- **One replica on `k3s-2`:** abrupt VM power-off interrupted the sole Service endpoint. Probe requests first failed at `08:52:22Z` and returned HTTP `200` at `08:58:09Z` (approximately 5 minutes 47 seconds) from the replacement Pod on `k3s-3`. The node became `NotReady`, the Pod was marked for eviction after the observed 300-second `not-ready`/`unreachable` tolerations, and the API readiness check continued to pass with two etcd members available.
- **Three spread replicas with `k3s-3` powered off:** the in-cluster probe had transient HTTP `000` results around the outage, then returned HTTP `200` from the replicas on `k3s-1` and `k3s-2`. `k3s-3` received `unreachable` taints and the replacement Pod remained `Pending` with `FailedScheduling` events because the hard spread rule would not place it on either surviving node while the failed node's Pod remained in the topology calculation. The warning events remained in the event history after recovery; the final Ready node/Pod/endpoint state confirmed they were no longer active failures.
- **VM and workload recovery:** the owner restarted the same `k3s-3` VM at `11:10:20 WEST`; a `whoami` IP responded again at `10:11:56Z`, and all three nodes were `Ready` by the later `11:17:23 WEST` observation. The pending replacement was scheduled on `k3s-3`; the final three Pods were distributed one per node, the API and three Service endpoints were healthy, and the host Ingress returned HTTP `200`.
- **Pod replacement:** deleting `whoami-59fb89bb5-2t4ln` on `k3s-3` caused the ReplicaSet to create a replacement on `k3s-1`, completing the three-node spread.
- **Optional container crash:** the repeated-crash demo kept the same Pod UID, reached six container restarts, and produced the intentional Python traceback. `kubectl logs --previous` intermittently could not retrieve the prior container ID while the crash loop advanced; the revised one-shot optional procedure below is intended to keep the previous log stable but has not yet been exercised.

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

The probe calls `whoami.platform-demo.svc.cluster.local` directly and is pinned to a healthy node that will remain running during the selected VM outage. This separates application Service behaviour from host routing and the Traefik controller. Its output is filtered to the timestamp, serving Pod, Pod IP, and HTTP status.

Do not start this probe during the baseline checks. Before launching it, check whether a `service-check` Pod from an earlier exercise is still running:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pod/service-check --ignore-not-found -o wide
```

If the Pod is `Running` on a healthy node other than the VM selected for this failure, reuse it; do not run another `kubectl run` with the same name. Keep its current terminal open, or follow its output with:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo logs -f pod/service-check | grep --color=never -E '^(---|[0-9]{4}-[0-9]{2}-[0-9]{2}T|Hostname:|IP: 10|HTTP )'
```

If it is absent, or pinned to the VM you plan to stop, clean up the old Pod below and launch a new probe from a different node. Keep the probe on Terminal A and use Terminal B for VM commands.

When reusing a probe from an earlier exercise, use the `NODE` column above to identify its node; choose a failed VM on a different node. The shell variable from an earlier terminal is not shared with the new terminal.

Run this command once for a new probe; it asks for both the failed VM and a different, healthy probe node in the same shell:

```sh
read -r -p 'VM to stop for this exercise (k3s-1, k3s-2, or k3s-3): ' failed_node
case "$failed_node" in k3s-1|k3s-2|k3s-3) ;; *) printf 'Unexpected VM name: %s\n' "$failed_node" >&2; exit 1 ;; esac
whoami_nodes=$(kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods -l app.kubernetes.io/name=whoami -o jsonpath='{range .items[*]}{.spec.nodeName}{" "}{end}')
case " $whoami_nodes " in *" $failed_node "*) ;; *) printf 'No whoami Pod is assigned to %s\n' "$failed_node" >&2; exit 1 ;; esac
read -r -p 'Healthy node for the Service probe: ' probe_node
case "$probe_node" in k3s-1|k3s-2|k3s-3) ;; *) printf 'Unexpected probe node: %s\n' "$probe_node" >&2; exit 1 ;; esac
if [ "$probe_node" = "$failed_node" ]; then printf 'Probe node must differ from failed VM %s\n' "$failed_node" >&2; exit 1; fi
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes "$failed_node" "$probe_node"
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo run service-check --rm -i --restart=Never --image=curlimages/curl:8.12.1 --overrides="{\"spec\":{\"nodeName\":\"${probe_node}\"}}" --command -- sh -c 'while true; do printf "\n---\n%s\n" "$(date -u +%FT%TZ)"; curl --connect-timeout 1 --max-time 3 --silent --show-error --write-out "\nHTTP %{http_code}\n" http://whoami.platform-demo.svc.cluster.local/; sleep 1; done' | grep --color=never -E '^(---|[0-9]{4}-[0-9]{2}-[0-9]{2}T|Hostname:|IP: 10|HTTP )'
```

The responses identify the serving Pod hostname. Keep this command running during each failure exercise and use a second terminal for VM and Kubernetes observations. After `Ctrl-C`, explicitly clean up the probe Pod before starting another probe; the `kubectl run --rm` client can exit while the Pod remains:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo delete pod/service-check --ignore-not-found --wait=true
```

This removes only the temporary `service-check` Pod and is safe to repeat if `--rm` already removed it.

## Exercise 1: one replica and abrupt node loss

Scale the Deployment to one replica without changing the repository manifest, wait for rollout, and note the VM hosting its Pod:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo scale deployment/whoami --replicas=1
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo rollout status deployment/whoami
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods -o wide
```

In Terminal A, start or reuse the Service probe and confirm it returns HTTP `200` from the only `whoami` Pod. Note the probe's node. In Terminal B, enter the VM hosting the `whoami` Pod as `failed_node`; it must be different from the probe node. Inspect its state; it must report `running` before you cut power to that VM:

```sh
read -r -p 'VM to stop (k3s-1, k3s-2, or k3s-3): ' failed_node
case "$failed_node" in k3s-1|k3s-2|k3s-3) ;; *) printf 'Unexpected VM name: %s\n' "$failed_node" >&2; exit 1 ;; esac
virsh domstate "$failed_node"
virsh destroy "$failed_node"
virsh domstate "$failed_node"
```

The first `domstate` output must be `running`; the second should be `shut off`. If either output differs, stop and investigate before continuing.

In separate terminals, watch node and workload state while the in-cluster probe continues:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes --watch
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods -o wide --watch
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get events --sort-by=.metadata.creationTimestamp
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
```

Record when requests first fail, when the node becomes `NotReady`, when the old endpoint stops being ready, when a replacement Pod is scheduled, and when HTTP `200` returns. Do not assume fixed detection or eviction durations; observe the cluster events and wait for the replacement to become Ready. The API and two surviving etcd members should remain available while only one server is down.

### Recover the VM before continuing

In Terminal B, inspect the same libvirt domain before starting it:

```sh
virsh domstate "$failed_node"
virsh start "$failed_node"
virsh domstate "$failed_node"
```

The first output should be `shut off` and the last should be `running`. If the first state differs, stop and inspect the VM rather than attempting another start.

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

Do not begin the failure until the three Ready `whoami` Pods are on three different nodes. With three replicas and three eligible hostname domains, the expected placement is one Pod per node. A `2 + 1 + 0` placement means a node may be excluded from the scheduler's eligible domains or the constraint may not be applied/matching; inspect the state before continuing:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes -o wide -L kubernetes.io/hostname
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes -o custom-columns='NODE:.metadata.name,UNSCHEDULABLE:.spec.unschedulable,TAINTS:.spec.taints'
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get deployment whoami -o jsonpath='{.spec.template.spec.topologySpreadConstraints}{"\n"}'
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pods -l app.kubernetes.io/name=whoami -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready'
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get events --field-selector=reason=FailedScheduling --sort-by=.metadata.creationTimestamp
```

In the first output, `STATUS` should be `Ready` and `HOSTNAME` should be unique for each node. In the second, `UNSCHEDULABLE` set to `true` means the node is cordoned; `<none>` means it is not explicitly cordoned, but inspect `TAINTS` for `NoSchedule` or `NoExecute`. Confirm the Deployment template prints the spread rule and that each Pod is Ready on its own node. If only two nodes are eligible, a `2 + 1 + 0` distribution can satisfy `maxSkew: 1`; resolve the ineligible node or configuration issue before continuing. A lack of `FailedScheduling` events means there are no recorded scheduling failures, not proof of three eligible domains.

Do not stop a node until the three replicas are Ready and distributed one per node. Record which node hosts the single Traefik Pod. In Terminal A, start or reuse the Service probe and confirm responses identify all three replicas. In Terminal B, choose a VM hosting a `whoami` Pod that is different from the probe node, then enter that VM at the shutdown prompt from Exercise 1.

Use the selected VM with the `virsh domstate` and `virsh destroy` commands from Exercise 1. Continue watching node, Pod, EndpointSlice, API, and probe state. After the unavailable node is detected, record that the Service still returns HTTP `200` from the two remaining Ready replicas, the outage window if any, and what happens to the Pod previously assigned to the failed node. Do not require a replacement Pod to become Ready while a node is unavailable; the hard spread constraint may leave it Pending until the failed node returns.

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

To observe a real container restart and a traceback without changing the `whoami` application or adding a Service, run this optional isolated Pod. It fails once with a Python exception; a marker in an `emptyDir` survives the container restart so the next instance stays alive while you inspect the previous logs:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo delete pod/crash-demo --ignore-not-found --wait=true
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: crash-demo
  namespace: platform-demo
spec:
  restartPolicy: Always
  containers:
    - name: crash-demo
      image: python:3.12.12-alpine3.22
      command: ["/bin/sh", "-c"]
      args:
        - |
          if [ -e /state/crashed ]; then
            printf '%s\n' 'Container restarted after the intentional failure'
            exec sleep 3600
          fi
          touch /state/crashed
          exec python -u -c 'raise RuntimeError("intentional Checkpoint 3 crash")'
      volumeMounts:
        - name: state
          mountPath: /state
  volumes:
    - name: state
      emptyDir: {}
YAML
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pod crash-demo --watch
```

Wait until `RESTARTS` is `1` and the Pod is back to `Running`, then stop the watch with `Ctrl-C`. Confirm the current container is the post-restart process and inspect the previous container's traceback:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo get pod crash-demo -o custom-columns='NAME:.metadata.name,UID:.metadata.uid,RESTARTS:.status.containerStatuses[0].restartCount,PHASE:.status.phase'
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo logs crash-demo
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" -n platform-demo logs crash-demo --previous
```

The current logs should report that the container restarted; `--previous` should show the intentional Python traceback. This demonstrates kubelet restarting a container inside the same Pod; the separate `whoami` deletion above demonstrates ReplicaSet creation of a new Pod. `kubectl logs --previous` exposes only the most recently terminated container and is not durable log storage. Remove the temporary crash Pod after capturing the evidence:

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

For each future replay, record the selected VM and its `whoami` placement, failure method, service impact, failed dependency, detection signal and timings, recovery action and owner, replacement scheduling, endpoint state, and evidence of restored HTTP responses. Preserve terminal output or sanitized notes outside Git; do not include kubeconfig contents, tokens, or unrelated host data.

Checkpoint 3 was completed on 2026-10-11: the one-replica outage and recovery, three spread replica service-continuity test, Pod replacement, and all-node recovery were exercised and the evidence is recorded above. The optional crash-demo adds container restart and traceback evidence but is not required for the checkpoint.

## Next step

Checkpoint 4 is the next roadmap capability and covers a reproducible clean replay. These exercises demonstrate node-level recovery on VMs sharing one host, not physical-host high availability.
