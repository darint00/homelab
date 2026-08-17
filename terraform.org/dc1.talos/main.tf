# ──────────────────────────────────────────────
# dc1.talos.general  –  N-node Talos cluster
# ──────────────────────────────────────────────

locals {
  # Derive IP components from base_ip
  ip_parts  = split(".", var.base_ip)
  ip_prefix = "${local.ip_parts[0]}.${local.ip_parts[1]}.${local.ip_parts[2]}"
  ip_start  = tonumber(local.ip_parts[3])

  # Compute node map from node_count: first node is controlplane, rest are workers
  nodes_map = {
    for i in range(var.node_count) : (i == 0 ? "cp1" : "wk${i}") => {
      role = i == 0 ? "controlplane" : "worker"
      ip   = "${local.ip_prefix}.${local.ip_start + i}"
      vmid = var.base_vmid + i
    }
  }

  controlplane_nodes = { for k, v in local.nodes_map : k => v if v.role == "controlplane" }
  worker_nodes       = { for k, v in local.nodes_map : k => v if v.role == "worker" }

  cluster_endpoint = "https://${local.nodes_map["cp1"].ip}:6443"

  # For initial config apply: use bootstrap (DHCP) endpoint if provided, else static IP.
  apply_endpoints = {
    for k, v in local.nodes_map : k => (
      lookup(var.bootstrap_endpoints, k, "") != "" ? var.bootstrap_endpoints[k] : v.ip
    )
  }
}

# ── ISO ──────────────────────────────────────

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.vm_iso_datastore
  node_name    = var.proxmox_node
  url          = "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/metal-amd64.iso"
  file_name            = "${var.cluster_name}-${var.talos_version}-metal-amd64.iso"
  overwrite_unmanaged  = true
}

# ── Talos secrets ────────────────────────────

resource "talos_machine_secrets" "cluster" {}

# ── Machine configurations ───────────────────

data "talos_machine_configuration" "node" {
  for_each = local.nodes_map

  cluster_name     = var.cluster_name
  machine_type     = each.value.role
  cluster_endpoint = local.cluster_endpoint
  talos_version    = trimprefix(var.talos_version, "v")
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets

  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = "${var.vm_name_prefix}-${each.key}"
          interfaces = [
            {
              deviceSelector = {
                busPath = "0*"
              }
              addresses = ["${each.value.ip}/${var.node_cidr}"]
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

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes_map

  name        = "${var.vm_name_prefix}-${each.key}"
  description = "Talos ${each.value.role} node for ${var.cluster_name}"
  tags        = ["talos", "linux", each.value.role, var.cluster_name]

  node_name = var.proxmox_node
  vm_id     = each.value.vmid
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
    order = each.value.role == "controlplane" ? "1" : "2"
  }

  lifecycle {
    ignore_changes = [cdrom]
  }
}

# ── Apply machine configuration ─────────────

resource "talos_machine_configuration_apply" "node" {
  for_each = local.nodes_map

  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  node                        = local.apply_endpoints[each.key]
  endpoint                    = local.apply_endpoints[each.key]

  depends_on = [proxmox_virtual_environment_vm.node]
}

# ── Bootstrap ────────────────────────────────

resource "talos_machine_bootstrap" "cluster" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = local.nodes_map["cp1"].ip
  endpoint             = local.nodes_map["cp1"].ip

  depends_on = [talos_machine_configuration_apply.node]
}

# ── Health check ─────────────────────────────

data "talos_cluster_health" "cluster" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  control_plane_nodes  = [for n in local.controlplane_nodes : n.ip]
  worker_nodes         = [for n in local.worker_nodes : n.ip]
  endpoints            = [for n in local.controlplane_nodes : n.ip]

  depends_on = [
    talos_machine_bootstrap.cluster,
    talos_machine_configuration_apply.node,
  ]
}

# ── Kubeconfig ───────────────────────────────

resource "talos_cluster_kubeconfig" "cluster" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  node                 = local.nodes_map["cp1"].ip
  endpoint             = local.nodes_map["cp1"].ip

  depends_on = [data.talos_cluster_health.cluster]
}
