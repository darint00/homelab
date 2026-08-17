# dc1.talos.claude – Two-Node Talos Cluster on Proxmox

Terraform module to provision a Talos Linux control-plane + worker on Proxmox
and bootstrap a Kubernetes cluster with static IPv4 addresses.

## What it creates

| Resource | Name | VMID | Static IP |
|---|---|---|---|
| Control-plane VM | `dc1-talos-cp` | 320 | `192.168.86.130` |
| Worker VM | `dc1-talos-wk` | 321 | `192.168.86.131` |

Plus: Talos ISO, machine secrets, machine configs (with static IPs and `dhcp: false`),
config apply, bootstrap, health check, and kubeconfig output.

## Key design choices

- **Static IPs with `dhcp: false`** — the machine config patches explicitly disable
  DHCP and assign static addresses using `deviceSelector` (no hardcoded interface name).
- **Bootstrap endpoint override** — Talos VMs first boot with DHCP from the ISO.
  Config apply must target the DHCP address.  Set `controlplane_bootstrap_endpoint`
  and `worker_bootstrap_endpoint` to those temporary addresses.  After config apply,
  Talos reboots with the static IP.  Bootstrap/health/kubeconfig then target the
  static IP directly.

## Deploy workflow (two-step)

### Step 1 – Create VMs only

```bash
cd terraform/dc1.talos.claude
terraform init
terraform apply -target=proxmox_virtual_environment_vm.controlplane \
                -target=proxmox_virtual_environment_vm.worker
```

### Step 2 – Discover DHCP addresses

Wait ~30 seconds for VMs to boot and obtain DHCP, then query Proxmox:

```bash
TOKEN="terraform@pve!terraform=<your-token>"
curl -sk -H "Authorization: PVEAPIToken=$TOKEN" \
  "https://192.168.86.240:8006/api2/json/nodes/pve/qemu" \
  | jq -r '.data[] | select(.vmid==320 or .vmid==321) | "\(.vmid) \(.name)"'
```

Or scan the DHCP range:

```bash
for ip in $(seq 180 199); do
  ping -c1 -W1 192.168.86.$ip &>/dev/null && echo "192.168.86.$ip UP"
done
```

Check Talos maintenance mode on discovered IPs:

```bash
talosctl -n 192.168.86.X version --insecure
```

### Step 3 – Set bootstrap endpoints and apply

Edit `terraform.tfvars`:

```hcl
controlplane_bootstrap_endpoint = "192.168.86.X"   # DHCP address of VMID 320
worker_bootstrap_endpoint       = "192.168.86.Y"   # DHCP address of VMID 321
```

Then apply the full config:

```bash
terraform apply
```

This sends machine configs, bootstraps the cluster, waits for health,
and retrieves the kubeconfig.

### Step 4 – Extract kubeconfig

```bash
terraform output -raw kubeconfig > ~/.kube/dc1-talos.yaml
export KUBECONFIG=~/.kube/dc1-talos.yaml
kubectl get nodes
```

## Files

| File | Purpose |
|---|---|
| `providers.tf` | Terraform and provider declarations |
| `variables.tf` | Configurable inputs |
| `main.tf` | VMs, Talos config, apply, bootstrap, health, kubeconfig |
| `outputs.tf` | Cluster info, IPs, kubeconfig, talosconfig |
| `terraform.tfvars` | Active values (gitignored) |
| `terraform.tfvars.example` | Template |

## Cleanup

```bash
terraform destroy -auto-approve
```
