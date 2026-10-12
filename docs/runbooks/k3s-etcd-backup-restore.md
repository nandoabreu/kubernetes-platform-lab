# K3s Embedded etcd Backup and Restore

## Status

This runbook defines the Checkpoint 4 procedure. The backup and both restore paths still require execution and evidence on the lab host before the checkpoint is complete.

## Purpose and scope

This runbook backs up and restores Kubernetes API state in K3s's embedded etcd datastore. It exercises recovery on an existing installation and on newly provisioned VMs. It does not back up persistent application data, because the current demo workload has no persistent volumes, and it does not provide recovery from physical-host loss.

The lab stores the snapshot and original K3s server token in a private directory on the libvirt host, outside the repository and VM disks. This is sufficient for recovering deleted or damaged VM/cluster state while that host remains available. If the host is lost, this host-local copy is lost too.

K3s automatically creates local snapshots by default, but snapshots stored only inside a VM do not survive deletion or loss of that VM's disk. This procedure creates an on-demand snapshot, copies it to the host, and saves the matching server token needed to decrypt confidential data in the snapshot.

The snapshot contains Kubernetes resources and cluster certificate data. Treat both the snapshot and server token as sensitive; do not display, commit, or store them in the VM disks. Use the pinned K3s version `v1.37.1+k3s1` for this checkpoint.

## Prerequisites

