# K3s Embedded etcd Backup and Restore

## Status

The owner validated backup and restore to the existing VMs on 2026-10-12 with K3s `v1.37.1+k3s1`; the snapshot, checksum, restored marker, API, nodes, workload endpoints, and HTTP Ingress response passed. Restore to newly provisioned VMs remains untested and is required before Checkpoint 4 is complete.

## Purpose and scope

This runbook backs up and restores Kubernetes API state in K3s's embedded etcd datastore. It exercises recovery on an existing installation and on newly provisioned VMs. It does not back up persistent application data, because the current demo workload has no persistent volumes, and it does not provide recovery from physical-host loss.

The lab stores the snapshot and original K3s server token in a private directory on the libvirt host, outside the repository and VM disks. This is sufficient for recovering deleted or damaged VM/cluster state while that host remains available. If the host is lost, this host-local copy is lost too.

K3s automatically creates local snapshots by default, but snapshots stored only inside a VM do not survive deletion or loss of that VM's disk. This procedure creates an on-demand snapshot, copies it to the host, and saves the matching server token needed to decrypt confidential data in the snapshot.

The snapshot contains Kubernetes resources and cluster certificate data. Treat both the snapshot and server token as sensitive; do not display or commit them. The restore procedure stages temporary copies under root-only `/root/k3s-restore` on `k3s-1` and removes them during cleanup. Use the pinned K3s version `v1.37.1+k3s1` for this checkpoint.

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
SNAPSHOT_OUTPUT="$(LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo /usr/local/bin/k3s etcd-snapshot save --name k3s-etcd' 2>&1)"
printf '%s\n' "$SNAPSHOT_OUTPUT"
SNAPSHOT_NAME="${SNAPSHOT_OUTPUT##*Snapshot }"
SNAPSHOT_NAME="${SNAPSHOT_NAME%% saved*}"
case "$SNAPSHOT_NAME" in
  k3s-etcd-k3s-1-[0-9]*)
    printf 'Selected snapshot: %s\n' "$SNAPSHOT_NAME"
    ;;
  *)
    printf 'Could not parse the snapshot name from K3s output: %s\n' \
      "$SNAPSHOT_OUTPUT" >&2
    false
    ;;
esac
LC_ALL=C ssh ubuntu@10.77.0.11 'sudo /usr/local/bin/k3s etcd-snapshot list'
```

`LC_ALL=C` prevents the host's unavailable `en_GB.UTF-8` locale from being forwarded to the guest. K3s may still log `Unknown flag --cluster-init` and `Unknown flag --tls-san` while the `etcd-snapshot` subcommand reads the shared server configuration; those server-only settings are skipped by this subcommand, and the warnings do not indicate a failed snapshot operation. Keep both settings in the K3s server configuration. The save output names snapshots as `k3s-etcd-k3s-1-<unix-seconds>`; the command block extracts that name and the following list shows the snapshots on disk.

Create a timestamped private host directory and copy the snapshot file named by `SNAPSHOT_NAME` and the original server token from `k3s-1`:

```sh
umask 077
BACKUP_ROOT="$HOME/.local/share/k3s-lab-backups"
BACKUP_DIR="$BACKUP_ROOT/$SNAPSHOT_TIMESTAMP"
SNAPSHOT_FILE="$BACKUP_DIR/k3s-etcd-snapshot"
TOKEN_FILE="$BACKUP_DIR/k3s-server-token"
MANIFEST_FILE="$BACKUP_DIR/k3s-etcd-manifest"
test -n "$SNAPSHOT_NAME"
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

Install the saved server token at K3s's active token path on `k3s-1`. This ensures the normal service restart and the Ansible join play both use the token that encrypted the snapshot:

```sh
LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo install -o root -g root -m 0600 /root/k3s-restore/k3s-server-token /var/lib/rancher/k3s/server/token'
```

Restore the snapshot on `k3s-1` using the original server token. A successful reset prints `Managed etcd cluster membership has been reset, restart without --cluster-reset flag now.` K3s v1.37.1 may also log a `level=error` shutdown-request message and etcd status JSON as the one-shot reset process exits; that message is expected when the command exits successfully and prints the reset confirmation. This local Bash script starts the service only if the reset command succeeds:

```sh
bash -s <<'RESTORE'
set -euo pipefail
LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo /usr/local/bin/k3s server --cluster-reset --cluster-reset-restore-path=/root/k3s-restore/k3s-etcd-snapshot --token-file=/root/k3s-restore/k3s-server-token'
LC_ALL=C ssh ubuntu@10.77.0.11 'bash -s' <<'REMOTE'
set -e
sudo systemctl start k3s
sudo systemctl is-active k3s
REMOTE
RESTORE
```

### Verify the restored server token

Before starting the peer servers, verify that K3s wrote the saved server token and node token on `k3s-1`. The join play reads the latter; compare hashes so the token itself is never printed:

