output "cluster_name" {
  description = "Talos cluster name"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = local.cluster_endpoint
}

output "controlplane_ip" {
  description = "Static IPv4 for control-plane node"
  value       = var.controlplane_ip
}

output "worker_ip" {
  description = "Static IPv4 for worker node"
  value       = var.worker_ip
}

output "controlplane_vmid" {
  description = "Control-plane VMID"
  value       = proxmox_virtual_environment_vm.controlplane.vm_id
}

output "worker_vmid" {
  description = "Worker VMID"
  value       = proxmox_virtual_environment_vm.worker.vm_id
}

output "kubeconfig" {
  description = "Raw kubeconfig for the cluster"
  value       = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Talos client configuration (ca_certificate, client_certificate, client_key)"
  value       = talos_machine_secrets.cluster.client_configuration
  sensitive   = true
}
