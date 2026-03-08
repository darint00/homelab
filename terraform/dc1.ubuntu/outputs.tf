output "ubuntu_image_id" {
  description = "Downloaded Ubuntu cloud image file ID"
  value       = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
}

output "vm_ids" {
  description = "VM IDs by node key"
  value       = { for k, v in proxmox_virtual_environment_vm.ubuntu : k => v.vm_id }
}

output "vm_names" {
  description = "VM names by node key"
  value       = { for k, v in proxmox_virtual_environment_vm.ubuntu : k => v.name }
}

output "node_ipv4_plan" {
  description = "Requested IPv4 settings from variables"
  value = {
    node1 = var.node1_ipv4_address
    node2 = var.node2_ipv4_address
  }
}
