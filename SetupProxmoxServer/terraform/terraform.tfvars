# ── Proxmox connection ─────────────────────────
proxmox_endpoint  = "https://192.168.86.240:8006"
proxmox_api_token = "terraform@pve!terraform=8f7b3ca8-dd9f-4f9c-b658-c271cd79a5d4"
proxmox_insecure  = true
proxmox_ssh_user  = "terraform"
proxmox_node      = "pve"

# ── Cluster ────────────────────────────────────
cluster_name   = "dc1"
vm_name_prefix = "dc1"
talos_version  = "v1.9.3"
install_disk   = "/dev/sda"

# ── Nodes ──────────────────────────────────────
# dc1-node1 (controlplane): VMID 330, 192.168.86.130
# dc1-node2 (worker):       VMID 331, 192.168.86.131
# dc1-node3 (worker):       VMID 332, 192.168.86.132
node_count = 3
base_ip    = "192.168.86.130"
base_vmid  = 330

# Populated automatically by cluster.sh --deploy; leave empty
bootstrap_endpoints = {}

# ── Networking ─────────────────────────────────
vm_network_bridge = "vmbr0"
node_cidr         = 24
node_gateway      = "192.168.86.1"
dns_servers       = ["192.168.86.1", "1.1.1.1"]

# ── Storage ────────────────────────────────────
vm_datastore     = "local-lvm"
vm_iso_datastore = "local"

# ── VM sizing ──────────────────────────────────
node_cpu_cores = 8
node_memory    = 32768
node_disk_size = 40
