# --- Proxmox Connection ---

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL (e.g. https://192.168.1.10:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in format 'user@realm!tokenid=secret'"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS certificate verification for Proxmox API"
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "SSH username for Proxmox host (used for ISO uploads and VM operations)"
  type        = string
  default     = "root"
}

variable "proxmox_node" {
  description = "Proxmox node name to deploy VMs on"
  type        = string
  default     = "pve"
}

# --- Talos & Cluster ---

variable "talos_version" {
  description = "Talos Linux version to deploy (see https://github.com/siderolabs/talos/releases)"
  type        = string
  default     = "v1.9.3"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "dc1"
}

variable "cluster_vip" {
  description = "Virtual IP (VIP) for the control plane endpoint. Must be in the same subnet as control plane nodes and not assigned to any host."
  type        = string
}

# --- Network ---

variable "controlplane_ip" {
  description = "Static IP address for the control plane node (without CIDR prefix)"
  type        = string
}

variable "controlplane_cidr" {
  description = "CIDR prefix length for the control plane node (e.g. 24 for /24)"
  type        = number
  default     = 24
}

variable "worker_ip" {
  description = "Static IP address for the worker node (without CIDR prefix)"
  type        = string
}

variable "worker_cidr" {
  description = "CIDR prefix length for the worker node (e.g. 24 for /24)"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default network gateway for all nodes"
  type        = string
}

variable "dns_servers" {
  description = "List of DNS servers for all nodes"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "vm_network_bridge" {
  description = "Proxmox network bridge to attach VM NICs to"
  type        = string
  default     = "vmbr0"
}

# --- Storage ---

variable "vm_datastore" {
  description = "Proxmox datastore ID for VM disks (e.g. local-lvm, ceph-pool)"
  type        = string
  default     = "local-lvm"
}

variable "vm_iso_datastore" {
  description = "Proxmox datastore ID for ISO image storage (must support ISO content type)"
  type        = string
  default     = "local"
}

# --- VM IDs ---

variable "controlplane_vmid" {
  description = "Proxmox VM ID for the control plane node"
  type        = number
  default     = 300
}

variable "worker_vmid" {
  description = "Proxmox VM ID for the worker node"
  type        = number
  default     = 301
}

# --- Control Plane Sizing ---

variable "controlplane_cpu_cores" {
  description = "Number of vCPU cores for the control plane node"
  type        = number
  default     = 2
}

variable "controlplane_memory" {
  description = "Memory allocation for the control plane node in MB"
  type        = number
  default     = 4096
}

variable "controlplane_disk_size" {
  description = "Root disk size for the control plane node in GB"
  type        = number
  default     = 50
}

# --- Worker Sizing ---

variable "worker_cpu_cores" {
  description = "Number of vCPU cores for the worker node"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "Memory allocation for the worker node in MB"
  type        = number
  default     = 4096
}

variable "worker_disk_size" {
  description = "Root disk size for the worker node in GB"
  type        = number
  default     = 50
}
