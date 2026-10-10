# K3s HA Cluster: Failure and Restart Validation

## Status

Roadmap Checkpoint 1 validation completed on 2026-10-09. Individual shutdown and recovery tests for `k3s-1`, `k3s-2`, and `k3s-3` passed: the API remained ready through HAProxy, each stopped node became `NotReady`, and each returned to `Ready` after restart. A full lab shutdown/restart also passed; the subsequent `make status` reported 7.1 GiB of available RAM, and the owner assessed the remaining host figures as acceptable. An `etcdctl member list` query also returned the three expected K3s server members.

## Prerequisites

- Run all commands from the repository root on the libvirt host unless a command explicitly opens an SSH session on a guest.
- Complete the [K3s HA build runbook](k3s-ha-cluster.md); all three nodes must report `Ready` through the host-side kubeconfig using `https://10.77.0.1:6443`.
- Confirm `kubectl get --raw='/readyz?verbose'` passes through the stable endpoint and HAProxy is logging backend/server selections to `/var/log/haproxy.log` as configured in the [Host HAProxy Endpoints runbook](host-haproxy.md).
- Keep the administrative kubeconfig at `$HOME/.kube/k3s-lab.yaml` with mode `0600`; do not display or commit it.
- Start from a healthy three-node cluster. Do not begin a failure test while a node is already unavailable or recovering.

## Baseline and quorum

Capture the host and storage baseline, then verify node roles and API readiness:

```sh
make status
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes -o wide
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
```

Each node should show the `control-plane,etcd` roles, and verbose readiness should include passing `etcd` and `etcd-readiness` checks. The individual shutdown tests then demonstrate quorum while one member is unavailable. Three voting members require a quorum of two: one unavailable server leaves quorum; two unavailable servers leave only one vote, so etcd cannot commit updates and API operations that need the datastore fail. Do not stop two servers at the same time.

Node roles, etcd readiness checks, and single-node outage tests verify quorum behaviour. The following read-only check additionally lists the configured etcd members. K3s does not install `etcdctl`; this downloads the upstream `v3.7.1` client matching the embedded etcd `v3.7.1-k3s3` base version, verifies its release checksum, uses K3s-managed TLS credentials, and removes the temporary files afterward:

```sh
LC_ALL=C ssh ubuntu@10.77.0.11 'bash -s' <<'REMOTE'
set -euo pipefail
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
curl --fail --location --silent --show-error https://github.com/etcd-io/etcd/releases/download/v3.7.1/SHA256SUMS -o "$tmpdir/SHA256SUMS"
curl --fail --location --silent --show-error https://github.com/etcd-io/etcd/releases/download/v3.7.1/etcd-v3.7.1-linux-amd64.tar.gz -o "$tmpdir/etcd-v3.7.1-linux-amd64.tar.gz"
cd "$tmpdir"
grep 'etcd-v3.7.1-linux-amd64.tar.gz$' SHA256SUMS | sha256sum --check -
tar -xzf etcd-v3.7.1-linux-amd64.tar.gz -C "$tmpdir" --strip-components=1 etcd-v3.7.1-linux-amd64/etcdctl
sudo "$tmpdir/etcdctl" --endpoints=https://127.0.0.1:2379 --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt --cert=/var/lib/rancher/k3s/server/tls/etcd/client.crt --key=/var/lib/rancher/k3s/server/tls/etcd/client.key member list --write-out=table
REMOTE
```

Expect three rows named for `k3s-1`, `k3s-2`, and `k3s-3`, all with `STATUS` `started` and `IS LEARNER` `false`. Member IDs are generated per cluster and should not be copied into reusable configuration. The list reports configured membership; use `/readyz` and the failure tests to verify current health and quorum.

Follow HAProxy activity in a separate terminal while running each exercise:

```sh
tail -f /var/log/haproxy.log
```

Connection entries identify the selected backend/server; health-check entries identify when a backend goes down or returns up.

## Stop and recover one server

Run this sequence for one node at a time, substituting `k3s-1`, `k3s-2`, or `k3s-3` in each command. Do not test the next node until the current one is back to `Ready` and HAProxy reports it healthy.

```sh
virsh shutdown k3s-1
virsh domstate k3s-1
```

Repeat `virsh domstate k3s-1` until it reports `shut off`, then check API readiness and watch the Kubernetes node status:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes --watch
```

The Kubernetes `Node` object remains in the API after the VM stops; its displayed status can remain temporarily `Ready` while the heartbeat lease expires and the node controller detects the missing kubelet. Wait for it to become `NotReady`, then press `Ctrl-C` to stop the watch. Throughout the test, `/readyz` should continue to pass and the other two nodes should remain `Ready`. HAProxy should mark the stopped backend down and route new connections to healthy backends.

Restore the VM and wait for the node and HAProxy backend to recover:

```sh
virsh start k3s-1
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes --watch
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
```

Press `Ctrl-C` after the restored node reports `Ready`. Record the stopped node, impact, detection signal, time to `NotReady`, HAProxy backend state, recovery action, and time to return to `Ready`. Repeat for the other two servers, one at a time. With no demo workload installed at this checkpoint, record API/control-plane impact; application traffic behaviour is tested in a later checkpoint.

## Full lab shutdown and restart

After all three individual failure tests have completed and all nodes are healthy, record another `make status` snapshot. Gracefully stop each VM and confirm it is shut off before starting the next:

```sh
virsh shutdown k3s-1
virsh domstate k3s-1
```

Wait until `virsh domstate k3s-1` reports `shut off`, then stop the next VM:

```sh
virsh shutdown k3s-2
virsh domstate k3s-2
```

Wait until `virsh domstate k3s-2` reports `shut off`, then stop the final VM:

```sh
virsh shutdown k3s-3
virsh domstate k3s-3
```

On restart, check the `k3s-lab` libvirt network and start it if inactive; see the [Terraform VM runbook](terraform-libvirt-vms.md) for the network start procedure. Then start the VMs:

```sh
virsh start k3s-1
virsh start k3s-2
virsh start k3s-3
```

VM start returns before the guests and API are ready. An initial API request may return `ServiceUnavailable`; repeat the readiness and node checks below until the API is ready and all nodes report `Ready`. This is guest/K3s startup time, distinct from the heartbeat lease delay used to detect a stopped node.

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes
```

Confirm all three nodes return to `Ready`, the stable API endpoint works, the etcd readiness check passes, and HAProxy reports all three backends healthy. Capture `make status` again and record memory, swap, CPU, disk, and pool usage.

## Recovery boundary and exit evidence

If two servers fail together or quorum is lost, stop disruptive changes and use a version-specific recovery procedure; do not improvise etcd membership changes. Snapshot/restore and full rebuild are separate procedures and are not established by this validation exercise.

Checkpoint 1 validation completed on 2026-10-09: all three individual failure/recovery tests and the full lab shutdown/restart passed, API readiness remained healthy with one server unavailable, host resource headroom was reviewed, and failure impact/detection/recovery evidence was observed. The exercises verify quorum operationally rather than recording etcd member IDs.
