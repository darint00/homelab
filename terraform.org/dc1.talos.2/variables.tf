# --- Proxmox Connection ---

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL"
  type        = string
  default     = "https://192.168.86.240:8006"
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
  description = "SSH username for Proxmox host"
  type        = string
  default     = "terraform"
}

variable "proxmox_node" {
  description = "Proxmox node name that hosts VMs"
  type        = string
  default     = "pve"
}

# --- Cluster ---

variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
  default     = "dc1-talos"
}

variable "vm_name_prefix" {
  description = "VM name prefix"
  type        = string
  default     = "dc1-talos"
}

variable "talos_version" {
  description = "Talos release version used for ISO download"
  type        = string
  default     = "v1.9.3"
}

variable "install_disk" {
  description = "Disk device Talos installs to"
  type        = string
  default     = "/dev/sda"
}

# --- Networking ---

variable "vm_network_bridge" {
  description = "Bridge to attach VM NICs"
  type        = string
  default     = "vmbr0"
}

variable "controlplane_ip" {
  description = "Static IPv4 for the Talos control-plane node"
  type        = string
}

variable "worker_ip" {
  description = "Static IPv4 for the Talos worker node"
  type        = string
}

variable "controlplane_bootstrap_endpoint" {
  description = "DHCP address of the control-plane node for first config apply. Discovered after VM boot. Leave empty to use controlplane_ip."
  type        = string
  default     = ""
}

variable "worker_bootstrap_endpoint" {
  description = "DHCP address of the worker node for first config apply. Discovered after VM boot. Leave empty to use worker_ip."
  type        = string
  default     = ""
}

variable "node_cidr" {
  description = "CIDR prefix length for node IPv4 addresses"
  type        = number
  default     = 24
}

variable "node_gateway" {
  description = "Default gateway for node IPv4 routing"
  type        = string
  default     = "192.168.86.1"
}

variable "dns_servers" {
  description = "DNS servers for Talos nodes"
  type        = list(string)
  default     = ["192.168.86.1", "1.1.1.1"]
}

# --- Storage ---

variable "vm_datastore" {
  description = "Datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "vm_iso_datastore" {
  description = "Datastore used for Talos ISO storage"
  type        = string
  default     = "local"
}

# --- VM IDs ---

variable "node1_vmid" {
  description = "VMID for control-plane node"
  type        = number
  default     = 320
}

variable "node2_vmid" {
  description = "VMID for worker node"
  type        = number
  default     = 321
}

# --- VM Sizing ---

variable "node_cpu_cores" {
  description = "vCPU cores per node"
  type        = number
  default     = 2
}

variable "node_memory" {
  description = "Memory (MB) per node"
  type        = number
  default     = 4096
}

variable "node_disk_size" {
  description = "Root disk size (GB) per node"
  type        = number
  default     = 40
}