- Complete the existing replay sequence through the three-server cluster and Checkpoint 3 workload exercises using the [documentation index](../README.md#replay-and-explore); this checkpoint reuses those runbooks rather than duplicating their provisioning and health checks.
- Keep the host HAProxy API endpoint available at `10.77.0.1:6443`; if the host configuration is absent, restore it using the [HAProxy endpoint runbook](host-haproxy.md) before validating with the saved kubeconfig.
- Have SSH access to `ubuntu@10.77.0.11`, `ubuntu@10.77.0.12`, and `ubuntu@10.77.0.13`, with the passwordless sudo access used by the existing runbooks.
- Have the private host-side kubeconfig at `$HOME/.kube/k3s-lab.yaml`. Do not overwrite or regenerate it before testing a restore; its validity after recovery is useful evidence that the cluster identity was restored.
- Use a private host path outside the repository and VM disks for backup artifacts. The commands below use `$HOME/.local/share/k3s-lab-backups`.

## Create and verify a backup

Set the host-side kubeconfig and confirm the cluster is healthy before changing its state:

```sh
export KUBECONFIG="$HOME/.kube/k3s-lab.yaml"
kubectl get --raw='/readyz?verbose'
kubectl wait --for=condition=Ready node --all --timeout=180s
kubectl get nodes -o wide
kubectl -n platform-demo rollout status deployment/whoami --timeout=180s
```

Create a non-secret, per-backup marker in the API. A ConfigMap is a Kubernetes key/value object; the API server persists it in etcd. The marker value includes the unique backup timestamp, is recorded in that backup's manifest, and is deliberately absent from repository manifests. This lets recovery verify which backup's state returned, rather than accepting the same static marker from an older snapshot.

```sh
SNAPSHOT_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
export SNAPSHOT_TIMESTAMP
EXPECTED_MARKER="k3s-etcd-snapshot-$SNAPSHOT_TIMESTAMP"
printf 'Backup run timestamp (UTC): %s\n' "$SNAPSHOT_TIMESTAMP"
kubectl -n platform-demo delete configmap k3s-recovery-proof --ignore-not-found
kubectl -n platform-demo create configmap k3s-recovery-proof \
  --from-literal=proof="$EXPECTED_MARKER"
kubectl -n platform-demo get configmap k3s-recovery-proof \
  -o jsonpath='{.data.proof}{"\n"}'
```

Confirm the marker output includes the current backup run timestamp. Then request an on-demand snapshot on `k3s-1` and list snapshots to note the exact K3s snapshot name:

```sh
LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo /usr/local/bin/k3s etcd-snapshot save --name k3s-etcd'
LC_ALL=C ssh ubuntu@10.77.0.11 'sudo /usr/local/bin/k3s etcd-snapshot list'
```

`LC_ALL=C` prevents the host's unavailable `en_GB.UTF-8` locale from being forwarded to the guest. K3s may still log `Unknown flag --cluster-init` and `Unknown flag --tls-san` while the `etcd-snapshot` subcommand reads the shared server configuration; those server-only settings are skipped by this subcommand, and the warnings do not indicate a failed snapshot operation. Keep both settings in the K3s server configuration. Confirm the save command reports `Snapshot ... saved` and returns successfully.

Create a timestamped private host directory and copy the exact snapshot file and original server token from `k3s-1`. Replace `<snapshot-name>` with the exact name returned by the snapshot list; do not include angle brackets:

```sh
umask 077
BACKUP_ROOT="$HOME/.local/share/k3s-lab-backups"
BACKUP_DIR="$BACKUP_ROOT/$SNAPSHOT_TIMESTAMP"
SNAPSHOT_NAME='<snapshot-name>'
SNAPSHOT_FILE="$BACKUP_DIR/k3s-etcd-snapshot"
TOKEN_FILE="$BACKUP_DIR/k3s-server-token"
MANIFEST_FILE="$BACKUP_DIR/k3s-etcd-manifest"
install -d -m 0700 "$BACKUP_DIR"
LC_ALL=C ssh ubuntu@10.77.0.11 \
  "sudo cat '/var/lib/rancher/k3s/server/db/snapshots/$SNAPSHOT_NAME'" \
  > "$SNAPSHOT_FILE"
LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo cat /var/lib/rancher/k3s/server/token' \
  > "$TOKEN_FILE"
chmod 0600 "$SNAPSHOT_FILE" "$TOKEN_FILE"
test -s "$SNAPSHOT_FILE"
test -s "$TOKEN_FILE"
sha256sum "$SNAPSHOT_FILE"
K3S_VERSION="$(LC_ALL=C ssh ubuntu@10.77.0.11 '/usr/local/bin/k3s --version')"
K3S_VERSION="${K3S_VERSION#* version }"
K3S_VERSION="${K3S_VERSION%% *}"
test -n "$K3S_VERSION"
SNAPSHOT_CHECKSUM="$(sha256sum -- "$SNAPSHOT_FILE" | cut -d' ' -f1)"
printf 'Snapshot: %s\nK3s version: %s\nSHA-256: %s\nRestore marker: %s\nBackup run timestamp (UTC): %s\n' \
  "$SNAPSHOT_NAME" "$K3S_VERSION" "$SNAPSHOT_CHECKSUM" "$EXPECTED_MARKER" "$SNAPSHOT_TIMESTAMP" \
  > "$MANIFEST_FILE"
chmod 0600 "$MANIFEST_FILE"
ls -l "$BACKUP_DIR"
```

The directory contains `k3s-etcd-snapshot`, `k3s-etcd-manifest`, and `k3s-server-token`. The manifest records non-secret metadata, including the per-backup restore marker; the snapshot and token remain private. The backup run timestamp identifies the directory and is embedded in the marker. Record the host-local path and completion time in the checkpoint evidence, but do not record the server token. Keep all three files together with restrictive permissions until both restore paths have passed.

## Restore to the existing VM installation

This path restores the existing VM installation from the selected snapshot. The Kubernetes API and workload will be unavailable until recovery succeeds.

The commands assume the backup and restore blocks run in the same host shell, so they reuse the exported timestamp generated during backup. If recovery starts in a new shell later, export `SNAPSHOT_TIMESTAMP` once using the selected backup directory name under `$HOME/.local/share/k3s-lab-backups`; do not replace it with the current time.

The marker must be absent from the live cluster before recovery so its return can only come from the snapshot:

```sh
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" \
  -n platform-demo delete configmap k3s-recovery-proof
test -z "$(kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" \
  -n platform-demo get configmap k3s-recovery-proof --ignore-not-found -o name)"
```

Copy the snapshot and token to a root-only staging directory on `k3s-1`. Use the `bash -s` heredoc pattern from the [K3s HA cluster runbook](k3s-ha-cluster.md#bootstrap-and-validate-one-server) for multiple remote commands. Stream each artifact through a separate single-command SSH call, then set its permissions in a separate call. The final checksum comparison confirms the snapshot arrived intact:

```sh
BACKUP_ROOT="$HOME/.local/share/k3s-lab-backups"
BACKUP_DIR="$BACKUP_ROOT/$SNAPSHOT_TIMESTAMP"
SNAPSHOT_FILE="$BACKUP_DIR/k3s-etcd-snapshot"
TOKEN_FILE="$BACKUP_DIR/k3s-server-token"
test -s "$SNAPSHOT_FILE"
test -s "$TOKEN_FILE"
LC_ALL=C ssh ubuntu@10.77.0.11 'bash -s' <<'REMOTE'
set -e
sudo install -d -o root -g root -m 0700 /root/k3s-restore
sudo chown root:root /root/k3s-restore
sudo chmod 0700 /root/k3s-restore
REMOTE
LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo tee /root/k3s-restore/k3s-etcd-snapshot >/dev/null' \
  < "$SNAPSHOT_FILE"
LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo chmod 0600 /root/k3s-restore/k3s-etcd-snapshot'
LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo tee /root/k3s-restore/k3s-server-token >/dev/null' \
  < "$TOKEN_FILE"
LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo chmod 0600 /root/k3s-restore/k3s-server-token'
SNAPSHOT_CHECKSUM="$(sha256sum -- "$SNAPSHOT_FILE" | cut -d' ' -f1)"
REMOTE_SNAPSHOT_CHECKSUM="$(LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo sha256sum /root/k3s-restore/k3s-etcd-snapshot' | cut -d' ' -f1)"
if [ "$SNAPSHOT_CHECKSUM" = "$REMOTE_SNAPSHOT_CHECKSUM" ]; then
  printf 'Snapshot checksum verified: %s\n' "$SNAPSHOT_CHECKSUM"
else
  printf 'Snapshot checksum mismatch: local=%s remote=%s\n' \
    "$SNAPSHOT_CHECKSUM" "$REMOTE_SNAPSHOT_CHECKSUM" >&2
  false
fi
```

Stop K3s on each server:

```sh
LC_ALL=C ssh ubuntu@10.77.0.11 'sudo systemctl stop k3s'
LC_ALL=C ssh ubuntu@10.77.0.12 'sudo systemctl stop k3s'
LC_ALL=C ssh ubuntu@10.77.0.13 'sudo systemctl stop k3s'
```

Move each etcd database directory aside to simulate loss of the data files while preserving them for rollback or inspection:

```sh
LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo mv /var/lib/rancher/k3s/server/db "/var/lib/rancher/k3s/server/db.pre-restore-$(date -u +%Y%m%dT%H%M%SZ)"'
LC_ALL=C ssh ubuntu@10.77.0.12 \
  'sudo mv /var/lib/rancher/k3s/server/db "/var/lib/rancher/k3s/server/db.pre-restore-$(date -u +%Y%m%dT%H%M%SZ)"'
LC_ALL=C ssh ubuntu@10.77.0.13 \
  'sudo mv /var/lib/rancher/k3s/server/db "/var/lib/rancher/k3s/server/db.pre-restore-$(date -u +%Y%m%dT%H%M%SZ)"'
```

Restore the snapshot on `k3s-1` using the original server token, then start that server. The reset command must report that managed etcd membership was reset and that K3s can be restarted without `--cluster-reset`:

```sh
LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo /usr/local/bin/k3s server --cluster-reset --cluster-reset-restore-path=/root/k3s-restore/k3s-etcd-snapshot --token-file=/root/k3s-restore/k3s-server-token'
LC_ALL=C ssh ubuntu@10.77.0.11 'bash -s' <<'REMOTE'
set -e
sudo systemctl start k3s
sudo systemctl is-active k3s
REMOTE
```

The snapshot restore resets membership on `k3s-1`; the other servers must rejoin the restored cluster rather than reuse their old local etcd databases. Start the two peer servers after `k3s-1` is active:

```sh
LC_ALL=C ssh ubuntu@10.77.0.12 'sudo systemctl start k3s'
LC_ALL=C ssh ubuntu@10.77.0.13 'sudo systemctl start k3s'
```

Continue with the [post-restore validation](#validate-the-restored-cluster). Do not apply repository manifests before checking the marker.

## Restore to newly provisioned VMs

This path simulates losing the VMs while retaining the host-local backup. Follow the existing [Terraform VM runbook](terraform-libvirt-vms.md) to recreate and validate the VMs; restore host HAProxy and firewall configuration separately if the host no longer has it. Use the [K3s HA cluster runbook](k3s-ha-cluster.md) to bootstrap only `k3s-1` with Ansible. Do not join `k3s-2` or `k3s-3` yet, and do not run `kubectl` against the newly bootstrapped cluster.

Set the backup location and the snapshot name recorded during backup:

```sh
BACKUP_ROOT="$HOME/.local/share/k3s-lab-backups"
BACKUP_DIR="$BACKUP_ROOT/$SNAPSHOT_TIMESTAMP"
SNAPSHOT_FILE="$BACKUP_DIR/k3s-etcd-snapshot"
TOKEN_FILE="$BACKUP_DIR/k3s-server-token"
test -s "$SNAPSHOT_FILE"
test -s "$TOKEN_FILE"
```

Copy the snapshot and server token to the new `k3s-1` using the commands in [Restore to the existing VM installation](#restore-to-the-existing-vm-installation), then stop K3s on `k3s-1`:

```sh
LC_ALL=C ssh ubuntu@10.77.0.11 'sudo systemctl stop k3s'
```

Run the same `k3s server --cluster-reset --cluster-reset-restore-path=... --token-file=...` command from the existing-installation restore section, using the copied snapshot and token. Start K3s on `k3s-1` and confirm the service is active. The restore must complete before the first `kubectl` request to this recovery target.

Use the previously saved administrative kubeconfig as the first API client if available. It should authenticate if the snapshot restored the original cluster CA and the client certificate has not expired. If the kubeconfig was lost with the old host, retrieve a fresh one over SSH from the restored server and point it at the host HAProxy endpoint:

```sh
umask 077
install -d -m 0700 "$HOME/.kube"
LC_ALL=C ssh -n ubuntu@10.77.0.11 \
  'sudo cat /etc/rancher/k3s/k3s.yaml' \
  > "$HOME/.kube/k3s-lab.yaml"
chmod 0600 "$HOME/.kube/k3s-lab.yaml"
kubectl --kubeconfig "$HOME/.kube/k3s-lab.yaml" \
  config set-cluster default --server=https://10.77.0.1:6443
```

Verify the restored marker before deleting stale node registrations or joining replacement VMs. The snapshot contains the old node objects, and newly provisioned VMs have new node identities; deleting the old node objects also removes their K3s node-password secrets. This check prints the observed value and stops before deleting nodes if it does not match:

```sh
bash -s <<'RESTORE_CHECK'
set -euo pipefail
KUBECONFIG="$HOME/.kube/k3s-lab.yaml"
EXPECTED_MARKER="k3s-etcd-snapshot-$SNAPSHOT_TIMESTAMP"
if ! ACTUAL_MARKER="$(kubectl --kubeconfig "$KUBECONFIG" \
  -n platform-demo get configmap k3s-recovery-proof \
  -o jsonpath='{.data.proof}')"; then
  printf 'Could not read the restored marker; inspect the kubectl error above\n' >&2
  exit 1
fi
if [ "$ACTUAL_MARKER" = "$EXPECTED_MARKER" ]; then
  printf 'Restored marker verified: %s\n' "$ACTUAL_MARKER"
else
  printf 'Restored marker mismatch: expected=%s actual=%s\n' \
    "$EXPECTED_MARKER" "${ACTUAL_MARKER:-<missing>}" >&2
  exit 1
fi
kubectl --kubeconfig "$KUBECONFIG" \
  delete node k3s-1 k3s-2 k3s-3 --ignore-not-found
RESTORE_CHECK
```

Join `k3s-2` and `k3s-3` to the restored cluster by following the join stage in the [K3s HA cluster runbook](k3s-ha-cluster.md#stable-endpoint-and-remaining-servers). That play reads the restored server token from `k3s-1`; it does not bootstrap another cluster.

## Validate the restored cluster

Set the kubeconfig path and verify the marker is still present with the expected value. This object is not in the repository manifests, so its return proves that data from the etcd snapshot was restored rather than recreated by applying the demo workload:

```sh
bash -s <<'VALIDATE'
set -euo pipefail
export KUBECONFIG="$HOME/.kube/k3s-lab.yaml"
EXPECTED_MARKER="k3s-etcd-snapshot-$SNAPSHOT_TIMESTAMP"
if ! ACTUAL_MARKER="$(kubectl -n platform-demo get configmap k3s-recovery-proof \
  -o jsonpath='{.data.proof}')"; then
  printf 'Could not read the restored marker; inspect the kubectl error above\n' >&2
  exit 1
fi
if [ "$ACTUAL_MARKER" = "$EXPECTED_MARKER" ]; then
  printf 'Restored marker verified: %s\n' "$ACTUAL_MARKER"
else
  printf 'Restored marker mismatch: expected=%s actual=%s\n' \
    "$EXPECTED_MARKER" "${ACTUAL_MARKER:-<missing>}" >&2
  exit 1
fi
kubectl get --raw='/readyz?verbose'
kubectl wait --for=condition=Ready node --all --timeout=300s
kubectl get nodes -o wide
kubectl -n platform-demo rollout status deployment/whoami --timeout=180s
kubectl -n platform-demo get endpointslice \
  -l kubernetes.io/service-name=whoami
curl --fail --silent --show-error \
  --resolve whoami.k3s-lab.test:80:10.77.0.11 \
  http://whoami.k3s-lab.test/
VALIDATE
```

If the existing kubeconfig is rejected after restore, stop and investigate the snapshot, token, K3s version, and API endpoint before replacing the kubeconfig; a TLS or authentication failure is not proof of a successful restore. If the restored API is healthy but the marker is absent, the restore failed its data-recovery criterion even if the manifests can be reapplied.

After both restore paths pass, record the service impact, failed dependency, recovery action, elapsed time, node/API/workload checks, snapshot checksum, and recovery target. Remove the test marker only after the evidence is recorded:

```sh
kubectl -n platform-demo delete configmap k3s-recovery-proof
```

Keep the host-local snapshot and server token only as long as needed for the lab exercise; delete them securely when the recovery test is complete. Preserve the `db.pre-restore-*` directories until the restored cluster has passed validation, then remove them from each VM to reclaim guest disk space.

## References

- [K3s backup and restore](https://docs.k3s.io/datastore/backup-restore)
- [K3s etcd snapshot and restore CLI](https://docs.k3s.io/cli/etcd-snapshot)
- [K3s node password secrets](https://docs.k3s.io/architecture#node-password-secrets)
