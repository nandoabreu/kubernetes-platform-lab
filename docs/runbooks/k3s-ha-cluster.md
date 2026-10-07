# K3s HA Cluster: Build and Verification

## Status

This is the target procedure for Roadmap Checkpoint 1. Keep it as a plan until the exact guest OS, K3s version, VM provisioning method, and stable API endpoint have been selected and verified. Do not copy commands into automation before the manual procedure has been exercised.

## Target

- Three libvirt VMs, each with 2 GiB RAM and a documented CPU/disk allocation.
- All three run the K3s server role.
- Embedded etcd is the cluster datastore.
- A stable Kubernetes API endpoint remains reachable after one server fails.
- No demo workload is required to prove cluster formation.

## Build sequence

1. Complete the [host and VM baseline](host-and-vm-baseline.md). Confirm the `extra` pool has capacity and the paused streaming VM remains stopped.
2. Create and update three equivalent VMs with stable, recorded network addresses. Keep credentials out of Git.
3. Verify time synchronisation, name/address resolution, and bidirectional node connectivity required by the chosen K3s and etcd configuration.
4. Select and validate the stable API endpoint before joining additional servers. It must remain available when any one server is stopped and must not rely solely on an in-cluster workload.
5. Install a pinned K3s version. Initialise the first server with embedded etcd cluster initialisation enabled; protect the join token as a secret.
6. Join the other two servers as K3s servers using the same token, version, cluster settings, and API endpoint.
7. Verify all three nodes, control-plane availability, datastore health, and access through the stable API endpoint.
8. Stop one server at a time. Confirm the remaining two retain quorum and the API endpoint remains usable; restore it before testing another server.
9. Record observed memory, swap, CPU, disk, recovery behaviour, and any limits.

Exact commands, service names, health checks, and endpoint implementation must be added after the selected K3s version and networking design are tested.

## Verification checklist

- [ ] All three Kubernetes nodes report `Ready`.
- [ ] The cluster reports three healthy embedded etcd members and quorum.
- [ ] API operations succeed through the stable endpoint.
- [ ] Stopping one server leaves two members, quorum, and API access.
- [ ] Restarting the stopped server returns it to a healthy member state.
- [ ] Host memory, swap, and `extra` pool usage remain within the agreed budget.
- [ ] No secret, token, kubeconfig credential, or generated key was committed.

## Recovery and cleanup

Do not test two simultaneous server failures in the initial exercise. If quorum is lost, stop disruptive changes and follow a version-specific recovery procedure; do not improvise etcd membership changes.

VM deletion, etcd snapshot/restore, and full rebuild procedures are not yet defined. Add and test them before calling the cluster reproducible or using it for important data.
