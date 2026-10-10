# Roadmap

## Delivery principles

- Add one major operational concept at a time.
- Every checkpoint ends in a working, verified state that can be replayed.
- Keep the process practical and resource-aware; measure before increasing allocations or adding components.
- Exercise failure and recovery, not only successful deployment.
- For each failure, record service impact, failed dependency, detection signal, recovery owner/action, and recovery evidence.
- Make each checkpoint usable on demand: document how to start, validate, stop, and resume the lab without assuming an always-on host.
- Review all changes before committing. Documentation-only changes may go directly to `main` after review; functional changes use a pull request.
- Converge each completed checkpoint on a versioned GitHub release with the matching source and replay instructions.

## Checkpoints

| Checkpoint | Capability | Exit evidence | Release outcome |
|---|---|---|---|
| 0 | Capture dated host capacity, reconcile pool and filesystem space, define the image/network/address plan, and provision three VMs with Terraform | Measurements record RAM/disk headroom; the image checksum is verified; Terraform creates three 2 GiB VMs with stable addresses on the lab NAT network; the VMs can be stopped and restarted on demand | Baseline and VM provisioning release |
| 1 | Form a three-server K3s cluster with embedded etcd | All servers are Ready; etcd quorum is healthy; stable API endpoint works | First cluster release |
| 2 | Store and apply a small HTTP workload manifest; observe one replica, scale to three, route in-cluster requests through a Kubernetes Service, and access the Service from the host through Traefik Ingress | The manifests are versioned in the repository and applied with `kubectl`; in-cluster and host-side requests succeed and responses expose which replica served them; Pod placement, endpoints, events, and basic resource signals can be inspected | Workload-routing release |
| 3 | Exercise control-plane and workload failures | With one replica, stop its node and observe the Service interruption and replacement scheduling; then restore the cluster, run three replicas with deliberate node spread, stop one node, and observe traffic to remaining ready replicas; a failed Pod is recreated; each exercise records impact, detection, recovery owner/action, and recovery evidence | Failure-exercise release |
| 4 | Rebuild the lab reproducibly | A documented clean replay recreates the checkpoint from versioned inputs without relying on undocumented state | Rebuild release |
| 5 | Automate the proven lifecycle | Provisioning and cluster configuration are repeatable, reviewed, and have a tested rollback/cleanup path | Automation release |

Checkpoint order may be refined as practical work reveals dependencies. Do not add a future tool or directory before its checkpoint needs it.

## Release and replay convention

- Use one GitHub release for each completed checkpoint.
- Tag the exact reviewed commit that satisfies the checkpoint's exit evidence.
- Include the checkpoint name, validation summary, and replay entry point in the release notes.
- Keep replay instructions in the repository; a release must not depend on undocumented manual state.
- Release creation and tagging require explicit owner authorisation.

## Current focus

Checkpoint 0 was validated on 2026-10-08: dated host and storage budgets are recorded, the guest image checksum is verified, Terraform provisions three on-demand libvirt VMs with stable addresses, and all three passed DHCP, graceful shutdown, and restart checks. Checkpoint 1's three-server K3s cluster, host HAProxy endpoint, etcd membership, individual node failure/recovery exercises, and full lab restart were validated on 2026-10-09. The [K3s HA validation runbook](runbooks/k3s-ha-validation.md) records the evidence. Release `v0.1.1` changes how the existing lab is licensed, explained, and validated for public use; it does not add cluster capability or alter the Checkpoint 1 topology. Checkpoint 2 was validated by the owner on 2026-10-10: one and then three replicas served requests through the ClusterIP Service; all three Pods were Ready and initially landed one per node without a placement rule; EndpointSlice membership, Pod replacement, and `kubectl top` were inspected; and repeated host requests entering only through `10.77.0.11:80` returned HTTP `200` from Pods in all three node Pod CIDRs. The [workload routing runbook](runbooks/k3s-workload-routing.md) records how one Traefik listener reaches ready application Pods across the cluster. Release `v0.2.0` records the completed Checkpoint 2 capability. The next functional focus is Checkpoint 3: exercise a single-node failure first with one replica and then with three deliberately spread replicas, recording service impact, detection, and recovery. No Checkpoint 3 workload failure exercise has been performed.

After the initial cluster and recovery exercises, relate each component to a managed cloud Kubernetes service: identify what the provider operates, what remains the workload owner's responsibility, and which availability, backup, networking, security, observability, and cost assumptions still need verification. Do not add cloud resources to the initial lab just to make this comparison.
