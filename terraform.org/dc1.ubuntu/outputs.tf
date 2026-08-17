output "node_count" {
  description = "Number of nodes passed to Terraform"
  value       = var.node_count
}
output "node_vm_ids" {
  description = "Map of node name → VM ID"
  value = { for k, v in proxmox_virtual_environment_vm.node : k => v.vm_id }
}

output "node_names" {
  description = "Map of node name → VM name"
  value = { for k, v in proxmox_virtual_environment_vm.node : k => v.name }
}

output "node_ips" {
  description = "Map of node name → static IP (from nodes_map)"
  value = { for k, v in local.nodes_map : k => v.ip }
}
