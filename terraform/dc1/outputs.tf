output "kubeconfig" {
  description = "Raw kubeconfig for the Kubernetes cluster. Save to ~/.kube/config or use KUBECONFIG env var."
  value       = data.talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Talos client configuration. Save to ~/.talos/config or use TALOSCONFIG env var."
  value       = talos_machine_secrets.cluster.client_configuration
  sensitive   = true
}

output "controlplane_ip" {
  description = "Control plane node IP address"
  value       = var.controlplane_ip
}

output "worker_ip" {
  description = "Worker node IP address"
  value       = var.worker_ip
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = "https://${var.cluster_vip}:6443"
}

output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = var.cluster_name
}
