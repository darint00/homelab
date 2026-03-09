
locals {
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
}

locals {
  node1_cloud_init = merge({
    hostname       = var.node1_name
    package_update = true
    package_upgrade = false
    packages       = ["qemu-guest-agent", "curl", "open-iscsi", "nfs-common"]
    users          = local.cloud_init_users
    runcmd         = [
      "systemctl enable --now qemu-guest-agent",
      "systemctl enable --now iscsid"
    ]
  }, var.cloud_init_password != "" ? {
    chpasswd = {
      expire = false
      list   = "${var.cloud_init_username}:${var.cloud_init_password}"
    }
  } : {})
  node2_cloud_init = merge({
    hostname       = var.node2_name
    package_update = true
    package_upgrade = false
    packages       = ["qemu-guest-agent", "curl", "open-iscsi", "nfs-common"]
    users          = local.cloud_init_users
    runcmd         = [
      "systemctl enable --now qemu-guest-agent",
      "systemctl enable --now iscsid"
    ]
  }, var.cloud_init_password != "" ? {
    chpasswd = {
      expire = false
      list   = "${var.cloud_init_username}:${var.cloud_init_password}"
    }
  } : {})
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = var.vm_image_datastore
  node_name    = var.proxmox_node
  url          = var.ubuntu_image_url
  file_name    = var.ubuntu_image_file_name
  overwrite    = false
}


resource "proxmox_virtual_environment_file" "cloud_init_user_data_node1" {
  content_type = "snippets"
  datastore_id = var.cloud_init_snippets_datastore
  node_name    = var.proxmox_node
  overwrite    = true

  source_raw {
    data      = "#cloud-config\n${yamlencode(local.node1_cloud_init)}"
    file_name = "${var.vm_name_prefix}-node1-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_user_data_node2" {
  content_type = "snippets"
  datastore_id = var.cloud_init_snippets_datastore
  node_name    = var.proxmox_node
  overwrite    = true

  source_raw {
    data      = "#cloud-config\n${yamlencode(local.node2_cloud_init)}"
    file_name = "${var.vm_name_prefix}-node2-cloud-config.yaml"
  }
}


resource "proxmox_virtual_environment_vm" "node1" {
  name        = var.node1_name
  description = "k3s server node (node1) for ${var.cluster_name}"
  tags        = ["ubuntu", "linux", "k3s", var.cluster_name, "server"]

  node_name = var.proxmox_node
  vm_id     = var.node1_vmid
  on_boot   = true

  cpu {
    cores = var.node1_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.node1_memory
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
    size         = var.node1_disk_size
    discard      = "on"
    ssd          = true
  }

  initialization {
    datastore_id = var.cloud_init_datastore
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data_node1.id

    ip_config {
      ipv4 {
        address = var.node1_ipv4_address
        gateway = var.node1_ipv4_gateway != "" ? var.node1_ipv4_gateway : null
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
    order = var.node1_startup
  }

  lifecycle {
    precondition {
      condition     = var.node1_ipv4_address != "dhcp" || var.node1_ipv4_gateway == ""
      error_message = "node1: leave gateway empty when IPv4 address is set to dhcp."
    }
  }
}

resource "proxmox_virtual_environment_vm" "node2" {
  name        = var.node2_name
  description = "k3s agent node (node2) for ${var.cluster_name}"
  tags        = ["ubuntu", "linux", "k3s", var.cluster_name, "agent"]

  node_name = var.proxmox_node
  vm_id     = var.node2_vmid
  on_boot   = true

  cpu {
    cores = var.node2_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.node2_memory
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
    size         = var.node2_disk_size
    discard      = "on"
    ssd          = true
  }

  initialization {
    datastore_id = var.cloud_init_datastore
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data_node2.id

    ip_config {
      ipv4 {
        address = var.node2_ipv4_address
        gateway = var.node2_ipv4_gateway != "" ? var.node2_ipv4_gateway : null
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
    order = var.node2_startup
  }

  lifecycle {
    precondition {
      condition     = var.node2_ipv4_address != "dhcp" || var.node2_ipv4_gateway == ""
      error_message = "node2: leave gateway empty when IPv4 address is set to dhcp."
    }
  }
}
