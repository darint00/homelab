output "ubuntu_image_id" {
  description = "Downloaded Ubuntu cloud image file ID"
  value       = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
}


output "node1_vm_id" {
  description = "VM ID for node1"
  value       = proxmox_virtual_environment_vm.node1.vm_id
}

output "node2_vm_id" {
  description = "VM ID for node2"
  value       = proxmox_virtual_environment_vm.node2.vm_id
}

output "node1_name" {
  description = "VM name for node1"
  value       = proxmox_virtual_environment_vm.node1.name
}

output "node2_name" {
  description = "VM name for node2"
  value       = proxmox_virtual_environment_vm.node2.name
}

output "node1_ip" {
  description = "Primary IPv4 address for node1 (from QEMU guest agent)"
  value       = try(proxmox_virtual_environment_vm.node1.ipv4_addresses[1][0], "unknown")
}

output "node2_ip" {
  description = "Primary IPv4 address for node2 (from QEMU guest agent)"
  value       = try(proxmox_virtual_environment_vm.node2.ipv4_addresses[1][0], "unknown")
}
