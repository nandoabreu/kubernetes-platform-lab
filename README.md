# Kubernetes High-Availability Lab

A practical, resource-conscious lab for learning Kubernetes platform operations, starting with a three-server K3s cluster and embedded etcd.

The lab runs on local libvirt VMs. Its first workload is a small HTTP application used to observe scheduling, service routing, and recovery. Kafka and other application platforms are outside this repository's initial scope.

## Start here

- Run `make status` for a dated host, storage, network, and VM snapshot.
- Read the [architecture](docs/architecture.md) and [roadmap](docs/roadmap.md).
- Follow the [host and VM baseline](docs/runbooks/host-and-vm-baseline.md).
- Follow the [Terraform VM runbook](docs/runbooks/terraform-libvirt-vms.md) to review and provision lab VMs.
- Use the [cluster build and verification runbook](docs/runbooks/k3s-ha-cluster.md) when the relevant roadmap checkpoint is ready.

## Initial target

```text
libvirt host
`-- three K3s server VMs
    |-- embedded etcd members (3; quorum is 2)
    |-- Kubernetes control plane on each server
    `-- lightweight HTTP demo workloads
```

The three VMs share one physical host and are not independent physical failure domains. This lab demonstrates node-level control-plane and workload behaviour, not host-level disaster tolerance.

The host is also used for other work, so the lab VMs run on demand rather than continuously. The exercises aim to explain the mechanisms and operational decisions behind Kubernetes, including capabilities that a managed cloud service may provide in a future production environment.

## Repository layout

```text
docs/         Architecture, roadmap, decisions, and runbooks
.github/      Pull request template
AGENTS.md     Repository-specific working instructions
```

Each completed roadmap checkpoint is documented and converges on a versioned GitHub release so the lab can be replayed later.
