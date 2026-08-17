#!/usr/bin/env bash
#
# cluster.sh — Manage a 2-node Talos Kubernetes cluster on Proxmox.
#
# Usage:
#   ./cluster.sh --deploy   # full deploy from zero to working cluster
#   ./cluster.sh --destroy  # tear down the cluster and clean up
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TFVARS="terraform.tfvars"
KUBECONFIG_FILE="$HOME/.kube/dc1-talos-claude.yaml"

# ── Helpers ──────────────────────────────────

log()  { printf '\n\033[1;34m>>> %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[1;32m  ✔ %s\033[0m\n' "$*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  --deploy   Create VMs, apply Talos config, bootstrap cluster, extract kubeconfig
  --destroy  Tear down the cluster and clean up

Examples:
  ./$(basename "$0") --deploy
  ./$(basename "$0") --destroy
EOF
  exit 0
}

tfvar() {
  # Extract a value from terraform.tfvars: tfvar <key>
  # Use ^[^=]*= (first = only) so values containing = (e.g. API tokens) are preserved
  grep "^${1}[[:space:]]*=" "$TFVARS" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | tr -d '"'
}

# ── Command dispatch ─────────────────────────

ACTION="${1:-}"
case "$ACTION" in
  --destroy|--deploy) ;;
  *) usage ;;
esac

# ══════════════════════════════════════════════
#  DESTROY
# ══════════════════════════════════════════════

if [[ "$ACTION" == "--destroy" ]]; then

  # ── Step 1: Terraform init ──────────────────
  log "Step 1: Terraform init"
  terraform init -input=false
  ok "Initialized"

  # ── Step 2: Terraform destroy ───────────────
  log "Step 2: Destroying cluster"
  terraform destroy -auto-approve
  ok "All resources destroyed"

  # ── Step 3: Clear bootstrap endpoints ───────
  log "Step 3: Clearing bootstrap endpoints"
  sed -i 's/^\(controlplane_bootstrap_endpoint *= *\)".*"/\1""/' "$TFVARS"
  sed -i 's/^\(worker_bootstrap_endpoint *= *\)".*"/\1""/' "$TFVARS"
  ok "Bootstrap endpoints cleared"

  # ── Step 4: Remove kubeconfig ───────────────
  log "Step 4: Cleaning up kubeconfig"
  if [[ -f "$KUBECONFIG_FILE" ]]; then
    rm -f "$KUBECONFIG_FILE"
    ok "Removed $KUBECONFIG_FILE"
  else
    ok "No kubeconfig to remove"
  fi

  log "Cluster destroyed"
fi

# ══════════════════════════════════════════════
#  DEPLOY
# ══════════════════════════════════════════════

