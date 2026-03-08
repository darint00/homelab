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

# --- Nodes ---

variable "node_count" {
  description = "Total number of cluster nodes (1 controlplane + N-1 workers)"
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 1
    error_message = "node_count must be at least 1."
  }
}

variable "base_ip" {
  description = "IP address of the first node; subsequent nodes increment the last octet"
  type        = string
  default     = "192.168.86.130"
}

variable "base_vmid" {
  description = "Starting Proxmox VMID; subsequent nodes increment by 1"
  type        = number
  default     = 320
}

variable "bootstrap_endpoints" {
  description = "Map of node name to DHCP address for initial config apply. Populated by cluster.sh during deploy."
  type        = map(string)
  default     = {}
}

# --- Networking ---

variable "vm_network_bridge" {
  description = "Bridge to attach VM NICs"
  type        = string
  default     = "vmbr0"
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
