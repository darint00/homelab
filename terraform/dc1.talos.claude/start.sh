#!/usr/bin/env bash
#
# start.sh — Standalone deploy of the dc1-talos-claude 2-node Talos Kubernetes cluster.
#
# Performs every step from zero to a working cluster:
#   1. Destroy any existing cluster
#   2. Terraform init & validate
#   3. Create VMs (targeted apply)
#   4. Poll until VMs are running
#   5. Discover DHCP addresses (MAC → ARP → IP)
#   6. Poll until Talos API is reachable on DHCP IPs
#   7. Write DHCP endpoints into terraform.tfvars
#   8. Full terraform apply (config apply → bootstrap → health → kubeconfig)
#   9. Poll until all Kubernetes nodes are Ready
#  10. Copy kubeconfig to ~/.kube/dc1-talos-claude.yaml
#
# Usage:
#   ./start.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TFVARS="terraform.tfvars"

# ── Helpers ──────────────────────────────────

log()  { printf '\n\033[1;34m>>> %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[1;32m  ✔ %s\033[0m\n' "$*"; }

tfvar() {
  # Extract a value from terraform.tfvars.
  # Uses ^[^=]*= so values containing = (e.g. API tokens) are preserved.
  grep "^${1}[[:space:]]*=" "$TFVARS" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | tr -d '"'
}

# ── Read config from tfvars ──────────────────

