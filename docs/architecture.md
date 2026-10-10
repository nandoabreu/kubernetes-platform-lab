# Architecture

## Purpose and scope

This repository teaches Kubernetes platform infrastructure through small, reproducible exercises on a resource-constrained homelab. The first target is a highly available K3s control plane. A lightweight HTTP workload demonstrates Kubernetes scheduling, service routing, and recovery.

The intended production context is likely a managed cloud Kubernetes service. Operating K3s on VMs is a way to understand control-plane dependencies, failure modes, and trade-offs so that managed-service guarantees and responsibilities can be evaluated rather than assumed.

Each failure exercise should record the service impact, failed dependency, detection signal, recovery owner and action, and evidence that the service recovered. For managed services, also verify the provider's explicit guarantees, exclusions, and the workload owner's remaining responsibilities.

Kafka and other application platforms are out of scope for the initial checkpoints. The demo workload exists to make platform behaviour visible; it is not a separate application project.

## Initial topology

```mermaid
flowchart TB
    subgraph host["One physical Linux host"]
        client["kubectl"] -->|"HTTPS 10.77.0.1:6443"| haproxy["HAProxy"]
        pool["libvirt storage pool"]

        subgraph network["libvirt NAT network: k3s-lab 10.77.0.0/24"]
            vm1["k3s-1<br/>10.77.0.11<br/>K3s server + etcd"]
            vm2["k3s-2<br/>10.77.0.12<br/>K3s server + etcd"]
            vm3["k3s-3<br/>10.77.0.13<br/>K3s server + etcd"]
        end

        haproxy --> vm1
        haproxy --> vm2
        haproxy --> vm3
        pool --- vm1
        pool --- vm2
        pool --- vm3
    end
```

Terraform owns only the lab network, VM domains, and VM disks. The selected storage pool and host networking remain host-owned prerequisites. The tested host uses a pool named `extra` because that filesystem had suitable capacity, but the pool name and cloud-image path are local inputs rather than architectural requirements. The lab network uses NAT for guest egress and fixed DHCP reservations for stable guest addresses; it does not expose the VMs directly to the home LAN. VMs and the network are not configured to autostart with the host.

All three VMs run the K3s server role. Each provides Kubernetes control-plane components and participates in the embedded etcd datastore. Three etcd members require a quorum of two and can tolerate one member being unavailable.

The cluster API must have a stable endpoint reachable by clients when any one server is unavailable. The selected lab design is HAProxy on the libvirt host at `10.77.0.1:6443`, forwarding to the three K3s servers. The endpoint is outside the cluster and reachable from the host and lab guests; it is host-owned and does not provide host-level high availability. The [Host HAProxy Endpoints runbook](runbooks/host-haproxy.md) documents its listener, firewall rule, validation, and rollback.

## Workload and traffic

Kubernetes node addresses and Pod addresses belong to different network layers. The VM addresses below are fixed on the libvirt network. Flannel assigns a Pod CIDR to each node and carries traffic between those Pod CIDRs by encapsulating it in VXLAN packets sent between the VM addresses.

```mermaid
flowchart LR
    subgraph vm1["k3s-1 | VM IP 10.77.0.11"]
        pod1["Pod IP<br/>node Pod CIDR"]
        flannel1["Flannel VXLAN"]
        pod1 --- flannel1
    end

    subgraph vm2["k3s-2 | VM IP 10.77.0.12"]
        flannel2["Flannel VXLAN"]
        pod2["Pod IP<br/>node Pod CIDR"]
        flannel2 --- pod2
    end

    flannel1 ==>|"UDP 8472 over 10.77.0.0/24<br/>encapsulated Pod traffic"| flannel2
```

The diagram shows one cross-node path. K3s configures the same full-mesh VXLAN relationship among all three servers. The libvirt network routes VM traffic and guest egress; Flannel provides the overlay used for Pod-to-Pod traffic across nodes. A Kubernetes Service adds another virtual addressing and routing layer, implemented by cluster networking rather than by libvirt or HAProxy.

The Checkpoint 2 demo is a small HTTP responder defined by versioned manifests under `kubernetes/`. A Deployment maintains three replicas, each response identifies the serving Pod, and a ClusterIP Service provides a stable in-cluster address and routes connections to ready Pods. Learners first apply one replica, inspect its node, then increase the desired replica count and observe the scheduler and Service. `kubectl get pods -o wide` correlates Pods with nodes. The initial Deployment has no placement rule; topology spread is a follow-up scheduling exercise. The Service does not place workloads or guarantee that replicas occupy distinct nodes.

The operator applies repository manifests to the K3s API using `kubectl` and a private kubeconfig. Git versions the desired configuration and change history; Kubernetes stores and reconciles the live objects. This lab uses direct `kubectl apply` and does not configure a GitOps controller.

Host-side HTTP access uses the packaged Traefik Ingress Controller and K3s ServiceLB: VM IPs on the private libvirt network expose Traefik on port `80`, and an Ingress rule routes a matching HTTP Host to the demo ClusterIP Service. ServiceLB advertises the node IPs individually; the Ingress Host rule does not provide a single stable virtual IP or DNS record. An optional host HAProxy listener at `10.77.0.1:80` can provide one address by forwarding to the three Traefik listeners; it is host-owned and shares the physical host failure boundary. Both paths are separate from the host HAProxy endpoint for the Kubernetes API on port `6443`. Neither exposes the application to the home LAN or Internet.

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

Use a libvirt pool with enough underlying filesystem capacity for VM disk growth. The tested path uses the `extra` pool, but users should select an existing suitable pool or follow the libvirt documentation to create one. Host memory, swap, disk, and CPU pressure must be measured during exercises.

Each VM is configured with two vCPUs, for six vCPUs total on a host with four physical cores and eight logical CPUs. These are schedulable virtual CPUs, not pinned or reserved physical cores; performance depends on concurrent host and guest workloads.
