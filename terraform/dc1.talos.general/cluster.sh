#!/usr/bin/env bash
#
# cluster.sh — Manage an N-node Talos Kubernetes cluster on Proxmox.
#
# Usage:
#   ./cluster.sh --deploy [--nodes N]  # deploy cluster (optionally set node count)
#   ./cluster.sh --destroy              # tear down the cluster
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TFVARS="terraform.tfvars"

# ── Helpers ──────────────────────────────────

log()  { printf '\n\033[1;34m>>> %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[1;32m  ✔ %s\033[0m\n' "$*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  --deploy [--nodes N]   Deploy the cluster. Optionally set node count
                         (1 controlplane + N-1 workers).
  --destroy              Tear down the cluster and clean up.

Examples:
  ./$(basename "$0") --deploy              # deploy using node_count in terraform.tfvars
  ./$(basename "$0") --deploy --nodes 3    # set node_count=3, then deploy
  ./$(basename "$0") --destroy
EOF
  exit 0
}

# ── Proxmox helpers ──────────────────────────
tfvar() {
  # Use ^[^=]*= (first = only) so values containing = (e.g. API tokens) are preserved
  grep "^${1}[[:space:]]*=" "$TFVARS" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | tr -d '"'
}

get_mac() {
  # get_mac <vmid> → MAC address from Proxmox API
  curl -sk -H "Authorization: PVEAPIToken=${PVE_TOKEN}" \
    "${PVE_ENDPOINT}/api2/json/nodes/${PVE_NODE}/qemu/${1}/config" \
    | jq -r '.data.net0' | grep -oP '[0-9A-Fa-f:]{17}' | head -1
}

mac_to_ip() {
  # mac_to_ip <mac> → IPv4 from Proxmox ip-neigh
  local mac_lower
  mac_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  ssh "terraform@${PVE_HOST}" "ip neigh show" 2>/dev/null \
    | grep -i "$mac_lower" \
    | grep -oP '^\d+\.\d+\.\d+\.\d+' \
    | head -1
}

# ── Command dispatch ─────────────────────────

REQUESTED_NODES=0

case "${1:-}" in
  --destroy)
    log "Destroying cluster"
    terraform destroy -auto-approve
    # Clear bootstrap_endpoints
    sed -i 's/^bootstrap_endpoints.*/bootstrap_endpoints = {}/' "$TFVARS"
    ok "Cluster destroyed and bootstrap endpoints cleared"
    exit 0
    ;;
  --deploy)
    shift
    if [[ "${1:-}" == "--nodes" ]]; then
      [[ -z "${2:-}" ]] && err "--nodes requires a number"
      REQUESTED_NODES=$2
      shift 2
    fi
    ;;
  *)
    usage
    ;;
esac

# ── Update node_count if --nodes was specified ─

if [[ $REQUESTED_NODES -gt 0 ]]; then
  log "Setting node_count = $REQUESTED_NODES in $TFVARS"
  sed -i "s/^node_count.*/node_count = $REQUESTED_NODES/" "$TFVARS"
  # Reset bootstrap_endpoints for a clean deploy
  sed -i 's/^bootstrap_endpoints.*/bootstrap_endpoints = {}/' "$TFVARS"
  ok "Updated $TFVARS"
fi

# ── Read config ──────────────────────────────

