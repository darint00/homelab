
locals {
  cloud_init_users = [
    "default",
    {
      name                = var.cloud_init_username
      groups              = "sudo"
      shell               = "/bin/bash"
      sudo                = "ALL=(ALL) NOPASSWD:ALL"
      ssh_authorized_keys = var.cloud_init_ssh_public_keys
    }
  ]

	nodes_map = {
		for i in range(var.node_count) :
			"node${i+1}" => {
				name    = "node${i+1}"
				role    = (i == 0 ? "server" : "agent")
				   ip      = "${split(".", var.base_ip)[0]}.${split(".", var.base_ip)[1]}.${split(".", var.base_ip)[2]}.${tonumber(split(".", var.base_ip)[3]) + i}/24"
				vmid    = var.base_vmid + i
			}
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
	for_each     = local.nodes_map
	content_type = "snippets"
	datastore_id = var.cloud_init_snippets_datastore
	node_name    = var.proxmox_node
	overwrite    = true

	source_raw {
		data      = "#cloud-config\n${yamlencode(merge({
			hostname        = each.value.name
			package_update  = true
			package_upgrade = false
			packages        = ["qemu-guest-agent", "curl", "open-iscsi", "nfs-common"]
			users           = local.cloud_init_users
			runcmd          = [
				"systemctl enable --now qemu-guest-agent",
				"systemctl enable --now iscsid"
			]
		}, var.cloud_init_password != "" ? {
			chpasswd = {
				expire = false
				list   = "${var.cloud_init_username}:${var.cloud_init_password}"
			}
		} : {}))}"
		file_name = "${var.vm_name_prefix}-${each.value.name}-cloud-config.yaml"
	}
}



resource "proxmox_virtual_environment_vm" "node" {
	for_each    = local.nodes_map
	name        = "${var.vm_name_prefix}-${each.value.name}"
	description = "k3s ${each.value.role} node (${each.value.name}) for ${var.cluster_name}"
	tags        = ["ubuntu", "linux", "k3s", var.cluster_name, each.value.role]

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
		import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
		size         = var.node_disk_size
		discard      = "on"
		ssd          = true
	}

	initialization {
		datastore_id      = var.cloud_init_datastore
		user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data[each.key].id

		ip_config {
			ipv4 {
				address = each.value.ip
				gateway = null
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
		order = each.value.role == "server" ? "1" : "2"
	}
}
