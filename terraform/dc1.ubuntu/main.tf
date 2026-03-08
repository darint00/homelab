locals {
  nodes = {
    node1 = {
      vm_id        = var.node1_vmid
      name         = "${var.vm_name_prefix}-01"
      ipv4_address = var.node1_ipv4_address
      ipv4_gateway = var.node1_ipv4_gateway
      startup      = "1"
    }
    node2 = {
      vm_id        = var.node2_vmid
      name         = "${var.vm_name_prefix}-02"
      ipv4_address = var.node2_ipv4_address
      ipv4_gateway = var.node2_ipv4_gateway
      startup      = "2"
    }
  }

  cloud_init_users = [
    "default",
    {
      name              = var.cloud_init_username
      groups            = "sudo"
      shell             = "/bin/bash"
      sudo              = "ALL=(ALL) NOPASSWD:ALL"
      ssh_authorized_keys = var.cloud_init_ssh_public_keys
    }
  ]

  cloud_init_by_node = {
    for k, n in local.nodes : k => merge(
      {
        hostname       = n.name
        package_update = true
        package_upgrade = false
        packages       = ["qemu-guest-agent"]
        users          = local.cloud_init_users
        runcmd         = ["systemctl enable --now qemu-guest-agent"]
      },
      var.cloud_init_password != "" ? {
        chpasswd = {
          expire = false
          list   = "${var.cloud_init_username}:${var.cloud_init_password}"
        }
      } : {}
    )
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = var.vm_image_datastore
  node_name    = var.proxmox_node
  url          = var.ubuntu_image_url
  file_name    = var.ubuntu_image_file_name
  overwrite    = false
}

resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  for_each = local.nodes

  content_type = "snippets"
  datastore_id = var.cloud_init_snippets_datastore
  node_name    = var.proxmox_node
  overwrite    = true

  source_raw {
    data      = "#cloud-config\n${yamlencode(local.cloud_init_by_node[each.key])}"
    file_name = "${var.vm_name_prefix}-${each.key}-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "ubuntu" {
  for_each = local.nodes

  name        = each.value.name
  description = "Ubuntu node ${each.key} for ${var.cluster_name}"
  tags        = ["ubuntu", "linux", var.cluster_name]

  node_name = var.proxmox_node
  vm_id     = each.value.vm_id
  on_boot   = true

  cpu {
    cores = var.node_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.node_memory
  }

  agent {
    enabled = true
    timeout = "30m"
    trim    = false
    type    = "virtio"

    wait_for_ip {
      ipv4 = true
      ipv6 = false
    }
  }

  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    size         = var.node_disk_size
    discard      = "on"
    ssd          = true
  }

  initialization {
    datastore_id = var.cloud_init_datastore
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data[each.key].id

    ip_config {
      ipv4 {
        address = each.value.ipv4_address
        gateway = each.value.ipv4_gateway != "" ? each.value.ipv4_gateway : null
      }
    }

    dns {
      servers = var.dns_servers
    }
  }

  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  startup {
    order = each.value.startup
  }

  lifecycle {
    precondition {
      condition     = each.value.ipv4_address != "dhcp" || each.value.ipv4_gateway == ""
      error_message = "${each.key}: leave gateway empty when IPv4 address is set to dhcp."
    }
  }
}
