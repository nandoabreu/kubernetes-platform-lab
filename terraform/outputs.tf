output "nodes" {
  description = "DHCP-reserved addresses and stable libvirt domain UUIDs for the lab VMs."
  value = {
    for name, node in local.nodes : name => {
      address     = node.ip
      mac         = node.mac
      domain_uuid = libvirt_domain.node[name].uuid
    }
  }
}

output "resource_budget" {
  description = "Configured VM resource capacity, not measured host consumption."
  value = {
    node_count                = length(local.nodes)
    memory_mib_per_node       = var.memory_mib
    memory_mib_total          = var.memory_mib * length(local.nodes)
    disk_gib_max_per_node     = var.disk_size_gib
    disk_gib_max_total        = var.disk_size_gib * length(local.nodes)
    base_image_capacity_gib   = var.base_image_capacity_gib
    disks_are_sparse_overlays = true
  }
}