PVE_ENDPOINT=$(tfvar proxmox_endpoint)
PVE_TOKEN=$(tfvar proxmox_api_token)
PVE_NODE=$(tfvar proxmox_node)
PVE_HOST=$(echo "$PVE_ENDPOINT" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
CP_VMID=$(tfvar node1_vmid)
WK_VMID=$(tfvar node2_vmid)

# ── Proxmox / Talos helper functions ────────

vm_status() {
  # vm_status <vmid> → "running", "stopped", etc.
  curl -sk --max-time 5 -H "Authorization: PVEAPIToken=${PVE_TOKEN}" \
    "${PVE_ENDPOINT}/api2/json/nodes/${PVE_NODE}/qemu/${1}/status/current" \
    | jq -r '.data.status // empty' 2>/dev/null || true
}

get_mac() {
  # get_mac <vmid> → MAC address from Proxmox VM config
  curl -sk --max-time 5 -H "Authorization: PVEAPIToken=${PVE_TOKEN}" \
    "${PVE_ENDPOINT}/api2/json/nodes/${PVE_NODE}/qemu/${1}/config" \
    | jq -r '.data.net0 // empty' | grep -oP '[0-9A-Fa-f:]{17}' | head -1 || true
}

mac_to_ip() {
  # mac_to_ip <mac> → IPv4 from Proxmox host ARP table
  local mac_lower
  mac_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "terraform@${PVE_HOST}" \
    "ip neigh show" 2>/dev/null \
    | grep -i "$mac_lower" \
    | grep -oP '^\d+\.\d+\.\d+\.\d+' \
    | head -1 || true
}

refresh_arp() {
  # Ping-sweep from Proxmox host to populate ARP table for recently-booted VMs.
  local gw subnet
  gw=$(tfvar node_gateway)
  subnet=$(echo "$gw" | grep -oP '^\d+\.\d+\.\d+\.')
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "terraform@${PVE_HOST}" \
    "ping -c2 -W1 -b ${subnet}255 2>/dev/null; \
     for i in \$(seq 128 200); do ping -c1 -W1 ${subnet}\$i >/dev/null 2>&1 & done; wait" \
    2>/dev/null || true
}

poll() {
  # poll <description> <interval_sec> <check_cmd...>
  # Polls check_cmd until it succeeds (exit 0). Waits indefinitely.
  local desc="$1" interval="$2"; shift 2
  local elapsed=0
  while true; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    printf '  Waiting for %s ... (%ds)\n' "$desc" "$elapsed"
    sleep "$interval"
    elapsed=$(( elapsed + interval ))
  done
}

check_vm_running() { [[ "$(vm_status "$1")" == "running" ]]; }

check_talos_port() {
  # TCP connect to Talos gRPC port 50000. talosctl version --insecure returns
  # non-zero in maintenance mode, so we check the port directly.
  timeout 3 bash -c "echo >/dev/tcp/${1}/50000" 2>/dev/null
}

# ══════════════════════════════════════════════
# STEP 1: Destroy any existing cluster
# ══════════════════════════════════════════════

log "Step 1: Clean up any existing cluster"

if [[ -f terraform.tfstate ]] && terraform state list 2>/dev/null | grep -q .; then
  terraform destroy -auto-approve || true
  ok "Existing resources destroyed"
else
  ok "No existing terraform state"
fi

# Clear bootstrap endpoints so the first targeted apply doesn't try to
# reach stale DHCP addresses.
sed -i 's/^\(controlplane_bootstrap_endpoint *= *\)".*"/\1""/' "$TFVARS"
sed -i 's/^\(worker_bootstrap_endpoint *= *\)".*"/\1""/' "$TFVARS"
ok "Bootstrap endpoints cleared"

# ══════════════════════════════════════════════
# STEP 2: Terraform init & validate
# ══════════════════════════════════════════════

log "Step 2: Terraform init"
terraform init -input=false

log "Step 2: Terraform validate"
terraform validate

# ══════════════════════════════════════════════
# STEP 3: Create VMs (targeted apply)
# ══════════════════════════════════════════════

log "Step 3: Creating VMs"
terraform plan -input=false \
  -target=proxmox_virtual_environment_download_file.talos_iso \
  -target=proxmox_virtual_environment_vm.controlplane \
  -target=proxmox_virtual_environment_vm.worker \
  -out=tfplan-vms

terraform apply tfplan-vms
rm -f tfplan-vms
ok "VMs created"

# ══════════════════════════════════════════════
# STEP 4: Poll until VMs are running
# ══════════════════════════════════════════════

log "Step 4: Waiting for VMs to be running"

poll "VM ${CP_VMID} running" 5 check_vm_running "$CP_VMID"
ok "VM ${CP_VMID} (controlplane) is running"

poll "VM ${WK_VMID} running" 5 check_vm_running "$WK_VMID"
ok "VM ${WK_VMID} (worker) is running"

# ══════════════════════════════════════════════
# STEP 5: Discover DHCP addresses
# ══════════════════════════════════════════════

log "Step 5: Discovering DHCP addresses (MAC → ARP → IP)"

CP_MAC="" WK_MAC=""
CP_DHCP="" WK_DHCP=""
dhcp_elapsed=0

while true; do
  # Get MACs from Proxmox API
  [[ -z "$CP_MAC" ]] && CP_MAC=$(get_mac "$CP_VMID")
  [[ -z "$WK_MAC" ]] && WK_MAC=$(get_mac "$WK_VMID")

  # Force ARP table refresh on Proxmox so ip neigh has entries
  if [[ -n "$CP_MAC" || -n "$WK_MAC" ]]; then
    refresh_arp
  fi

  # Resolve MACs to IPs via ARP table
  if [[ -n "$CP_MAC" && -z "$CP_DHCP" ]]; then
    CP_DHCP=$(mac_to_ip "$CP_MAC")
  fi
  if [[ -n "$WK_MAC" && -z "$WK_DHCP" ]]; then
    WK_DHCP=$(mac_to_ip "$WK_MAC")
  fi

  # Both found → done
  if [[ -n "$CP_DHCP" && -n "$WK_DHCP" ]]; then
    break
  fi

  echo "  Waiting for DHCP... CP_MAC=${CP_MAC:-pending} WK_MAC=${WK_MAC:-pending} CP=${CP_DHCP:-pending} WK=${WK_DHCP:-pending} (${dhcp_elapsed}s)"
  sleep 10
  dhcp_elapsed=$(( dhcp_elapsed + 10 ))
done

ok "Control-plane DHCP: $CP_DHCP  (MAC $CP_MAC)"
ok "Worker DHCP:        $WK_DHCP  (MAC $WK_MAC)"

# ══════════════════════════════════════════════
# STEP 6: Poll until Talos API is reachable
# ══════════════════════════════════════════════

log "Step 6: Waiting for Talos API (port 50000) on DHCP addresses"

poll "Talos API on ${CP_DHCP}" 10 check_talos_port "$CP_DHCP"
ok "Talos API reachable on ${CP_DHCP}"

poll "Talos API on ${WK_DHCP}" 10 check_talos_port "$WK_DHCP"
ok "Talos API reachable on ${WK_DHCP}"

# ══════════════════════════════════════════════
# STEP 7: Write DHCP endpoints into tfvars
# ══════════════════════════════════════════════

log "Step 7: Setting bootstrap endpoints in $TFVARS"
sed -i "s|^\(controlplane_bootstrap_endpoint *= *\)\".*\"|\1\"${CP_DHCP}\"|" "$TFVARS"
sed -i "s|^\(worker_bootstrap_endpoint *= *\)\".*\"|\1\"${WK_DHCP}\"|" "$TFVARS"
ok "Updated $TFVARS"

# ══════════════════════════════════════════════
# STEP 8: Full terraform apply
# ══════════════════════════════════════════════
# This creates: talos_machine_secrets, machine config apply (both nodes),
# bootstrap, cluster health check, and kubeconfig.

log "Step 8: Terraform plan (full)"
terraform plan -input=false -out=tfplan

log "Step 8: Terraform apply (config → bootstrap → health → kubeconfig)"
terraform apply tfplan
rm -f tfplan
ok "Terraform apply complete"

# ══════════════════════════════════════════════
# STEP 9: Poll until all Kubernetes nodes are Ready
# ══════════════════════════════════════════════

log "Step 9: Waiting for Kubernetes nodes to be Ready"
KUBECONFIG_TMP=$(mktemp)
terraform output -raw kubeconfig > "$KUBECONFIG_TMP"

ready_elapsed=0
while true; do
  TOTAL_NODES=$(KUBECONFIG="$KUBECONFIG_TMP" kubectl get nodes --no-headers 2>/dev/null | wc -l)
  READY_NODES=$(KUBECONFIG="$KUBECONFIG_TMP" kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l)

  if [[ "$READY_NODES" -ge 2 && "$TOTAL_NODES" -ge 2 ]]; then
    break
  fi

  printf '  Nodes Ready: %s/%s (%ds)\n' "$READY_NODES" "$TOTAL_NODES" "$ready_elapsed"
  sleep 10
  ready_elapsed=$(( ready_elapsed + 10 ))
done

ok "All nodes Ready ($READY_NODES/$TOTAL_NODES)"

# ══════════════════════════════════════════════
# STEP 10: Copy kubeconfig
# ══════════════════════════════════════════════

log "Step 10: Saving kubeconfig"
mkdir -p ~/.kube
cp "$KUBECONFIG_TMP" ~/.kube/dc1-talos-claude.yaml
rm -f "$KUBECONFIG_TMP"

export KUBECONFIG=~/.kube/dc1-talos-claude.yaml
cp ~/.kube/dc1-talos-claude.yaml ~/.kube/config.dc1

log "Cluster status"
kubectl get nodes -o wide

ok "Kubernetes cluster is ready!"
echo ""
echo "  export KUBECONFIG=~/.kube/dc1-talos-claude.yaml"
echo ""