PVE_ENDPOINT=$(tfvar proxmox_endpoint)
PVE_TOKEN=$(tfvar proxmox_api_token)
PVE_NODE=$(tfvar proxmox_node)
PVE_HOST=$(echo "$PVE_ENDPOINT" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

NODE_COUNT=$(tfvar node_count)
BASE_VMID=$(tfvar base_vmid)

# Compute node names and VMIDs (mirrors terraform locals)
declare -a NODE_NAMES NODE_VMIDS
for ((i=0; i<NODE_COUNT; i++)); do
  if [[ $i -eq 0 ]]; then
    NODE_NAMES[i]="cp1"
  else
    NODE_NAMES[i]="wk${i}"
  fi
  NODE_VMIDS[i]=$(( BASE_VMID + i ))
done

log "Deploying $NODE_COUNT node(s)"
for ((j=0; j<NODE_COUNT; j++)); do
  echo "  ${NODE_NAMES[j]}  vmid=${NODE_VMIDS[j]}"
done

# ── Step 0: Init & Validate ─────────────────

log "Terraform init"
terraform init -input=false

log "Terraform validate"
terraform validate

# ── Step 1: Create VMs only ──────────────────

log "Creating VMs (step 1 of 2)"

TARGET_ARGS="-target=proxmox_virtual_environment_download_file.talos_iso"
for ((j=0; j<NODE_COUNT; j++)); do
  TARGET_ARGS+=" -target=proxmox_virtual_environment_vm.node[\"${NODE_NAMES[j]}\"]"
done

terraform plan -input=false $TARGET_ARGS -out=tfplan-vms
terraform apply tfplan-vms
rm -f tfplan-vms
ok "VMs created"

# ── Step 2: Discover DHCP addresses ──────────

log "Waiting 45s for VMs to boot and obtain DHCP leases"
sleep 45

log "Discovering DHCP addresses via Proxmox ARP table"

declare -A DHCP_MAP
for ((j=0; j<NODE_COUNT; j++)); do
  mac=$(get_mac "${NODE_VMIDS[j]}")
  dhcp=$(mac_to_ip "$mac")
  [[ -z "$dhcp" ]] && err "Could not find DHCP address for ${NODE_NAMES[j]} (VMID ${NODE_VMIDS[j]}, MAC $mac)"
  DHCP_MAP["${NODE_NAMES[j]}"]="$dhcp"
  ok "${NODE_NAMES[j]} (VMID ${NODE_VMIDS[j]}) MAC=$mac  DHCP=$dhcp"
done

# ── Step 3: Update tfvars with bootstrap endpoints ─

log "Setting bootstrap endpoints in $TFVARS"

# Build the HCL map literal: { "cp1" = "1.2.3.4", "wk1" = "1.2.3.5" }
ENDPOINTS_HCL="bootstrap_endpoints = {"
for key in "${!DHCP_MAP[@]}"; do
  ENDPOINTS_HCL+=" \"$key\" = \"${DHCP_MAP[$key]}\","
done
ENDPOINTS_HCL+=" }"

sed -i "s|^bootstrap_endpoints.*|${ENDPOINTS_HCL}|" "$TFVARS"
ok "Updated $TFVARS"

# ── Step 4: Full apply ───────────────────────

log "Terraform plan (full)"
terraform plan -input=false -out=tfplan

log "Terraform apply (config apply → bootstrap → health → kubeconfig)"
terraform apply tfplan
rm -f tfplan
ok "Cluster deployed"

# ── Step 5: Extract kubeconfig ───────────────

CLUSTER_NAME=$(tfvar cluster_name)
KUBECONFIG_FILE=~/.kube/${CLUSTER_NAME}.yaml

log "Extracting kubeconfig"
mkdir -p ~/.kube
terraform output -raw kubeconfig > "$KUBECONFIG_FILE"
export KUBECONFIG="$KUBECONFIG_FILE"

# ── Step 6: Wait for all nodes to be Ready ───

log "Waiting for all $NODE_COUNT node(s) to reach Ready state"
MAX_WAIT=300
INTERVAL=10
elapsed=0
while true; do
  # Count nodes that are truly Ready (exclude NotReady)
  ready_count=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {n++} END {print n+0}')
  total_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  echo "  ${ready_count}/${NODE_COUNT} nodes Ready, ${total_count} registered  (${elapsed}s elapsed)"
  if [[ $ready_count -ge $NODE_COUNT ]]; then
    break
  fi
  if [[ $elapsed -ge $MAX_WAIT ]]; then
    echo "  Current node status:"
    kubectl get nodes 2>/dev/null || true
    err "Timed out after ${MAX_WAIT}s waiting for nodes to be Ready (${ready_count}/${NODE_COUNT})"
  fi
  sleep $INTERVAL
  elapsed=$(( elapsed + INTERVAL ))
done

log "Verifying cluster"
kubectl get nodes -o wide

ok "Kubernetes cluster is ready"
echo ""
echo "  export KUBECONFIG=$KUBECONFIG_FILE"
echo ""
cp "$KUBECONFIG_FILE" ~/.kube/config.dc1
ok "Kubeconfig copied to ~/.kube/config.dc1"
