# dc1 — Talos Kubernetes Cluster on Proxmox

Provisions a 2-node Talos Linux Kubernetes cluster on a Proxmox VE host using Terraform.

## Architecture

```
Proxmox VE Host
├── dc1-cp-01     (VM 300)  Control Plane  — runs etcd, API server, scheduler, controller-manager
│   └── VIP: cluster_vip   :6443           — floating IP for the API endpoint
└── dc1-worker-01 (VM 301)  Worker         — runs workloads
```

Both nodes boot from the Talos metal ISO, which is automatically downloaded from GitHub into
Proxmox storage. Talos installs itself to disk on first boot, then the ISO is ignored on
subsequent reboots.

## Client Machine Setup

These tools must be installed on your laptop before running any commands in this guide.

### Terraform

**macOS (Homebrew)**
```bash
brew install terraform
terraform -version
```

**Linux (Debian / Ubuntu)**
```bash
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
terraform -version
```

**Linux (manual binary)**
```bash
# Replace 1.9.0 with the latest version from https://releases.hashicorp.com/terraform/
TERRAFORM_VERSION=1.9.0
curl -LO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform -version
```

---

### talosctl

The `talosctl` version should match the `talos_version` variable in your `terraform.tfvars`
(default `v1.9.3`).

**macOS (manual binary — Apple Silicon)**
```bash
TALOS_VERSION=v1.9.3
curl -LO "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-darwin-arm64"
chmod +x talosctl-darwin-arm64
sudo mv talosctl-darwin-arm64 /usr/local/bin/talosctl
talosctl version --client
```

**macOS (manual binary — Intel)**
```bash
TALOS_VERSION=v1.9.3
curl -LO "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-darwin-amd64"
chmod +x talosctl-darwin-amd64
sudo mv talosctl-darwin-amd64 /usr/local/bin/talosctl
talosctl version --client
```

**Linux (install script — installs latest)**
```bash
curl -sL https://talos.dev/install | sh
talosctl version --client
```

**Linux (specific version)**
```bash
TALOS_VERSION=v1.9.3
curl -LO "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-amd64"
chmod +x talosctl-linux-amd64
sudo mv talosctl-linux-amd64 /usr/local/bin/talosctl
talosctl version --client
```

---

### kubectl

**macOS (Homebrew)**
```bash
brew install kubectl
kubectl version --client
```

**Linux (apt)**
```bash
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubectl
kubectl version --client
```

**Linux (manual binary)**
```bash
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

---

### Verify all tools are installed

```bash
terraform -version
talosctl version --client
kubectl version --client
```

---

## Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Terraform | >= 1.5.0 | https://developer.hashicorp.com/terraform/install |
| talosctl | matches `talos_version` var | https://github.com/siderolabs/talos/releases |
| kubectl | any recent | https://kubernetes.io/docs/tasks/tools/ |

### Proxmox API Token

Terraform authenticates to Proxmox via an API token. Create one with the required privileges:

1. Log in to the Proxmox web UI as `root` (or an admin user).

2. Create a dedicated user:
   ```
   Datacenter → Permissions → Users → Add
   User: terraform@pam
   ```

3. Create an API token for that user:
   ```
   Datacenter → Permissions → API Tokens → Add
   User:       terraform@pam
   Token ID:   terraform
   Privilege Separation: unchecked
   ```
   Copy the displayed secret — it is shown only once.

4. Grant the token the required permissions on `/`:
   ```
   Datacenter → Permissions → Add → API Token Permission
   Path:  /
   Token: terraform@pam!terraform
   Role:  PVEVMAdmin   (or a custom role — see below)
   ```

   Minimum required privileges for a custom role:

   | Privilege | Required For |
   |-----------|-------------|
   | `VM.Allocate` | Creating VMs |
   | `VM.Config.CDROM` | Attaching ISO |
   | `VM.Config.CPU` | Setting CPU |
   | `VM.Config.Disk` | Adding disks |
   | `VM.Config.Memory` | Setting RAM |
   | `VM.Config.Network` | Adding NICs |
   | `VM.Config.Options` | Boot order, tags |
   | `VM.PowerMgmt` | Starting VMs |
   | `Datastore.AllocateSpace` | Creating disk images |
   | `Datastore.AllocateTemplate` | Uploading ISO |
   | `Datastore.Audit` | Reading storage info |
   | `SDN.Use` | Network bridge access |
   | `Sys.Modify` | Node-level operations |

### SSH Agent

The `bpg/proxmox` provider uses SSH for file operations (ISO upload). Ensure your SSH key is
loaded and can reach the Proxmox host:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519          # or whichever key has access to your Proxmox host
ssh root@<proxmox-host>            # verify connectivity before running terraform
```

### Network Planning

Before running, choose and note four IP addresses in the same subnet:

| Address | Used For |
|---------|----------|
| Proxmox host IP | Already exists |
| `cluster_vip` | Floats to the active control plane — **must not be assigned to any host** |
| `controlplane_ip` | Static IP of the control plane VM |
| `worker_ip` | Static IP of the worker VM |

## File Structure

```
dc1/
├── providers.tf              # bpg/proxmox and siderolabs/talos provider config
├── variables.tf              # All input variable declarations with descriptions
├── main.tf                   # ISO download, VM creation, Talos config + bootstrap
├── outputs.tf                # kubeconfig, talosconfig, IPs, cluster endpoint
├── terraform.tfvars.example  # Template — copy to terraform.tfvars and edit
└── README.md                 # This file
```

## Step-by-Step Setup

### 1. Copy and edit the variables file

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your environment values. The fields you **must** change:

