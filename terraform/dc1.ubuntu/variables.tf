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

variable "cluster_name" {
  description = "Name prefix used for VM tags and labels"
  type        = string
  default     = "dc1-ubuntu"
}

variable "vm_name_prefix" {
  description = "VM name prefix"
  type        = string
  default     = "dc1-ubuntu"
}

variable "ubuntu_image_url" {
  description = "Ubuntu cloud image URL"
  type        = string
  default     = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

variable "ubuntu_image_file_name" {
  description = "Filename used in Proxmox datastore for the Ubuntu cloud image"
  type        = string
  default     = "jammy-server-cloudimg-amd64.qcow2"
}

variable "vm_datastore" {
  description = "Datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "vm_image_datastore" {
  description = "Datastore used to store downloaded cloud image import file"
  type        = string
  default     = "local"
}

variable "cloud_init_datastore" {
  description = "Datastore for cloud-init disk"
  type        = string
  default     = "local-lvm"
}

variable "cloud_init_snippets_datastore" {
  description = "Datastore that supports 'snippets' content for cloud-init user-data files"
  type        = string
  default     = "local"
}

variable "vm_network_bridge" {
  description = "Bridge to attach VM NICs"
  type        = string
  default     = "vmbr0"
}

variable "dns_servers" {
  description = "DNS servers passed via cloud-init"
  type        = list(string)
  default     = ["192.168.86.1", "1.1.1.1"]
}

variable "cloud_init_username" {
  description = "Default cloud-init user"
  type        = string
  default     = "ubuntu"
}

variable "cloud_init_password" {
  description = "Optional cloud-init password. Leave empty if using SSH keys only."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloud_init_ssh_public_keys" {
  description = "SSH public keys to inject via cloud-init"
  type        = list(string)
  default     = []
}

variable "node1_vmid" {
  description = "VMID for first Ubuntu node"
  type        = number
  default     = 310
}

variable "node2_vmid" {
  description = "VMID for second Ubuntu node"
  type        = number
  default     = 311
}

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

variable "node1_ipv4_address" {
  description = "Node 1 IPv4 CIDR or 'dhcp'"
  type        = string
  default     = "dhcp"
}

variable "node1_ipv4_gateway" {
  description = "Node 1 IPv4 gateway. Leave empty when node1_ipv4_address is 'dhcp'."
  type        = string
  default     = ""
}

variable "node2_ipv4_address" {
  description = "Node 2 IPv4 CIDR or 'dhcp'"
  type        = string
  default     = "dhcp"
}

variable "node2_ipv4_gateway" {
  description = "Node 2 IPv4 gateway. Leave empty when node2_ipv4_address is 'dhcp'."
  type        = string
  default     = ""
}
