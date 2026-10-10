# Kubernetes Platform Lab

A practical learning lab for building and operating Kubernetes platform infrastructure on local VMs. Terraform provisions three Ubuntu guests on libvirt, Ansible forms a three-server K3s cluster with embedded etcd, and the runbooks explain how to validate the result and observe failure recovery.

> [!IMPORTANT]
> All three VMs share one physical host, storage device, power source, and host network. The lab demonstrates node-level control-plane resilience, not host-level high availability.

## What you will build

```text
Linux host (KVM/libvirt)
|-- HAProxy: stable Kubernetes API endpoint at 10.77.0.1:6443
`-- libvirt NAT network: k3s-lab (10.77.0.0/24)
    |-- k3s-1: 10.77.0.11 | K3s server | embedded etcd member
    |-- k3s-2: 10.77.0.12 | K3s server | embedded etcd member
    `-- k3s-3: 10.77.0.13 | K3s server | embedded etcd member
```

The three control-plane nodes can tolerate one K3s server being unavailable because embedded etcd retains a quorum of two. They cannot tolerate the physical host failing. See the [architecture](docs/architecture.md) for the network layers, ownership boundaries, and failure model.

## Release boundaries

| Release | Provides | Does not provide |
|---|---|---|
| `v0.0.1` | A libvirt NAT network and three stopped Ubuntu VMs provisioned with Terraform, including stable DHCP reservations, sparse disks, cloud-init SSH access, and serial consoles | K3s, Kubernetes, HAProxy, workloads, or host-level resilience |
| `v0.1.0` | A validated three-server K3s cluster with embedded etcd, a host-side HAProxy API endpoint, one-node failure exercises, and full lab restart validation | Application workloads, workload failure exercises, etcd backup/restore, or a production-ready platform |
| `v0.1.1` | Public-project documentation, licensing, portable entry points, and static validation for the existing `v0.1.0` capability | New cluster or workload capability |
| `v0.2.0` | A versioned three-replica HTTP workload, ClusterIP Service, Traefik Ingress, and verified host access through K3s ServiceLB node listeners | Node/VM failure exercises, guaranteed cross-node Pod placement, a single stable application VIP, ingress-controller HA, or a production-ready platform |
| `v0.2.1` | The recommended, ordered replay path for the `v0.2.0` workload, including VM validation, cluster setup, and the distinction between K3s-packaged Traefik and the `whoami` Ingress route | New cluster or workload capability; Checkpoint 3 failure and recovery exercises |

Checkpoint 2's workload capability was delivered by `v0.2.0`; use `v0.2.1` as the recommended replay baseline. The [documentation index](docs/README.md) gives the ordered replay path. Checkpoint 3 exercises node and workload failures; the [roadmap](docs/roadmap.md) defines the evidence required before each capability is considered complete.

## Getting started

The lab was tested on a Linux x86-64 host with 16 GiB RAM, KVM/libvirt, and storage for three VMs. See [requirements and the ordered replay path](docs/README.md) before provisioning; detailed commands live in the runbooks.

For an overview of delivered capabilities, see the [release boundaries](#release-boundaries) and [roadmap](docs/roadmap.md). For the complete replay sequence, start at the [documentation index](docs/README.md).

## Documentation

Start with the [documentation index](docs/README.md) for prerequisites and the ordered runbook path. The [architecture](docs/architecture.md) explains the design and boundaries; the [roadmap](docs/roadmap.md) tracks delivered and planned capabilities.

## Repository layout

```text
terraform/    Libvirt network and VM provisioning
ansible/      K3s server installation and cluster inventory
kubernetes/  Versioned Kubernetes workload manifests
docs/         Architecture, roadmap, evidence, and runbooks
.github/      Pull request guidance and automated checks
AGENTS.md     Instructions for coding agents working in this repository
```

## Licence

Licensed under the [Apache License 2.0](LICENSE). Copyright 2026 Fernando R. Abreu.
