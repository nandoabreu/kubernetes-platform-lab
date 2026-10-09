# K3s HA Cluster: Build and Bootstrap

## Status

The build portion of Checkpoint 1 was completed on 2026-10-09. Ansible installed K3s `v1.37.1+k3s1` on all three VMs; all nodes reported `Ready`, the API `/readyz` checks passed through HAProxy at `10.77.0.1:6443`, and HAProxy logs showed connections reaching all three backends. The failure, resource, and full-restart exercises are in the separate [K3s HA validation runbook](k3s-ha-validation.md).

## Decisions

- The guests run Ubuntu Server 24.04.4 LTS, use the fixed addresses `10.77.0.11` through `10.77.0.13`, and are provisioned by Terraform.
- Pin K3s to `v1.37.1+k3s1` on every server; this release bundles Kubernetes `v1.37.1` and embedded etcd `v3.7.1-k3s3`.
- Use K3s embedded etcd and its default Flannel VXLAN backend and packaged components; do not install etcd separately.
- Use `10.77.0.1:6443` as the stable API endpoint behind HAProxy. Ansible passes it as a parameter and includes it in the API server certificate's Subject Alternative Names (SANs).
- Bootstrap `k3s-1` first and validate it directly at `10.77.0.11:6443`; after HAProxy is installed and validated, join `k3s-2` and `k3s-3` through `10.77.0.1:6443`.
- Use Ansible with all three hosts in inventory. Bootstrap and join are separate plays; use `--limit` to run the appropriate stage, and `serial: 1` joins servers sequentially.

Kubernetes uses TLS for API and control-plane communication. K3s creates and manages the cluster certificate authorities and the certificates used by API, nodes, and embedded etcd. The `tls-san` setting adds the stable API endpoint IP to the API server certificate identity; it is not a custom CA and does not replace K3s-managed node or etcd certificates. The generated administrative kubeconfig and join token are credentials and must remain outside Git.

Flannel is K3s's default Container Network Interface (CNI), which gives Pods network connectivity across nodes. Its VXLAN backend encapsulates Pod-network packets inside UDP packets between VM addresses; it is separate from the Kubernetes API and etcd traffic. K3s also deploys packaged components by default, including CoreDNS, Traefik, ServiceLB, local-path storage, and metrics-server. ServiceLB exposes Kubernetes `LoadBalancer` Services; it is not the stable endpoint for the Kubernetes API. This checkpoint keeps the defaults so the lab starts with the standard K3s networking and system components.

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
- K3s nodes need outbound access to download the installer and release binary. Ansible pins the installer source to a full K3s commit and verifies its SHA-256; the installer separately verifies the version-pinned K3s binary against the release manifest.

The three guests currently have UFW inactive, and the libvirt NAT network is not published to the home LAN. This checkpoint does not add guest firewall rules; the guests and host are treated as trusted members of the lab network. Restricting etcd and overlay-network traffic with host or guest firewall policy can be a separate security exercise later. The port list above describes K3s communication requirements, not a request to add firewall rules now.

## Ansible layout

The controller configuration and inventory are in `ansible/`. `ansible/inventory/hosts.yml` contains all three VMs, the pinned K3s version, and the parameterised API endpoint/SAN. `ansible/playbooks/k3s.yml` has a bootstrap play for `k3s-1` and a serial join play for the other servers; joining servers reads the generated token from `k3s-1` without logging it. The configuration file on each guest is written with mode `0600`. In Ansible, `hosts: k3s_joiners` selects both joining hosts from inventory; `serial: 1` runs the play's tasks on one host, completes it, and then repeats for the next host.

Each target VM downloads the installer script from the full commit associated with K3s `v1.37.1+k3s1`; Ansible verifies the script SHA-256 before execution. The installer downloads that VM's K3s binary and verifies it against the release manifest. The playbook compares the complete installed version token, not a substring, and does not cache a binary centrally. The playbook does not fetch the administrative kubeconfig; the manual host-side test below stores it outside the repository.

The `/etc/rancher/k3s` path is K3s's conventional Linux configuration directory. Its name reflects K3s's Rancher project origins; installing K3s there does not install the Rancher management server.

## Prepare and review

