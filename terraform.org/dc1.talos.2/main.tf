# ──────────────────────────────────────────────
# dc1.talos.claude  –  Two-node Talos cluster
# ──────────────────────────────────────────────

locals {
  cluster_endpoint = "https://${var.controlplane_ip}:6443"

  # For first config apply, use the bootstrap (DHCP) endpoint if set;
  # otherwise fall back to the static IP.
  cp_apply_endpoint = var.controlplane_bootstrap_endpoint != "" ? var.controlplane_bootstrap_endpoint : var.controlplane_ip
  wk_apply_endpoint = var.worker_bootstrap_endpoint != "" ? var.worker_bootstrap_endpoint : var.worker_ip
}

# ── ISO ──────────────────────────────────────

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.vm_iso_datastore
  node_name    = var.proxmox_node
  url          = "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/metal-amd64.iso"
  file_name            = "${var.cluster_name}-claude-${var.talos_version}-metal-amd64.iso"
  overwrite_unmanaged  = true
}

# ── Talos secrets ────────────────────────────

resource "talos_machine_secrets" "cluster" {}

# ── Machine configurations ───────────────────

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = local.cluster_endpoint
  talos_version    = trimprefix(var.talos_version, "v")
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets

  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = "${var.vm_name_prefix}-cp"
          interfaces = [
            {
              deviceSelector = {
                busPath = "0*"
              }
              addresses = ["${var.controlplane_ip}/${var.node_cidr}"]
              dhcp      = false
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.node_gateway
                }
              ]
            }
          ]
          nameservers = var.dns_servers
        }
        install = {
          disk = var.install_disk
        }
      }
    })
  ]
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = local.cluster_endpoint
  talos_version    = trimprefix(var.talos_version, "v")
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets

  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = "${var.vm_name_prefix}-wk"
          interfaces = [
            {
              deviceSelector = {
                busPath = "0*"
              }
              addresses = ["${var.worker_ip}/${var.node_cidr}"]
              dhcp      = false
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.node_gateway
                }
              ]
            }
          ]
          nameservers = var.dns_servers
        }
        install = {
          disk = var.install_disk
        }
      }
    })
  ]
}

# ── Proxmox VMs ──────────────────────────────

resource "proxmox_virtual_environment_vm" "controlplane" {
  name        = "${var.vm_name_prefix}-cp"
  description = "Talos control-plane node for ${var.cluster_name}"
  tags        = ["talos", "linux", "controlplane", var.cluster_name]

  node_name = var.proxmox_node
  vm_id     = var.node1_vmid
  on_boot   = true

  cpu {
    cores = var.node_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.node_memory
  }

  agent {
    enabled = false
  }

  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    file_format  = "raw"
    size         = var.node_disk_size
    discard      = "on"
    ssd          = true
  }

  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide0"
  }

  boot_order = ["ide0", "scsi0"]

  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  startup {
    order = "1"
  }

  lifecycle {
    ignore_changes = [cdrom]
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  name        = "${var.vm_name_prefix}-wk"
  description = "Talos worker node for ${var.cluster_name}"
  tags        = ["talos", "linux", "worker", var.cluster_name]

  node_name = var.proxmox_node
  vm_id     = var.node2_vmid
  on_boot   = true

  cpu {
    cores = var.node_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.node_memory
  }

  agent {
    enabled = false
  }

  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    file_format  = "raw"
    size         = var.node_disk_size
    discard      = "on"
    ssd          = true
  }

  cdrom {
    enabled   = true
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide0"
  }

  boot_order = ["ide0", "scsi0"]

  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  startup {
    order = "2"
  }

  lifecycle {
    ignore_changes = [cdrom]
  }
}

# ── Apply machine configuration ─────────────
#
# When a Talos VM first boots from the ISO it gets a DHCP address.
# Set controlplane_bootstrap_endpoint / worker_bootstrap_endpoint to those
# DHCP addresses so config apply can reach the nodes.  After config apply,
# Talos installs to disk and reboots with the static IP.
# Bootstrap/health/kubeconfig then target the static IP directly.

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = local.cp_apply_endpoint
  endpoint                    = local.cp_apply_endpoint

  depends_on = [proxmox_virtual_environment_vm.controlplane]
}

resource "talos_machine_configuration_apply" "worker" {
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = local.wk_apply_endpoint
  endpoint                    = local.wk_apply_endpoint

  depends_on = [
    proxmox_virtual_environment_vm.worker,
    talos_machine_configuration_apply.controlplane,
  ]
}

# ── Bootstrap ────────────────────────────────

resource "talos_machine_bootstrap" "cluster" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = var.controlplane_ip
  endpoint             = var.controlplane_ip

  depends_on = [talos_machine_configuration_apply.controlplane]
}

# ── Health check ─────────────────────────────

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

# ── Kubeconfig ───────────────────────────────

resource "talos_cluster_kubeconfig" "cluster" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = var.controlplane_ip
  endpoint             = var.controlplane_ip

  depends_on = [data.talos_cluster_health.cluster]
}