| Variable | Description |
|----------|-------------|
| `proxmox_endpoint` | URL of your Proxmox API, e.g. `https://192.168.1.10:8006` |
| `proxmox_api_token` | Token created above: `terraform@pam!terraform=<secret>` |
| `proxmox_node` | Name of the Proxmox node, shown in the web UI (often `pve`) |
| `cluster_vip` | Free IP for the floating API endpoint |
| `controlplane_ip` | Static IP for the control plane VM |
| `worker_ip` | Static IP for the worker VM |
| `gateway` | Your network gateway |

The remaining variables have sensible defaults and can be left as-is or adjusted to match your
storage layout, VM IDs, and sizing requirements.

> **Never commit `terraform.tfvars`** — it contains your API token. It is already excluded by
> `../.gitignore`.

### 2. Initialise Terraform

```bash
terraform init
```

This downloads the `bpg/proxmox` (~0.67) and `siderolabs/talos` (~0.7) providers.

### 3. Preview the plan

```bash
terraform plan
```

Review the output. Terraform will create:
- 1 ISO download resource (Talos metal image)
- 2 Proxmox VMs (`dc1-cp-01`, `dc1-worker-01`)
- Talos machine secrets (PKI, tokens, encryption keys)
- Talos machine configurations for each node
- Talos config apply for each node
- 1 bootstrap resource (initialises etcd)
- 1 cluster health check (waits for ready state)
- 1 kubeconfig data source

### 4. Apply

```bash
terraform apply
```

Type `yes` when prompted. The apply proceeds in order:

1. Downloads the Talos ISO into Proxmox storage
2. Creates both VMs and starts them — they boot into the Talos installer
3. Generates cluster secrets and machine configurations
4. Pushes configuration to each node via the Talos API (port 50000)
5. Bootstraps etcd on the control plane (runs once)
6. Waits for both nodes to report healthy
7. Retrieves the kubeconfig

Total time is typically 5–10 minutes depending on ISO download speed and hardware.

### 5. Save credentials

Both outputs are marked `sensitive`. Retrieve them explicitly:

```bash
# Kubernetes credentials
terraform output -raw kubeconfig > ~/.kube/dc1.kubeconfig

# Talos management credentials
terraform output -raw talosconfig > ~/.talos/dc1config
```

Set environment variables for your shell session:

```bash
export KUBECONFIG=~/.kube/dc1.kubeconfig
export TALOSCONFIG=~/.talos/dc1config
```

### 6. Verify the cluster

```bash
# Check nodes are Ready
kubectl get nodes -o wide

# Expected output:
# NAME               STATUS   ROLES           AGE   VERSION
# dc1-cp-01          Ready    control-plane   Xm    v1.x.x
# dc1-worker-01      Ready    <none>          Xm    v1.x.x

# Check all system pods are running
kubectl get pods -A

# Verify via talosctl
talosctl --nodes <controlplane_ip> health
talosctl --nodes <controlplane_ip> version
```

## Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `proxmox_endpoint` | — | Proxmox API URL |
| `proxmox_api_token` | — | API token (sensitive) |
| `proxmox_insecure` | `true` | Skip TLS verification |
| `proxmox_ssh_user` | `root` | SSH user for Proxmox host |
| `proxmox_node` | `pve` | Proxmox node name |
| `talos_version` | `v1.9.3` | Talos release to deploy |
| `cluster_name` | `dc1` | Cluster and hostname prefix |
| `cluster_vip` | — | Floating control plane IP |
| `controlplane_ip` | — | Control plane static IP |
| `controlplane_cidr` | `24` | Control plane subnet prefix |
| `worker_ip` | — | Worker static IP |
| `worker_cidr` | `24` | Worker subnet prefix |
| `gateway` | — | Default gateway |
| `dns_servers` | `["1.1.1.1","8.8.8.8"]` | DNS servers |
| `vm_network_bridge` | `vmbr0` | Proxmox bridge |
| `vm_datastore` | `local-lvm` | Datastore for VM disks |
| `vm_iso_datastore` | `local` | Datastore for ISO |
| `controlplane_vmid` | `300` | Proxmox VM ID |
| `worker_vmid` | `301` | Proxmox VM ID |
| `controlplane_cpu_cores` | `2` | vCPUs |
| `controlplane_memory` | `4096` | RAM in MB |
| `controlplane_disk_size` | `50` | Root disk in GB |
| `worker_cpu_cores` | `2` | vCPUs |
| `worker_memory` | `4096` | RAM in MB |
| `worker_disk_size` | `50` | Root disk in GB |

## Outputs Reference

| Output | Sensitive | Description |
|--------|-----------|-------------|
| `kubeconfig` | yes | Raw kubeconfig for `kubectl` |
| `talosconfig` | yes | Talos client config for `talosctl` |
| `controlplane_ip` | no | Control plane node IP |
| `worker_ip` | no | Worker node IP |
| `cluster_endpoint` | no | `https://<vip>:6443` |
| `cluster_name` | no | Cluster name |

## Useful Day-2 Commands

```bash
# List all Talos services on the control plane
talosctl --nodes <controlplane_ip> services

# Stream logs from a service
talosctl --nodes <controlplane_ip> logs kubelet

# Upgrade Talos on a node (update talos_version in tfvars, then):
talosctl --nodes <node_ip> upgrade --image ghcr.io/siderolabs/installer:<new_version>

# Upgrade Kubernetes
talosctl --nodes <controlplane_ip> upgrade-k8s --to <k8s_version>

# Reset a node (wipes disk — use with caution)
talosctl --nodes <node_ip> reset
```

## Teardown

```bash
terraform destroy
```

This removes both VMs and the downloaded ISO from Proxmox. The Talos secrets stored in
Terraform state are also destroyed — back up `terraform.tfstate` if you need to recover the
cluster credentials later.