Run these commands from the repository root on the libvirt host; the first command enters `ansible/`. Ansible Core, `kubectl`, SSH access as `ubuntu`, and passwordless sudo for that SSH user are required.

```sh
cd ansible
ansible --version
kubectl version --client
ansible-inventory --graph
ansible-playbook playbooks/k3s.yml --syntax-check
ansible-playbook playbooks/k3s.yml --list-hosts --limit k3s-1
# See the Terraform VM runbook if recreated VMs cause host-key or ssh_askpass errors.
LC_ALL=C ssh -o BatchMode=yes ubuntu@10.77.0.11 true
ansible k3s_initial -m ping --limit k3s-1
```

The host list should show `k3s-1` for the bootstrap play and no hosts for the join play. The SSH check must succeed before the Ansible ping. If a deliberately recreated VM causes a host-key error, remove its stale host-key entry as described in the [Terraform VM runbook](terraform-libvirt-vms.md#ssh-access-after-vm-recreation); for an ordinary update, investigate rather than removing it. If Ansible reports `ssh_askpass`, load the matching private key into `ssh-agent` as described there, then retry. Keep host-key checking enabled and never add the private key to Git. The Ansible ping checks SSH and Python access without changing the guest.

## Bootstrap and validate one server

After reviewing the inventory, template, pinned installer source, and playbook, run only the bootstrap play:

```sh
ansible-playbook playbooks/k3s.yml --limit k3s-1
```

The play creates `/etc/rancher/k3s/config.yaml` with `cluster-init: true` and the API endpoint SAN, installs the pinned K3s server as a systemd service, and starts a one-member embedded etcd cluster. This temporary state proves the first-server setup only; it has no etcd fault tolerance and does not complete the HA checkpoint. The play does not install K3s on `k3s-2` or `k3s-3`.

Check the service and API locally on the guest:

```sh
LC_ALL=C ssh ubuntu@10.77.0.11 'bash -s' <<'REMOTE'
set -e
sudo systemctl is-active k3s
sudo /usr/local/bin/k3s --version
sudo /usr/local/bin/k3s kubectl get nodes
sudo /usr/local/bin/k3s kubectl get --raw='/readyz?verbose'
REMOTE
```

`kubectl` is the Kubernetes command-line client. It sends HTTPS requests to the API server using the endpoint and credentials in a kubeconfig; it can run on the host or another authorised workstation and does not need to run inside the cluster. Running it on the host here proves host-to-API connectivity and certificate validation through the same route an administrator will use. In enterprise environments, operators commonly run `kubectl` from their workstation, a controlled bastion, or CI; identities and RBAC are usually more restricted than this lab's administrator kubeconfig.

To verify the API from the host with certificate validation, copy the administrative kubeconfig to a private path outside the repository and point it at the guest's direct API address for this first check:

```sh
bash -s <<'LOCAL'
set -e
umask 077
install -d -m 0700 "$HOME/.kube"
touch "$HOME/.kube/k3s-lab.yaml"
chmod 0600 "$HOME/.kube/k3s-lab.yaml"
LC_ALL=C ssh ubuntu@10.77.0.11 'sudo cat /etc/rancher/k3s/k3s.yaml' > "$HOME/.kube/k3s-lab.yaml"
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" config set-cluster default --server=https://10.77.0.11:6443
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get nodes
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" get --raw='/readyz?verbose'
LOCAL
```

The commands run in a child Bash process so `set -e` and the restrictive `umask` do not change or terminate the interactive shell. The SSH command opens a short-lived non-interactive connection and closes it after copying the file. The kubeconfig contains administrator client credentials. Keep it under `$HOME/.kube`, do not display it, and do not add it to Git. Confirm the API response includes the ready checks and that the API certificate validates when reached at `10.77.0.11`.

## Stable endpoint and remaining servers

HAProxy does not need to be installed before the VMs or before K3s; it is an independent host service. We place it after the first-server validation so we can test the API proxy with one known-good backend, then observe backends become healthy as the other K3s servers join. The additional servers must not join until this endpoint works because they will register through it.

Review and install HAProxy on the host, then add the narrow host UFW rule required by its default-deny incoming policy:

```sh
sudo ufw allow in from 10.77.0.0/24 to 10.77.0.1 port 6443 proto tcp comment 'K3s API via HAProxy (lab only)'
sudo ufw status numbered
```

Do not replace the package configuration. It contains useful global settings for the chroot, unprivileged `haproxy` user, admin stats socket, TLS defaults, and existing HTTP defaults. The packaged systemd service loads only `/etc/haproxy/haproxy.cfg`; it does not automatically load an apt-style `conf.d` directory. Back up the file, then append a named TCP defaults section and the API frontend/backend below. This keeps the existing HTTP defaults for any other proxy sections.

```haproxy
defaults k3s_api_defaults
    mode tcp
    log global
    option tcplog
    option logasap
    timeout connect 5s
    timeout client 1h
    timeout server 1h

frontend k3s_api from k3s_api_defaults
    bind 10.77.0.1:6443
    default_backend k3s_api_servers

backend k3s_api_servers from k3s_api_defaults
    balance roundrobin
    option log-health-checks
    server k3s-1 10.77.0.11:6443 check inter 2s fall 2 rise 2
    server k3s-2 10.77.0.12:6443 check inter 2s fall 2 rise 2
    server k3s-3 10.77.0.13:6443 check inter 2s fall 2 rise 2
```

Back up the package file, append the three HAProxy sections above with `sudoedit`, validate the result, and reload HAProxy:

```sh
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
sudoedit /etc/haproxy/haproxy.cfg
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy
sudo tail -f /var/log/haproxy.log
```

Confirm the endpoint `10.77.0.1:6443` forwards TCP to the healthy K3s servers and does not depend on an in-cluster workload. `balance roundrobin` distributes new TCP connections across healthy backends. The `check` settings test whether each backend accepts TCP connections; after two failed checks HAProxy marks it down, and after two successful checks it marks it up. These layer-4 checks detect an unavailable API listener but do not validate K3s readiness or etcd health; verify readiness separately with `kubectl`. `option tcplog` with `option logasap` logs the backend/server selected for each new connection as soon as possible, while `option log-health-checks` records backend state transitions. The package configures rsyslog to write HAProxy messages to `/var/log/haproxy.log`; follow that file while nodes are added or stopped. As this is TLS pass-through, HAProxy will not see Kubernetes HTTP requests or response bodies; a long-lived client connection can also carry multiple API requests, so logs do not promise one backend choice per `kubectl` command.

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

After all three nodes report `Ready` and API operations succeed through the stable endpoint, continue with the [K3s HA validation runbook](k3s-ha-validation.md) for quorum checks, one-node failure/recovery tests, resource measurements, and a full lab restart.

## Build sequence

1. Complete the [host and VM baseline](host-and-vm-baseline.md). Confirm the `extra` pool has capacity and the paused streaming VM remains stopped.
2. Start the three equivalent VMs and verify their fixed addresses, time synchronisation, and bidirectional node connectivity; these network checks have been manually exercised.
3. Review the Ansible inventory and playbook, then bootstrap only `k3s-1` with the pinned release and embedded etcd.
4. Validate the single-node API locally and from the host, including TLS validation against the API certificate.
5. Review, install, and validate the host HAProxy endpoint. Do this before joining additional servers.
6. Join `k3s-2` and `k3s-3` sequentially through the stable endpoint using the same K3s version and server configuration.
7. Verify all three nodes, control-plane availability, datastore health, and access through the stable API endpoint.
8. Continue to the [K3s HA validation runbook](k3s-ha-validation.md) for failure, resource, and full-restart exercises.

The build procedure has been exercised through formation of the three-server cluster and stable API endpoint. Checkpoint 1 is complete only after the validation runbook's remaining evidence is recorded.

## Verification checklist

- [x] The initial `k3s-1` node reports `Ready` and the API is reachable from the host.
- [x] The API TLS certificate validates for the stable endpoint address `10.77.0.1`.
- [x] All three Kubernetes nodes report `Ready`.
- [x] API operations succeed through the stable endpoint.
- [ ] No secret, token, kubeconfig credential, or generated key was committed.

## Recovery and cleanup

VM deletion, etcd snapshot/restore, and full rebuild procedures are not yet defined. Add and test them before calling the cluster reproducible or using it for important data.
