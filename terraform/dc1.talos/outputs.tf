output "cluster_name" {
  description = "Talos cluster name"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint URL"
  value       = local.cluster_endpoint
}

output "node_ips" {
  description = "Map of node name → static IP"
  value       = { for k, v in local.nodes_map : k => v.ip }
}

output "node_vmids" {
  description = "Map of node name → Proxmox VMID"
  value       = { for k, v in local.nodes_map : k => v.vmid }
}

output "kubeconfig" {
  description = "Cluster kubeconfig (admin)"
  value       = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Talosctl client configuration"
  value       = talos_machine_secrets.cluster.client_configuration
  sensitive   = true
}