if [[ "$ACTION" == "--deploy" ]]; then

  # ── Read config from tfvars ──────────────────

  PVE_ENDPOINT=$(tfvar proxmox_endpoint)
  PVE_TOKEN=$(tfvar proxmox_api_token)
  PVE_NODE=$(tfvar proxmox_node)
  PVE_HOST=$(echo "$PVE_ENDPOINT" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
  CP_VMID=$(tfvar node1_vmid)
  WK_VMID=$(tfvar node2_vmid)

  # ── Proxmox / Talos helper functions ────────

  vm_status() {
    curl -sk --max-time 5 -H "Authorization: PVEAPIToken=${PVE_TOKEN}" \
      "${PVE_ENDPOINT}/api2/json/nodes/${PVE_NODE}/qemu/${1}/status/current" \
      | jq -r '.data.status // empty' 2>/dev/null || true
  }

  get_mac() {
    curl -sk --max-time 5 -H "Authorization: PVEAPIToken=${PVE_TOKEN}" \
      "${PVE_ENDPOINT}/api2/json/nodes/${PVE_NODE}/qemu/${1}/config" \
      | jq -r '.data.net0 // empty' | grep -oP '[0-9A-Fa-f:]{17}' | head -1 || true
  }

  mac_to_ip() {
    local mac_lower
    mac_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "terraform@${PVE_HOST}" \
      "ip neigh show" 2>/dev/null \
      | grep -i "$mac_lower" \
      | grep -oP '^\d+\.\d+\.\d+\.\d+' \
      | head -1 || true
  }

  refresh_arp() {
    local gw subnet
    gw=$(tfvar node_gateway)
    subnet=$(echo "$gw" | grep -oP '^\d+\.\d+\.\d+\.')
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "terraform@${PVE_HOST}" \
      "ping -c2 -W1 -b ${subnet}255 2>/dev/null; \
       for i in \$(seq 128 200); do ping -c1 -W1 ${subnet}\$i >/dev/null 2>&1 & done; wait" \
      2>/dev/null || true
  }

  poll() {
    local desc="$1" interval="$2"; shift 2
    local elapsed=0
    while true; do
      if "$@" >/dev/null 2>&1; then return 0; fi
      printf '  Waiting for %s ... (%ds)\n' "$desc" "$elapsed"
      sleep "$interval"
      elapsed=$(( elapsed + interval ))
    done
  }

  check_vm_running() { [[ "$(vm_status "$1")" == "running" ]]; }

  check_talos_port() {
    timeout 3 bash -c "echo >/dev/tcp/${1}/50000" 2>/dev/null
  }

  # ── Step 1: Clean up any existing cluster ────

  log "Step 1: Clean up any existing cluster"

  if [[ -f terraform.tfstate ]] && terraform state list 2>/dev/null | grep -q .; then
    terraform destroy -auto-approve || true
    ok "Existing resources destroyed"
  else
    ok "No existing terraform state"
  fi

  sed -i 's/^\(controlplane_bootstrap_endpoint *= *\)".*"/\1""/' "$TFVARS"
  sed -i 's/^\(worker_bootstrap_endpoint *= *\)".*"/\1""/' "$TFVARS"
  ok "Bootstrap endpoints cleared"

  # ── Step 2: Terraform init & validate ────────

  log "Step 2: Terraform init"
  terraform init -input=false

  log "Step 2: Terraform validate"
  terraform validate

  # ── Step 3: Create VMs (targeted apply) ──────

  log "Step 3: Creating VMs"
  terraform plan -input=false \
    -target=proxmox_virtual_environment_download_file.talos_iso \
    -target=proxmox_virtual_environment_vm.controlplane \
    -target=proxmox_virtual_environment_vm.worker \
    -out=tfplan-vms

  terraform apply tfplan-vms
  rm -f tfplan-vms
  ok "VMs created"

  # ── Step 4: Poll until VMs are running ───────

  log "Step 4: Waiting for VMs to be running"

  poll "VM ${CP_VMID} running" 5 check_vm_running "$CP_VMID"
  ok "VM ${CP_VMID} (controlplane) is running"

  poll "VM ${WK_VMID} running" 5 check_vm_running "$WK_VMID"
  ok "VM ${WK_VMID} (worker) is running"

  # ── Step 5: Discover DHCP addresses ──────────

  log "Step 5: Discovering DHCP addresses (MAC → ARP → IP)"

  CP_MAC="" WK_MAC=""
  CP_DHCP="" WK_DHCP=""
  dhcp_elapsed=0

  while true; do
    [[ -z "$CP_MAC" ]] && CP_MAC=$(get_mac "$CP_VMID")
    [[ -z "$WK_MAC" ]] && WK_MAC=$(get_mac "$WK_VMID")

    if [[ -n "$CP_MAC" || -n "$WK_MAC" ]]; then
      refresh_arp
    fi

    if [[ -n "$CP_MAC" && -z "$CP_DHCP" ]]; then
      CP_DHCP=$(mac_to_ip "$CP_MAC")
    fi
    if [[ -n "$WK_MAC" && -z "$WK_DHCP" ]]; then
      WK_DHCP=$(mac_to_ip "$WK_MAC")
    fi

    if [[ -n "$CP_DHCP" && -n "$WK_DHCP" ]]; then
      break
    fi

    echo "  Waiting for DHCP... CP_MAC=${CP_MAC:-pending} WK_MAC=${WK_MAC:-pending} CP=${CP_DHCP:-pending} WK=${WK_DHCP:-pending} (${dhcp_elapsed}s)"
    sleep 10
    dhcp_elapsed=$(( dhcp_elapsed + 10 ))
  done

  ok "Control-plane DHCP: $CP_DHCP  (MAC $CP_MAC)"
  ok "Worker DHCP:        $WK_DHCP  (MAC $WK_MAC)"

  # ── Step 6: Poll until Talos API is reachable ─

  log "Step 6: Waiting for Talos API (port 50000) on DHCP addresses"

  poll "Talos API on ${CP_DHCP}" 10 check_talos_port "$CP_DHCP"
  ok "Talos API reachable on ${CP_DHCP}"

  poll "Talos API on ${WK_DHCP}" 10 check_talos_port "$WK_DHCP"
  ok "Talos API reachable on ${WK_DHCP}"

  # ── Step 7: Write DHCP endpoints into tfvars ─

  log "Step 7: Setting bootstrap endpoints in $TFVARS"
  sed -i "s|^\(controlplane_bootstrap_endpoint *= *\)\".*\"|\1\"${CP_DHCP}\"|" "$TFVARS"
  sed -i "s|^\(worker_bootstrap_endpoint *= *\)\".*\"|\1\"${WK_DHCP}\"|" "$TFVARS"
  ok "Updated $TFVARS"

  # ── Step 8: Full terraform apply ─────────────

  log "Step 8: Terraform plan (full)"
  terraform plan -input=false -out=tfplan

  log "Step 8: Terraform apply (config → bootstrap → health → kubeconfig)"
  terraform apply tfplan
  rm -f tfplan
  ok "Terraform apply complete"

  # ── Step 9: Poll until nodes are Ready ───────

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

  # ── Step 10: Save kubeconfig ─────────────────

  log "Step 10: Saving kubeconfig"
  mkdir -p ~/.kube
  cp "$KUBECONFIG_TMP" "$KUBECONFIG_FILE"
  rm -f "$KUBECONFIG_TMP"

  export KUBECONFIG="$KUBECONFIG_FILE"
  cp "$KUBECONFIG_FILE" ~/.kube/config.dc1

  log "Cluster status"
  kubectl get nodes -o wide

  ok "Kubernetes cluster is ready!"
  echo ""
  echo "  export KUBECONFIG=~/.kube/dc1-talos-claude.yaml"
  echo ""
fi
