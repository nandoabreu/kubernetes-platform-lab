# Host and VM Baseline

## Purpose

Record the conditions needed to decide whether the three-VM lab can run safely. Do this before provisioning or changing host configuration.

## Known host facts

The initial inspection found:

- Dell Inspiron 5590, Intel i7-10510U (4 cores / 8 threads), VT-x available;
- 16 GiB RAM and 4 GiB swap;
- `/dev/kvm`, KVM, and libvirt are available;
- libvirt pool `extra` points to `/home/common/libvirt` on `/home`;
- `extra` reported about 64.8 GiB available at inspection time;
- an existing 4 GiB `streaming-dev` VM is paused and must remain stopped during this lab unless capacity is deliberately reassessed.

These are observations, not reserved capacity. Recheck before each build because host use and free pool capacity change.

## Baseline checks

Run these read-only checks on the libvirt host:

```sh
free -h
uptime
df -h / /home /var
virsh pool-info extra
virsh list --all
virsh dominfo streaming-dev
```

Record date, available memory, swap use, load, free space, pool availability, and running VMs. Do not start the paused `streaming-dev` VM alongside the three planned VMs without re-evaluating the memory budget.

## Initial VM budget

The target is three VMs with 2 GiB RAM each (6 GiB assigned in total). Keep additional headroom for the host, libvirt/QEMU, and transient workloads. Do not use swap as the planned memory capacity for Kubernetes. If host `MemAvailable` falls materially during cluster activity or swap pressure grows, stop and reduce workload or VM allocations before proceeding.

Use the `extra` pool for VM disks. Check pool free space and the planned maximum disk sizes, not only current sparse allocation. Preserve room for host operations and image growth.

## Network and access facts to record

Before cluster installation, document:

- VM network and addressing method;
- how host and guest addresses are discovered and kept stable;
- client reachability to the Kubernetes API endpoint;
- the selected stable API endpoint and how it survives one server failure;
- access path to the demo workload, if external access is needed;
- ports opened and the rollback procedure for any host firewall changes.

Do not assume Wi-Fi bridging or direct LAN attachment works for libvirt guests. Validate the chosen path with the actual host and network.

## Completion criteria

- Current host and pool capacity are recorded.
- Three 2 GiB VMs can be allocated without consuming the host's safety margin.
- Guest image, network plan, API endpoint approach, and required disk capacity are documented.
- No host networking or firewall change is required without an explicit, reversible procedure.
