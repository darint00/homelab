# dc1.talos.general — N-Node Talos Cluster on Proxmox

Terraform module that deploys a variable-size [Talos](https://www.talos.dev/) Kubernetes cluster on Proxmox VE.

## Quick start

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set Proxmox credentials, node list, IPs, VMIDs
chmod +x cluster.sh
./cluster.sh --deploy
```

## Node configuration

Add or remove entries in the `nodes` list in `terraform.tfvars`:

```hcl
nodes = [
  { name = "cp1", role = "controlplane", ip = "192.168.86.130", vmid = 320, bootstrap_endpoint = "" },
  { name = "cp2", role = "controlplane", ip = "192.168.86.132", vmid = 322, bootstrap_endpoint = "" },
  { name = "wk1", role = "worker",       ip = "192.168.86.131", vmid = 321, bootstrap_endpoint = "" },
  { name = "wk2", role = "worker",       ip = "192.168.86.133", vmid = 323, bootstrap_endpoint = "" },
]
```

- At least one `controlplane` node is required.
- `bootstrap_endpoint` is auto-populated by `cluster.sh` during deploy (leave empty).

## Deploy / Destroy

```bash
./cluster.sh --deploy    # create VMs → discover DHCP → apply Talos config → bootstrap → kubeconfig
./cluster.sh --destroy   # terraform destroy + clear bootstrap endpoints
```

## Providers

| Provider | Version |
|----------|---------|
| bpg/proxmox | ~> 0.98 |
| siderolabs/talos | ~> 0.10 |
