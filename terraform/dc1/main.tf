# =============================================================================
# Talos ISO Download
# =============================================================================

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.vm_iso_datastore
  node_name    = var.proxmox_node
  url          = "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/metal-amd64.iso"
  file_name    = "talos-${var.talos_version}-metal-amd64.iso"
  overwrite    = false
}

# =============================================================================
# Talos Secrets & Machine Configurations
# =============================================================================

# Cluster-wide PKI, bootstrap tokens, and encryption keys
resource "talos_machine_secrets" "cluster" {}

# Control plane machine configuration with static IP and VIP
data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets

  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = "${var.cluster_name}-cp-01"
          interfaces = [
            {
              interface = "eth0"
              addresses = ["${var.controlplane_ip}/${var.controlplane_cidr}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
              # VIP floats to whichever control plane node is the leader
              vip = {
                ip = var.cluster_vip
              }
            }
          ]
          nameservers = var.dns_servers
        }
        install = {
          disk = "/dev/sda"
        }
      }
    })
  ]
}

# Worker machine configuration with static IP
data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets

  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = "${var.cluster_name}-worker-01"
          interfaces = [
            {
              interface = "eth0"
              addresses = ["${var.worker_ip}/${var.worker_cidr}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
            }
          ]
          nameservers = var.dns_servers
        }
        install = {
          disk = "/dev/sda"
        }
      }
    })
  ]
}

# =============================================================================
# Proxmox VMs
# =============================================================================

resource "proxmox_virtual_environment_vm" "controlplane" {
  name        = "${var.cluster_name}-cp-01"
  node_name   = var.proxmox_node
  vm_id       = var.controlplane_vmid
  description = "Talos Kubernetes control plane for cluster '${var.cluster_name}'"
  tags        = ["talos", "kubernetes", "controlplane", var.cluster_name]

  on_boot = true

  cpu {
    cores = var.controlplane_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.controlplane_memory
  }

  # Talos manages its own guest agent; QEMU agent is not used
  agent {
    enabled = false
  }

  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  disk {
    datastore_id = var.vm_datastore
    size         = var.controlplane_disk_size
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide0"
  }

  boot_order = ["scsi0", "ide0"]

  operating_system {
    type = "l26"
  }

  # Prevent terraform from re-attaching the ISO on subsequent applies
  # after Talos has installed itself to disk
  lifecycle {
    ignore_changes = [cdrom]
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  name        = "${var.cluster_name}-worker-01"
  node_name   = var.proxmox_node
  vm_id       = var.worker_vmid
  description = "Talos Kubernetes worker for cluster '${var.cluster_name}'"
  tags        = ["talos", "kubernetes", "worker", var.cluster_name]

  on_boot = true

  cpu {
    cores = var.worker_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.worker_memory
  }

  agent {
    enabled = false
  }

  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  disk {
    datastore_id = var.vm_datastore
    size         = var.worker_disk_size
    interface    = "scsi0"
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide0"
  }

  boot_order = ["scsi0", "ide0"]

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [cdrom]
  }
}

# =============================================================================
# Talos Configuration Apply & Bootstrap
# =============================================================================

# Push machine config to the control plane node once the VM is running
resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = var.controlplane_ip

  depends_on = [proxmox_virtual_environment_vm.controlplane]
}

# Push machine config to the worker node
resource "talos_machine_configuration_apply" "worker" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = var.worker_ip

  depends_on = [proxmox_virtual_environment_vm.worker]
}

# Initialise etcd and bootstrap the control plane — run exactly once
resource "talos_machine_bootstrap" "cluster" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = var.controlplane_ip

  depends_on = [talos_machine_configuration_apply.controlplane]
}

# =============================================================================
# Cluster Health & Credentials
# =============================================================================

# Wait for the cluster to become healthy before exporting credentials
data "talos_cluster_health" "cluster" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  control_plane_nodes  = [var.controlplane_ip]
  worker_nodes         = [var.worker_ip]
  endpoints            = [var.controlplane_ip]

  depends_on = [
    talos_machine_bootstrap.cluster,
    talos_machine_configuration_apply.worker,
  ]
}

# Retrieve the kubeconfig once the cluster is healthy
data "talos_cluster_kubeconfig" "cluster" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = var.controlplane_ip

  depends_on = [data.talos_cluster_health.cluster]
}
