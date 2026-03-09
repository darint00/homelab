# dc1.ubuntu - Two Ubuntu VMs on Proxmox

Terraform module to provision two Ubuntu cloud-image nodes on Proxmox.

## What it creates

- 1 Ubuntu cloud image import file in Proxmox datastore
- 2 VMs:
  - `${vm_name_prefix}-01` (VMID `node1_vmid`)
  - `${vm_name_prefix}-02` (VMID `node2_vmid`)
- Cloud-init configuration for user access and networking

## Files

- `providers.tf` - Terraform and provider setup
- `variables.tf` - all configurable inputs
- `main.tf` - image download and VM resources
- `outputs.tf` - VM IDs and names
- `terraform.tfvars.example` - sample values

## Usage

```bash
cd terraform/dc1.ubuntu
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars (token, ssh key, and any IP settings)

terraform init -input=false
terraform validate
terraform plan -input=false -out=tfplan
terraform apply tfplan
```

## Notes

- Defaults use DHCP for both nodes (`node1_ipv4_address = "dhcp"`, `node2_ipv4_address = "dhcp"`).
- If using static IPs, set each address as CIDR (for example `192.168.86.210/24`) and set matching gateway.
- Cloud-init installs and enables `qemu-guest-agent` on both nodes, and Terraform enables the Proxmox agent to report VM IP addresses.
- Ensure snippets are enabled on the datastore set by `cloud_init_snippets_datastore` (default `local`) in Proxmox (`Datacenter -> Storage -> <datastore> -> Edit -> Content -> Snippets`).
- Keep `terraform.tfvars` out of git.
