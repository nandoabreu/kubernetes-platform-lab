# Documentation

## Requirements

- The Linux host needs KVM/libvirt, the existing `extra` storage pool, Git, Make, and Terraform CLI `>= 1.5.0, < 2.0.0`; install Terraform using the [official instructions](https://developer.hashicorp.com/terraform/install).
- The host is also the Ansible controller and needs `ansible-core` (`sudo apt install ansible-core`), SSH access to the Ubuntu guests, and `kubectl` for host-side API checks; use the [official kubectl installation guide](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) and keep the client within one Kubernetes minor version of the cluster.
- Install HAProxy on the host only at the Checkpoint 1 endpoint stage, after validating the first K3s server (`sudo apt install haproxy`). The host UFW policy denies incoming traffic by default, so the HAProxy step must add a narrowly scoped rule for TCP `6443` from `10.77.0.0/24` to `10.77.0.1`.
- K3s and etcd are not host prerequisites; Ansible installs the pinned K3s release on the VMs. See the [Terraform VM runbook](runbooks/terraform-libvirt-vms.md) and [K3s HA runbook](runbooks/k3s-ha-cluster.md) for the staged workflow.

## Start here

- [Architecture](architecture.md): scope, target topology, and failure model.
- [Roadmap](roadmap.md): ordered learning checkpoints and release outcomes.
- [Host and VM baseline](runbooks/host-and-vm-baseline.md): capacity and VM prerequisites.
- [Terraform libvirt VMs](runbooks/terraform-libvirt-vms.md): VM input preparation, plan review, and provisioning.
- [K3s HA cluster build](runbooks/k3s-ha-cluster.md): Ansible installation, HAProxy setup, and cluster formation.
- [K3s HA validation](runbooks/k3s-ha-validation.md): quorum, node failure/recovery, resource, and full-restart exercises.

Runbooks become active when their roadmap checkpoint is implemented and validated. Architecture decisions that affect later checkpoints should be recorded under `adr/`.
