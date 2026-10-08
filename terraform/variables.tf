variable "libvirt_uri" {
  description = "Libvirt connection URI for the local system daemon."
  type        = string
  default     = "qemu:///system"
}

variable "storage_pool" {
  description = "Existing host-owned libvirt storage pool for lab volumes."
  type        = string
  default     = "extra"
}

variable "cloud_image_path" {
  description = "Path to a locally downloaded and checksum-verified Ubuntu 24.04 cloud image."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key installed on each guest."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "base_image_capacity_gib" {
  description = "Virtual capacity of the cloud image volume in GiB, not VM RAM or root-disk capacity."
  type        = number
  default     = 3.5
}

variable "memory_mib" {
  description = "RAM assigned to each Kubernetes lab VM in MiB."
  type        = number
  default     = 2048
}

variable "vcpu" {
  description = "Virtual CPUs assigned to each Kubernetes lab VM."
  type        = number
  default     = 2
}

variable "disk_size_gib" {
  description = "Maximum sparse root-disk capacity for each VM in GiB."
  type        = number
  default     = 12
}
