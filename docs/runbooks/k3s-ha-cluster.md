# K3s HA Cluster: Build and Verification

## Status

This is the prepared procedure for Roadmap Checkpoint 1; it has not yet been run against the VMs. The owner will review and execute the commands when ready. The network path between VMs and from the host to TCP port 6443 was manually verified with a temporary HTTP server, but K3s and etcd are not installed yet.

## Decisions

- The guests run Ubuntu Server 24.04.4 LTS, use the fixed addresses `10.77.0.11` through `10.77.0.13`, and are provisioned by Terraform.
- Pin K3s to `v1.37.1+k3s1` on every server; this release bundles Kubernetes `v1.37.1` and embedded etcd `v3.7.1-k3s3`.
- Use K3s embedded etcd and its default Flannel VXLAN backend and packaged components; do not install etcd separately.
- Use `10.77.0.1` as the future stable API endpoint behind HAProxy. Ansible passes it as a parameter and includes it in the API server certificate's Subject Alternative Names (SANs).
- Bootstrap `k3s-1` first and validate it directly at `10.77.0.11:6443`. Install HAProxy on the libvirt host only after that validation and a separate review; join `k3s-2` and `k3s-3` through `10.77.0.1:6443` afterward.
- Use Ansible with all three hosts in inventory. The initial execution is limited to `k3s-1`; joining servers is a separate play and is run only after the HAProxy endpoint is ready.

Kubernetes uses TLS for API and control-plane communication. K3s creates and manages the cluster certificate authorities and the certificates used by API, nodes, and embedded etcd. The `tls-san` setting adds the future API endpoint IP to the API server certificate identity; it is not a custom CA and does not replace K3s-managed node or etcd certificates. The generated administrative kubeconfig and join token are credentials and must remain outside Git.

## Target

- Three libvirt VMs, each with 2 GiB RAM and a documented CPU/disk allocation.
- All three run the K3s server role.
- Embedded etcd is the cluster datastore.
- A stable Kubernetes API endpoint remains reachable after one server fails.
- No demo workload is required to prove cluster formation.

## Network requirements

- The host needs SSH access to the guests on TCP `22` and Kubernetes API access on TCP `6443`; initially use `10.77.0.11:6443`, then the HAProxy endpoint `10.77.0.1:6443`.
- Every server must reach the other servers on TCP `6443`, TCP `2379-2380` for embedded etcd, and UDP `8472` for the default Flannel VXLAN backend.
- TCP `10250` between nodes is needed when using the K3s metrics-server component; retain it on the lab network only.
- Do not expose etcd ports `2379-2380` to the host or home LAN. Keep the node-to-node ports scoped to the isolated `k3s-lab` network.
- K3s nodes need outbound access to download the version-pinned installer and release binary. The installer verifies the binary against the matching release SHA-256 manifest.
- The playbook does not change guest firewall policy. Check `sudo ufw status verbose` on each VM; if UFW is active, apply the following inbound rules on each VM before installing and verify them with `sudo ufw status numbered`.

```sh
sudo ufw allow from 10.77.0.0/24 to any port 6443 proto tcp
sudo ufw allow from 10.77.0.11 to any port 2379:2380 proto tcp
sudo ufw allow from 10.77.0.12 to any port 2379:2380 proto tcp
sudo ufw allow from 10.77.0.13 to any port 2379:2380 proto tcp
sudo ufw allow from 10.77.0.11 to any port 8472 proto udp
sudo ufw allow from 10.77.0.12 to any port 8472 proto udp
sudo ufw allow from 10.77.0.13 to any port 8472 proto udp
sudo ufw allow from 10.77.0.11 to any port 10250 proto tcp
sudo ufw allow from 10.77.0.12 to any port 10250 proto tcp
sudo ufw allow from 10.77.0.13 to any port 10250 proto tcp
sudo ufw status numbered
```

## Ansible layout

The controller configuration and inventory are in `ansible/`. `ansible/inventory/hosts.yml` contains all three VMs, the pinned K3s version, and the parameterised API endpoint/SAN. `ansible/playbooks/k3s.yml` has a bootstrap play for `k3s-1` and a serial join play for the other servers; joining servers reads the generated token from `k3s-1` without logging it. The configuration file on each guest is written with mode `0600`.

The installer script is fetched from the matching K3s release tag rather than the moving `get.k3s.io` URL. The installer then downloads the matching K3s binary and verifies its SHA-256. The playbook does not fetch the administrative kubeconfig; the manual host-side test below stores it outside the repository.

## Prepare and review

Run these commands from the repository root on the libvirt host; the first command enters `ansible/`. Ansible Core, `kubectl`, SSH access as `ubuntu`, and passwordless sudo for that SSH user are required.

```sh
cd ansible
ansible --version
kubectl version --client
ansible-inventory --graph
ansible-playbook playbooks/k3s.yml --syntax-check
ansible-playbook playbooks/k3s.yml --list-hosts --limit k3s-1
ansible k3s_initial -m ping --limit k3s-1
```

The host list should show `k3s-1` for the bootstrap play and no hosts for the join play. The ping command checks Ansible's SSH and Python access without changing the guest.

## Bootstrap and validate one server

After reviewing the inventory, template, pinned installer source, and playbook, run only the bootstrap play:

```sh
ansible-playbook playbooks/k3s.yml --limit k3s-1
```

