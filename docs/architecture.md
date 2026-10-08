# Architecture

## Purpose and scope

This repository teaches Kubernetes platform infrastructure through small, reproducible exercises on a resource-constrained homelab. The first target is a highly available K3s control plane. A lightweight HTTP workload demonstrates Kubernetes scheduling, service routing, and recovery.

The intended production context is likely a managed cloud Kubernetes service. Operating K3s on VMs is a way to understand control-plane dependencies, failure modes, and trade-offs so that managed-service guarantees and responsibilities can be evaluated rather than assumed.

Each failure exercise should record the service impact, failed dependency, detection signal, recovery owner and action, and evidence that the service recovered. For managed services, also verify the provider's explicit guarantees, exclusions, and the workload owner's remaining responsibilities.

Kafka and other application platforms are out of scope for the initial checkpoints. The demo workload exists to make platform behaviour visible; it is not a separate application project.

## Initial topology

```text
Physical libvirt host
|-- libvirt pool: extra (VM disks)
|-- Terraform-managed NAT network: k3s-lab (10.77.0.0/24)
|-- k3s-1 (2 GiB RAM): server + embedded etcd member
|-- k3s-2 (2 GiB RAM): server + embedded etcd member
`-- k3s-3 (2 GiB RAM): server + embedded etcd member
```

Terraform owns only the lab network, VM domains, and VM disks. The existing `extra` storage pool and host networking remain host-owned prerequisites. The lab network uses NAT for guest egress and fixed DHCP reservations for stable guest addresses; it does not expose the VMs directly to the home LAN. VMs and the network are not configured to autostart with the host.

All three VMs run the K3s server role. Each provides Kubernetes control-plane components and participates in the embedded etcd datastore. Three etcd members require a quorum of two and can tolerate one member being unavailable.

The cluster API must have a stable endpoint reachable by clients when any one server is unavailable. The endpoint implementation and its placement are an explicit design decision to settle before the cluster-build checkpoint is automated. It must not depend solely on a workload inside the cluster to make the Kubernetes API reachable.

## Workload and traffic

The initial demo is a small HTTP responder deployed with multiple replicas. Responses should identify the serving Pod and, where practical, its node. A Kubernetes Service provides a stable in-cluster address and routes connections to ready Pods. The scheduler places Pods on nodes; the Service does not place workloads or guarantee that replicas occupy distinct nodes.

An external load balancer for the demo application is a separate exercise from the stable API endpoint. Begin with in-cluster Service routing and add external access only when its networking model is selected and documented.

## Failure model and limitations

- Loss of one K3s server leaves two etcd members, preserving quorum.
- Loss of two servers removes etcd quorum; normal control-plane writes are unavailable until quorum is restored.
- Workloads already running may continue during control-plane disruption, but scheduling and reconciliation are impaired.
- Replicated Pods can recover from an individual Pod or node failure only when sufficient healthy nodes and resources remain and the workload is configured with appropriate replicas and placement.
- All VMs share one physical host, power source, storage device, and host network. Physical-host failure takes down the entire lab.
- The physical host serves other personal workloads; lab VMs run on demand and must not be assumed to remain available between sessions.
- This is a learning environment, not a production service or a production availability claim.

## Resource and ownership boundaries

- The host and libvirt own the physical environment and storage pools.
- Terraform owns the lab NAT network, VM domains, and VM disks; it does not configure the host OS or manage Kubernetes workloads.
- K3s owns cluster control-plane and node services.
- Kubernetes manifests or Helm own demo workloads and their in-cluster resources.
- Local VM state, generated credentials, and secrets remain outside Git.

Use the `extra` libvirt pool for VM disks, subject to checking current free capacity and retaining operational headroom before provisioning. Host memory, swap, disk, and CPU pressure must be measured during exercises.

Each VM is configured with two vCPUs, for six vCPUs total on a host with four physical cores and eight logical CPUs. These are schedulable virtual CPUs, not pinned or reserved physical cores; performance depends on concurrent host and guest workloads.
