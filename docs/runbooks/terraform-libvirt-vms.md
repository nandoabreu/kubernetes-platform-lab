# Terraform Libvirt VMs

## Purpose and scope

Terraform manages the lab-only NAT network, three VM domains, and their disks. The existing `extra` storage pool and `default` libvirt network remain untouched. New VM domains and the lab network do not autostart with the host. Terraform creates VMs stopped and ignores later changes to their running state, leaving session start and stop operations to the operator.

## Inputs

- Ubuntu Server 24.04 LTS cloud image downloaded locally and verified against its SHA-256 manifest.
- The shared image at `/home/common/cache/libvirt/noble-server-cloudimg-amd64.img` is QCOW2 with a 3.5 GiB virtual capacity and about 596 MiB of allocated file data; its SHA-256 is `6e40c07ae715f744f84af0bec76415cc1987dd115b4b8de437818561f01a3733`.
- `base_image_capacity_gib` sets the base image's virtual disk capacity. It is 3.5 GiB for this image, not RAM and not the 12 GiB root-disk size of each VM.
- A local SSH public key; never copy the private key into this repository.
- The `extra` pool must be active with enough physical filesystem space for image and VM disk growth.
- The Terraform provider connects to the local system libvirt daemon through `qemu:///system`.

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and update the image path and public-key path if needed. The local tfvars file, Terraform state, plans, provider cache, and VM images are ignored by Git.

## Review and provision

From the repository root, run the following commands and inspect the plan before applying it:

```sh
make status
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=terraform.tfplan
terraform -chdir=terraform show terraform.tfplan
```

The plan should create one isolated NAT network, one base image volume, three sparse 12 GiB VM disks, three cloud-init volumes, and three stopped 2 GiB VM domains. It reserves `10.77.0.11` through `10.77.0.13` by DHCP using fixed MAC addresses. The existing `default` network is not changed.

The VM disks use QCOW2 copy-on-write overlays with sparse allocation requested. Their 12 GiB capacity is a maximum; physical filesystem use grows as the guests write data. The imported base image consumes approximately the source image's allocated data. Use `make status` to compare actual `/home` free space with the pool's figures.

Only after reviewing the complete plan, apply it with:

```sh
terraform -chdir=terraform apply terraform.tfplan
```

Applying creates libvirt resources but leaves the VMs stopped. Terraform does not start them or configure K3s.

## Validate and operate

Run `make status` and confirm the domains and `k3s-lab` network exist. Check the network state and start it only if inactive, then start VMs explicitly when ready:

```sh
virsh net-info k3s-lab
# Run the next command only if Active is no.
virsh net-start k3s-lab
virsh start k3s-1
virsh start k3s-2
virsh start k3s-3
virsh list --all
virsh net-dhcp-leases k3s-lab
```

The DHCP reservations should assign `10.77.0.11`, `10.77.0.12`, and `10.77.0.13` to `k3s-1`, `k3s-2`, and `k3s-3`. The network provides guest egress and host-to-guest access, not direct home-LAN exposure.

Connect to a guest's serial console for boot output and an interactive terminal:

```sh
virsh console k3s-1
```

Replace the domain name to connect to another node. Press `Ctrl+]` to detach from the console without stopping the VM.

The domains expose ACPI so Ubuntu can process a graceful power-button request. `virsh shutdown` only submits that request; wait for `virsh domstate` or `virsh list --all` to report `shut off` before assuming the host memory has been released.

Shut down guests gracefully after each session:

```sh
virsh shutdown k3s-1
virsh shutdown k3s-2
virsh shutdown k3s-3
virsh list --all
```

If the guest reaches its poweroff target but remains `running` in libvirt, inspect the serial console and check ACPI configuration before retrying. `virsh destroy` forcibly stops a domain without deleting its definition or disks; reserve it for a guest that is already halted or otherwise cannot complete a graceful shutdown.

## Cleanup

Run cleanup from the same working directory and local Terraform state used to provision the lab; the state file is ignored by Git. Gracefully shut down every running guest first, resume any paused guest before shutting it down, and confirm `virsh list --all` shows the lab VMs as shut off. Then create and inspect a saved destroy plan before applying that exact plan:

```sh
terraform -chdir=terraform plan -destroy -out=terraform.destroy.tfplan
terraform -chdir=terraform show terraform.destroy.tfplan
terraform -chdir=terraform apply terraform.destroy.tfplan
```

Destroying the Terraform-managed resources deletes the lab domains, their QCOW2 overlays, the imported base-image volume, cloud-init volumes, and NAT network from `/home/common/libvirt`. It reclaims the physical blocks those managed volumes used, but leaves the source image at the path configured by `cloud_image_path` (currently `/home/common/cache/libvirt/noble-server-cloudimg-amd64.img`), the `extra` pool itself, the existing `streaming-dev` VM, and the `default` network untouched.
