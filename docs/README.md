# Documentation

## Requirements

- The tested environment is an Ubuntu 22.04 x86-64 host with 16 GiB RAM, KVM/libvirt, and an Intel CPU with virtualisation enabled. Host package, UFW, systemd, HAProxy, and logging commands follow Ubuntu conventions. Other Linux distributions and architectures require compatible packages, cloud images, and provider support and have not been validated by this project.
- The host needs Git, Make, Terraform CLI `>= 1.5.0, < 2.0.0`, and an active libvirt storage pool with enough underlying filesystem capacity for the cloud image and three sparse disks that can grow to 12 GiB each. Install Terraform using the [official instructions](https://developer.hashicorp.com/terraform/install).
- The host is also the Ansible controller and needs `ansible-core` (`sudo apt install ansible-core`), SSH access to the Ubuntu guests, and `kubectl` for host-side API checks; use the [official kubectl installation guide](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) and keep the client within one Kubernetes minor version of the cluster.
- HAProxy is a host-owned prerequisite for the Checkpoint 1 stable API endpoint. Install it and configure the API firewall/listener by following the [Host HAProxy API Endpoint runbook](runbooks/host-haproxy.md). Application traffic uses K3s ServiceLB and Traefik, not this HAProxy listener.
- K3s and etcd are not host prerequisites; Ansible installs the pinned K3s release on the VMs. See the [Terraform VM runbook](runbooks/terraform-libvirt-vms.md) and [K3s HA runbook](runbooks/k3s-ha-cluster.md) for the staged workflow.

Run `make requirements` to check whether the documented command-line tools are available. This checks command presence, not host virtualisation, storage capacity, versions, permissions, or network access; the runbooks validate those conditions at the relevant stage.

## Start here

- [Architecture](architecture.md): scope, target topology, and failure model.
- [Roadmap](roadmap.md): ordered learning checkpoints and release outcomes.
- [Host and VM baseline](runbooks/host-and-vm-baseline.md): capacity and VM prerequisites.
- [Terraform libvirt VMs](runbooks/terraform-libvirt-vms.md): VM input preparation, plan review, and provisioning.
- [K3s HA cluster build](runbooks/k3s-ha-cluster.md): Ansible installation, HAProxy setup, and cluster formation.
- [Host HAProxy API endpoint](runbooks/host-haproxy.md): stable K3s API listener, UFW rule, validation, and rollback.
- [K3s HA validation](runbooks/k3s-ha-validation.md): quorum, node failure/recovery, resource, and full-restart exercises.
- [K3s workload routing and scheduling](runbooks/k3s-workload-routing.md): version and apply manifests, inspect Pod placement, Service routing, events, and resource signals.

Runbooks become active when their roadmap checkpoint is implemented and validated. Architecture decisions that affect later checkpoints should be recorded under `adr/`.