```sh
bash -s <<'TOKEN_CHECK'
set -euo pipefail
TOKEN_FILE="$HOME/.local/share/k3s-lab-backups/$SNAPSHOT_TIMESTAMP/k3s-server-token"
BACKUP_TOKEN_CHECKSUM="$(sha256sum -- "$TOKEN_FILE" | cut -d' ' -f1)"
RESTORED_SERVER_TOKEN_CHECKSUM="$(LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo sha256sum /var/lib/rancher/k3s/server/token' | cut -d' ' -f1)"
RESTORED_NODE_TOKEN_CHECKSUM="$(LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo sha256sum /var/lib/rancher/k3s/server/node-token' | cut -d' ' -f1)"
if [ "$BACKUP_TOKEN_CHECKSUM" = "$RESTORED_SERVER_TOKEN_CHECKSUM" ] && \
   [ "$BACKUP_TOKEN_CHECKSUM" = "$RESTORED_NODE_TOKEN_CHECKSUM" ]; then
  printf 'Restored server and node tokens match the backup\n'
else
  printf 'Restored token mismatch: backup=%s server=%s node=%s\n' \
    "$BACKUP_TOKEN_CHECKSUM" "$RESTORED_SERVER_TOKEN_CHECKSUM" \
    "$RESTORED_NODE_TOKEN_CHECKSUM" >&2
  exit 1
fi
TOKEN_CHECK
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

Install the saved server token at the active path before restoring. The fresh K3s bootstrap generated a temporary token; replace it so the restored service and Ansible join play use the token that encrypted the snapshot:

```sh
LC_ALL=C ssh ubuntu@10.77.0.11 \
  'sudo install -o root -g root -m 0600 /root/k3s-restore/k3s-server-token /var/lib/rancher/k3s/server/token'
```

Leave the newly bootstrapped `server/db` in place; K3s moves existing etcd files to `db/etcd-old-*` as part of `--cluster-reset-restore-path`. Run the reset-and-start script from the existing-installation restore section. K3s will use the restored token file, and the service start regenerates `node-token`; complete [Verify the restored server token](#verify-the-restored-server-token) before the first `kubectl` request or joining peer servers.

The restore decrypts and writes the original cluster CA and client certificate files from the snapshot. The normal K3s service start then rewrites `/etc/rancher/k3s/k3s.yaml` using those restored files. Use the previously saved administrative kubeconfig as the first API client if available; it should authenticate if its client certificate has not expired. If that kubeconfig is missing or fails because it contains pre-restore credentials, retrieve the post-restore kubeconfig over SSH and point it at the host HAProxy endpoint. Do not copy it from the newly bootstrapped server before the snapshot restore:

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

Confirm the three embedded etcd members are configured and started by following the [read-only etcd member list check](k3s-ha-validation.md#read-only-etcd-member-list). It must show `k3s-1`, `k3s-2`, and `k3s-3` as started voting members (`IS LEARNER` is `false`); Kubernetes node readiness alone does not confirm etcd membership.

If the saved kubeconfig is rejected with a CA mismatch, fetch `/etc/rancher/k3s/k3s.yaml` again from `k3s-1` after the restored service is running; do not use the file generated during the fresh bootstrap. K3s restores the CA and client certificate files from the snapshot, then writes the kubeconfig from those files at normal server startup. If the post-restore kubeconfig is still rejected, stop and investigate the snapshot, token, K3s version, and API endpoint; do not bypass TLS validation. If the API is healthy but the marker is absent, the restore failed its data-recovery criterion even if the manifests can be reapplied.

After both restore paths pass, record the service impact, failed dependency, recovery action, elapsed time, node/API/workload checks, etcd member list, snapshot checksum, and recovery target. Remove the test marker only after the evidence is recorded:

```sh
kubectl -n platform-demo delete configmap k3s-recovery-proof
```

## Cleanup temporary recovery state

Only after both restore paths have passed and evidence is recorded, remove the VM-side database archives, TLS archives, and staged snapshot/token. These files can contain cluster credentials. The cleanup leaves the active `/var/lib/rancher/k3s/server/token`, `/var/lib/rancher/k3s/server/node-token`, and `server/tls` files in place; K3s needs them to keep running. Run this cleanup on each VM:

```sh
LC_ALL=C ssh ubuntu@10.77.0.11 'bash -s' <<'CLEANUP'
set -euo pipefail
shopt -s nullglob
for path in \
  /var/lib/rancher/k3s/server/db.pre-restore-* \
  /var/lib/rancher/k3s/server/db/etcd-old-* \
  /var/lib/rancher/k3s/server/tls-*; do
  printf 'Removing %s\n' "$path"
  sudo rm -rf -- "$path"
done
if [ -d /root/k3s-restore ]; then
  printf 'Removing /root/k3s-restore\n'
  sudo rm -rf -- /root/k3s-restore
fi
CLEANUP
LC_ALL=C ssh ubuntu@10.77.0.12 'bash -s' <<'CLEANUP'
set -euo pipefail
shopt -s nullglob
for path in \
  /var/lib/rancher/k3s/server/db.pre-restore-* \
  /var/lib/rancher/k3s/server/db/etcd-old-* \
  /var/lib/rancher/k3s/server/tls-*; do
  printf 'Removing %s\n' "$path"
  sudo rm -rf -- "$path"
done
if [ -d /root/k3s-restore ]; then
  printf 'Removing /root/k3s-restore\n'
  sudo rm -rf -- /root/k3s-restore
fi
CLEANUP
LC_ALL=C ssh ubuntu@10.77.0.13 'bash -s' <<'CLEANUP'
set -euo pipefail
shopt -s nullglob
for path in \
  /var/lib/rancher/k3s/server/db.pre-restore-* \
  /var/lib/rancher/k3s/server/db/etcd-old-* \
  /var/lib/rancher/k3s/server/tls-*; do
  printf 'Removing %s\n' "$path"
  sudo rm -rf -- "$path"
done
if [ -d /root/k3s-restore ]; then
  printf 'Removing /root/k3s-restore\n'
  sudo rm -rf -- /root/k3s-restore
fi
CLEANUP
```

Keep or remove the host-local backup according to the lab's retention needs. If you remove it, delete only the selected timestamp directory under `$HOME/.local/share/k3s-lab-backups`; its snapshot and server token are sensitive.

## References

- [K3s backup and restore](https://docs.k3s.io/datastore/backup-restore)
- [K3s etcd snapshot and restore CLI](https://docs.k3s.io/cli/etcd-snapshot)
- [K3s node password secrets](https://docs.k3s.io/architecture#node-password-secrets)
