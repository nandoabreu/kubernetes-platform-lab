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
- an existing 4 GiB `streaming-dev` VM is paused, has autostart enabled, and must remain stopped during this lab unless capacity is deliberately reassessed.

These are observations, not reserved capacity. Recheck before each build because host use and free pool capacity change.

## Initial dated snapshot

The first Makefile status snapshot was recorded on 2026-10-07 at 16:06 +01:00. It showed 15 GiB RAM, 8.3 GiB available, 2.9 GiB of 4 GiB swap used, 8 logical CPUs, and load averages of 2.05, 1.58, and 1.28.

The `/home` ext4 filesystem had 201.56 GiB total, 140.92 GiB used, and 50.33 GiB available to an unprivileged process. After refreshing the `extra` pool, libvirt reported 201.56 GiB capacity, 140.92 GiB allocation, and 60.64 GiB available. The approximately 10.3 GiB difference is the ext4 reserved-block allowance (2,698,103 blocks at 4 KiB); `df` excludes that space from ordinary available capacity, so use its available figure for the lab budget.

Before refreshing the pool, libvirt reported 64.80 GiB available. `virsh pool-refresh extra` corrected the stale pool allocation figure. The pool directory contained 3.3 GiB of allocated files at the time of the snapshot.

The existing `streaming-dev` VM was paused with 4 GiB configured and autostart enabled. The measured 8.3 GiB host availability includes the current paused-VM state; shut it down and rerun `make status` before relying on the three-node RAM budget. These values are a dated starting point, not evidence that Checkpoint 0 is complete.

The planned 36 GiB maximum capacity for three sparse VM disks leaves 14.33 GiB below the snapshot's filesystem-available value, before accounting for the image copy or unrelated host writes. Maintain at least 10 GiB of filesystem headroom and remeasure after image download and VM creation; sparse disks can grow toward their configured maximum.

## Checkpoint 0 completion snapshot

The completion snapshot was recorded on 2026-10-08 at 14:18 +01:00 with all three lab VMs running and `streaming-dev` shut off with autostart disabled. The host reported 8.4 GiB RAM available, 3.1 GiB of 4 GiB swap used, 8 logical CPUs, and load averages of 1.02, 0.76, and 0.47.

The `/home` ext4 filesystem had 201.56 GiB total, 142.61 GiB used, and 48.64 GiB available. After pool refresh, libvirt reported `extra` at 201.56 GiB capacity, 142.61 GiB allocation, and 58.95 GiB available; the approximately 10.3 GiB difference remains the ext4 reserved-block allowance, so the budget uses `df`'s available value. The three sparse root disks have 36 GiB total virtual capacity, leaving a conservative 12.64 GiB against that available value, above the 10 GiB headroom floor. The pool directory used 5.0 GiB.

All three nodes obtained their reserved DHCP addresses (`k3s-1` at `10.77.0.11`, `k3s-2` at `10.77.0.12`, and `k3s-3` at `10.77.0.13`). The owner gracefully shut down and restarted the nodes; the same addresses were present after restart. ACPI is enabled on the domains so guest poweroff completes and libvirt reports `shut off`.

This is a shared personal host, not a dedicated cluster host. The lab VMs should be started only for an exercise and shut down afterwards. Recheck `streaming-dev` autostart before host reboots or relying on the planned memory budget.

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

Run `make status` for the same information in one dated report. It refreshes libvirt's pool inventory before displaying the pool figures; it does not start or modify VMs or volumes.

Record date, available memory, swap use, load, free space, pool availability, and running VMs. The paused `streaming-dev` VM still reserves 4 GiB of host memory; shut it down before starting the three lab VMs and reassess capacity. Its autostart setting is enabled, so account for it during host restarts.

Compare pool availability with free space on the underlying filesystem, and budget for disk growth as well as configured maximum disk sizes. For the ext4 `/home` filesystem, pool availability includes reserved blocks that ordinary users cannot allocate; use `df`'s available figure for the safety budget. Swap already in use is a reason to measure current memory pressure, not by itself proof of active swapping.

## Initial VM budget

The target is three VMs with 2 GiB RAM each (6 GiB assigned in total). Keep additional headroom for the host, libvirt/QEMU, and transient workloads. Do not use swap as the planned memory capacity for Kubernetes. If host `MemAvailable` falls materially during cluster activity or swap pressure grows, stop and reduce workload or VM allocations before proceeding. Terraform's initial disk budget is 12 GiB per VM (36 GiB maximum virtual capacity total); compare that maximum with `df`-available space and retain at least 10 GiB of filesystem headroom.

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
- A session start/stop plan accounts for other host workloads and confirms that the cluster can resume after the VMs have been shut down.
- A dated status snapshot records RAM and disk headroom and explains any difference between libvirt pool availability and filesystem availability.
- The selected guest image and SHA-256 checksum, lab network, and stable address reservations are recorded.
- All three VMs have booted, received their reserved addresses, and retained those addresses through graceful shutdown and restart.