The play creates `/etc/rancher/k3s/config.yaml` with `cluster-init: true` and the API endpoint SAN, installs the pinned K3s server as a systemd service, and starts a one-member embedded etcd cluster. This temporary state proves the first-server setup only; it has no etcd fault tolerance and does not complete the HA checkpoint. The play does not install K3s on `k3s-2` or `k3s-3`.

Check the service and API locally on the guest:

```sh
ssh ubuntu@10.77.0.11 'sudo systemctl is-active k3s && sudo k3s --version && sudo k3s kubectl get nodes'
ssh ubuntu@10.77.0.11 "sudo k3s kubectl get --raw='/readyz?verbose'"
```

To verify the API from the host with certificate validation, copy the administrative kubeconfig to a private path outside the repository and point it at the guest's direct API address for this first check:

```sh
set -e
umask 077
install -d -m 0700 "$HOME/.kube"
ssh ubuntu@10.77.0.11 'sudo cat /etc/rancher/k3s/k3s.yaml' > "$HOME/.kube/k3s-lab.yaml"
chmod 0600 "$HOME/.kube/k3s-lab.yaml"
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" config set-cluster default --server=https://10.77.0.11:6443
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
```

The kubeconfig contains administrator client credentials. Keep it under `$HOME/.kube`, do not display it, and do not add it to Git. Confirm the API response includes the ready checks and that the API certificate validates when reached at `10.77.0.11`.

## Stable endpoint and remaining servers

Stop after the single-server validation and review the HAProxy design and checks before installing it on the host. Confirm the endpoint `10.77.0.1:6443` forwards TCP to the healthy K3s servers and does not depend on an in-cluster workload.

Once HAProxy is installed and validated, update the host-side kubeconfig to use `https://10.77.0.1:6443` and confirm API access through that endpoint. Then review the join play's `server` URL and execute it against the remaining servers one at a time:

```sh
cd ansible
ansible-playbook playbooks/k3s.yml --list-hosts --limit 'k3s-2,k3s-3'
ansible-playbook playbooks/k3s.yml --limit 'k3s-2,k3s-3'
```

The host-side kubeconfig endpoint can be changed and tested with:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" config set-cluster default --server=https://10.77.0.1:6443
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
```

The join play reads `/var/lib/rancher/k3s/server/node-token` from `k3s-1` over SSH and keeps the token out of task output. Each joining server uses the same pinned K3s version, the stable API URL, and the API endpoint SAN; the play uses `serial: 1` so only one server joins at a time.

After confirming all three nodes are healthy and the etcd-backed API is ready, stop and restore one server at a time from the host. For each node, wait until libvirt reports it shut off, verify API readiness through HAProxy, restart it, and wait until it returns to `Ready` before testing the next node:

```sh
sudo virsh shutdown k3s-1
sudo virsh domstate k3s-1
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
sudo virsh start k3s-1
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes --watch
```

Repeat with `k3s-2` and `k3s-3`, never stopping two servers together. Record the observed API/readiness impact and recovery evidence for each exercise.

## Build sequence

1. Complete the [host and VM baseline](host-and-vm-baseline.md). Confirm the `extra` pool has capacity and the paused streaming VM remains stopped.
2. Start the three equivalent VMs and verify their fixed addresses, time synchronisation, and bidirectional node connectivity; these network checks have been manually exercised.
3. Review the Ansible inventory and playbook, then bootstrap only `k3s-1` with the pinned release and embedded etcd.
4. Validate the single-node API locally and from the host, including TLS validation against the API certificate.
5. Review, install, and validate the host HAProxy endpoint. Do this before joining additional servers.
6. Join `k3s-2` and `k3s-3` sequentially through the stable endpoint using the same K3s version and server configuration.
7. Verify all three nodes, control-plane availability, datastore health, and access through the stable API endpoint.
8. Stop one server at a time. Confirm the remaining two retain quorum and the API endpoint remains usable; restore it before testing another server.
9. Record observed memory, swap, CPU, disk, recovery behaviour, and any limits.
10. After restoring all three healthy servers, shut down the lab VMs when the exercise ends. On the next session, start them again and verify node readiness, etcd membership, and API access before continuing.

The K3s version, VM addressing, and endpoint address are selected. HAProxy implementation and the final etcd membership/failover checks remain gated on the single-server validation and owner review.

## Verification checklist

- [ ] The initial `k3s-1` node reports `Ready` and the API is reachable from the host.
- [ ] The API TLS certificate validates for the future endpoint address `10.77.0.1`.
- [ ] All three Kubernetes nodes report `Ready`.
- [ ] The cluster reports three healthy embedded etcd members and quorum.
- [ ] API operations succeed through the stable endpoint.
- [ ] Stopping one server leaves two members, quorum, and API access.
- [ ] Restarting the stopped server returns it to a healthy member state.
- [ ] Host memory, swap, and `extra` pool usage remain within the agreed budget.
- [ ] After an intentional full lab shutdown and restart, all three servers and the stable API endpoint return to a healthy state.
- [ ] No secret, token, kubeconfig credential, or generated key was committed.

## Recovery and cleanup

Do not test two simultaneous server failures in the initial exercise. If quorum is lost, stop disruptive changes and follow a version-specific recovery procedure; do not improvise etcd membership changes.

VM deletion, etcd snapshot/restore, and full rebuild procedures are not yet defined. Add and test them before calling the cluster reproducible or using it for important data.
