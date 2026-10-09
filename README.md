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

The next functional checkpoint deploys a multi-replica HTTP workload behind a Kubernetes Service. The [roadmap](docs/roadmap.md) defines the evidence required before each later capability is considered complete.

## Requirements

This is an opinionated lab tested on a Linux x86-64 host with 16 GiB RAM, KVM/libvirt, and enough storage for three 12 GiB sparse VM disks. The VMs use 2 GiB RAM and two vCPUs each. These figures describe the tested environment, not universal minimum requirements: measure your host and leave capacity for the host OS and any other VMs.

You need Git, Make, Terraform, Ansible Core, `kubectl`, a working system libvirt daemon, and an SSH public key. The detailed [requirements](docs/README.md#requirements) explain the tested assumptions.

## Quick start

The commands below take the tested path through VM provisioning. Review every plan and command before applying it to your host.

1. Clone the repository and inspect host capacity:

```sh
git clone https://github.com/nandoabreu/kubernetes-platform-lab.git
cd kubernetes-platform-lab
make requirements
make status
```

2. Download an Ubuntu Server 24.04 cloud image, verify its SHA-256 checksum against Ubuntu's published manifest, and copy the example inputs:

```sh
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

3. Edit `terraform/terraform.tfvars` so `cloud_image_path`, `storage_pool`, and `ssh_public_key_path` match your host. The tested host uses a pool named `extra` because its default pool did not have enough free space; use any existing pool with suitable capacity, or follow the libvirt documentation to create one.

4. Initialise, validate, review, and apply the Terraform plan:

```sh
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=terraform.tfplan
terraform -chdir=terraform show terraform.tfplan
terraform -chdir=terraform apply terraform.tfplan
```

This completes the `v0.0.1` boundary. Terraform deliberately leaves the VMs stopped. Continue with the [Terraform VM runbook](docs/runbooks/terraform-libvirt-vms.md#validate-and-operate) to start and validate them.

5. To reach the `v0.1.0` boundary, follow the [K3s cluster build runbook](docs/runbooks/k3s-ha-cluster.md), then perform the [failure and restart validation](docs/runbooks/k3s-ha-validation.md). The staged procedure matters: the first server is validated before HAProxy is configured and the other two servers join.

## Documentation

- [Documentation index](docs/README.md): requirements and ordered reading path.
- [Architecture](docs/architecture.md): topology, traffic layers, ownership, and failure boundaries.
- [Roadmap](docs/roadmap.md): incremental capabilities and exit evidence.
- [Host and VM baseline](docs/runbooks/host-and-vm-baseline.md): resource measurement and tested-host evidence.
- [Terraform VM runbook](docs/runbooks/terraform-libvirt-vms.md): provisioning, operation, and cleanup.
- [K3s cluster build](docs/runbooks/k3s-ha-cluster.md): bootstrap, HAProxy, and cluster formation.
- [K3s validation](docs/runbooks/k3s-ha-validation.md): quorum, node failure, and restart exercises.

## Repository layout

```text
terraform/    Libvirt network and VM provisioning
ansible/      K3s server installation and cluster inventory
docs/         Architecture, roadmap, evidence, and runbooks
.github/      Pull request guidance and automated checks
AGENTS.md     Instructions for coding agents working in this repository
```

## Licence

Licensed under the [Apache License 2.0](LICENSE). Copyright 2026 Fernando R. Abreu.
