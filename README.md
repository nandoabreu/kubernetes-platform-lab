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

Checkpoint 2 adds a versioned HTTP workload, Kubernetes Service, and host-side route through Traefik Ingress on the private lab network. Follow the [workload routing runbook](docs/runbooks/k3s-workload-routing.md) to apply and validate it. The next functional checkpoint exercises node and workload failures. The [roadmap](docs/roadmap.md) defines the evidence required before each later capability is considered complete.

## Requirements

This is an opinionated lab tested on a Linux x86-64 host with 16 GiB RAM, KVM/libvirt, and enough storage for three 12 GiB sparse VM disks. The VMs use 2 GiB RAM and two vCPUs each. These figures describe the tested environment, not universal minimum requirements: measure your host and leave capacity for the host OS and any other VMs.

You need Git, Make, Terraform, Ansible Core, `kubectl`, a working system libvirt daemon, and an SSH public key. The detailed [requirements](docs/README.md#requirements) explain the tested assumptions.

## Quick start

The commands below take the tested path through VM provisioning. Review every plan and command before applying it to your host.

1. Clone the repository and check the required command-line tools:

```sh
git clone https://github.com/nandoabreu/kubernetes-platform-lab.git
cd kubernetes-platform-lab
make requirements
```

2. Download the Ubuntu Server 24.04 cloud image and its `SHA256SUMS` file from the [official Ubuntu image directory](https://cloud-images.ubuntu.com/noble/current/), then verify the image and inspect its virtual capacity:

```sh
sha256sum --ignore-missing --check SHA256SUMS
qemu-img info --output=json noble-server-cloudimg-amd64.img
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

3. Edit `terraform/terraform.tfvars` so `cloud_image_path`, `base_image_capacity_gib`, `storage_pool`, and `ssh_public_key_path` match your host. Derive `base_image_capacity_gib` from the virtual size reported by `qemu-img`, not the downloaded file size. The tested host uses a pool named `extra` because its default pool did not have enough free space; use any existing pool with suitable capacity, or follow the libvirt documentation to create one.

4. Inspect host capacity using the pool and storage paths you selected. The Makefile defaults describe the original test host; override them when your host differs:

```sh
make status LIBVIRT_POOL=default LIBVIRT_VOLUME_DIR=/var/lib/libvirt/images HOST_STORAGE_PATH=/var
```

5. Initialise, validate, review, and apply the Terraform plan:

```sh
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=terraform.tfplan
terraform -chdir=terraform show terraform.tfplan
terraform -chdir=terraform apply terraform.tfplan
```

Terraform deliberately leaves the VMs stopped. Continue immediately with [Start and validate the VMs](docs/runbooks/terraform-libvirt-vms.md#start-and-validate-the-vms); SSH and Ansible require the guests to be running. Completing those VM checks reaches the `v0.0.1` boundary.

6. To reach the `v0.1.0` boundary, follow the [K3s cluster build runbook](docs/runbooks/k3s-ha-cluster.md), then perform the [failure and restart validation](docs/runbooks/k3s-ha-validation.md). The staged procedure matters: the first server is validated before HAProxy is configured and the other two servers join.

7. To begin Checkpoint 2, follow the [workload routing and scheduling runbook](docs/runbooks/k3s-workload-routing.md). It shows where the Kubernetes manifests live, how `kubectl apply` sends them to the API, and how to inspect replicas, node placement, Service endpoints, events, and resource signals.

## Documentation

- [Documentation index](docs/README.md): requirements and ordered reading path.
- [Architecture](docs/architecture.md): topology, traffic layers, ownership, and failure boundaries.
- [Roadmap](docs/roadmap.md): incremental capabilities and exit evidence.
- [Host and VM baseline](docs/runbooks/host-and-vm-baseline.md): resource measurement and tested-host evidence.
- [Terraform VM runbook](docs/runbooks/terraform-libvirt-vms.md): provisioning, operation, and cleanup.
- [K3s cluster build](docs/runbooks/k3s-ha-cluster.md): bootstrap, HAProxy, and cluster formation.
- [Host HAProxy endpoints](docs/runbooks/host-haproxy.md): stable API entry point and optional single-address HTTP access for the demo.
- [K3s validation](docs/runbooks/k3s-ha-validation.md): quorum, node failure, and restart exercises.
- [Workload routing and scheduling](docs/runbooks/k3s-workload-routing.md): version, apply, and inspect the HTTP demo workload.

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
