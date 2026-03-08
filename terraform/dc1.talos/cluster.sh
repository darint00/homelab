#!/usr/bin/env bash
#
# cluster.sh — Manage an N-node Talos Kubernetes cluster on Proxmox.
#
# Usage:
#   ./cluster.sh --deploy [--nodes N]  # deploy cluster (optionally set node count)
#   ./cluster.sh --destroy             # tear down the cluster
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

tfvar() {
  # Extract a value from terraform.tfvars: tfvar <key>
  # Use ^[^=]*= (first = only) so values containing = (e.g. API tokens) are preserved
  grep "^${1}[[:space:]]*=" "$TFVARS" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | tr -d '"'
}

# ── Command dispatch ─────────────────────────

ACTION=""
REQUESTED_NODES=0

case "${1:-}" in
  --destroy) ACTION="destroy" ;;
  --deploy)
    ACTION="deploy"
    shift
    if [[ "${1:-}" == "--nodes" ]]; then
      [[ -z "${2:-}" ]] && err "--nodes requires a number"
      REQUESTED_NODES=$2
      shift 2
    fi
    ;;
  *) usage ;;
esac

# ══════════════════════════════════════════════
#  DESTROY
# ══════════════════════════════════════════════

if [[ "$ACTION" == "destroy" ]]; then

  CLUSTER_NAME=$(tfvar cluster_name)
  KUBECONFIG_FILE="$HOME/.kube/${CLUSTER_NAME}.yaml"

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
  sed -i 's/^bootstrap_endpoints.*/bootstrap_endpoints = {}/' "$TFVARS"
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

if [[ "$ACTION" == "deploy" ]]; then

  # ── Update node_count if --nodes was specified ─

  if [[ $REQUESTED_NODES -gt 0 ]]; then
    log "Setting node_count = $REQUESTED_NODES in $TFVARS"
    sed -i "s/^node_count.*/node_count = $REQUESTED_NODES/" "$TFVARS"
    ok "Updated $TFVARS"
  fi

  # ── Read config from tfvars ──────────────────

  PVE_ENDPOINT=$(tfvar proxmox_endpoint)
  PVE_TOKEN=$(tfvar proxmox_api_token)
  PVE_NODE=$(tfvar proxmox_node)
  PVE_HOST=$(echo "$PVE_ENDPOINT" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

  NODE_COUNT=$(tfvar node_count)
  BASE_VMID=$(tfvar base_vmid)
  BASE_IP=$(tfvar base_ip)
  CLUSTER_NAME=$(tfvar cluster_name)
  SUBNET=$(echo "$BASE_IP" | grep -oP '^\d+\.\d+\.\d+\.')
  KUBECONFIG_FILE="$HOME/.kube/${CLUSTER_NAME}.yaml"

  declare -a NODE_NAMES NODE_VMIDS
  for ((i=0; i<NODE_COUNT; i++)); do
    if [[ $i -eq 0 ]]; then
      NODE_NAMES[i]="cp1"
    else
      NODE_NAMES[i]="wk${i}"
    fi
    NODE_VMIDS[i]=$(( BASE_VMID + i ))
  done

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
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "terraform@${PVE_HOST}" \
      "ping -c2 -W1 -b ${SUBNET}255 2>/dev/null; \
       for i in \$(seq 128 200); do ping -c1 -W1 ${SUBNET}\$i >/dev/null 2>&1 & done; wait" \
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

  sed -i 's/^bootstrap_endpoints.*/bootstrap_endpoints = {}/' "$TFVARS"
  ok "Bootstrap endpoints cleared"

  # ── Step 2: Terraform init & validate ────────

  log "Step 2: Terraform init"
  terraform init -input=false

  log "Step 2: Terraform validate"
  terraform validate

  # ── Step 3: Create VMs (targeted apply) ──────

  log "Step 3: Creating $NODE_COUNT VM(s)"
  for ((j=0; j<NODE_COUNT; j++)); do
    echo "  ${NODE_NAMES[j]}  vmid=${NODE_VMIDS[j]}"
  done

  TARGET_ARGS="-target=proxmox_virtual_environment_download_file.talos_iso"
  for ((j=0; j<NODE_COUNT; j++)); do
    TARGET_ARGS+=" -target=proxmox_virtual_environment_vm.node[\"${NODE_NAMES[j]}\"]"
  done

  terraform plan -input=false $TARGET_ARGS -out=tfplan-vms
  terraform apply tfplan-vms
  rm -f tfplan-vms
  ok "VMs created"

  # ── Step 4: Poll until VMs are running ───────

  log "Step 4: Waiting for VMs to be running"

  for ((j=0; j<NODE_COUNT; j++)); do
    poll "VM ${NODE_VMIDS[j]} (${NODE_NAMES[j]}) running" 5 check_vm_running "${NODE_VMIDS[j]}"
    ok "VM ${NODE_VMIDS[j]} (${NODE_NAMES[j]}) is running"
  done

  # ── Step 5: Discover DHCP addresses ──────────

  log "Step 5: Discovering DHCP addresses (MAC → ARP → IP)"

  declare -A NODE_MACS NODE_DHCP
  dhcp_elapsed=0

  while true; do
    # Collect MACs for any nodes we don't have yet
    for ((j=0; j<NODE_COUNT; j++)); do
      name="${NODE_NAMES[j]}"
      vmid="${NODE_VMIDS[j]}"
      if [[ -z "${NODE_MACS[$name]:-}" ]]; then
        NODE_MACS[$name]=$(get_mac "$vmid")
      fi
    done

    # Refresh ARP table if we have any MACs (before resolving)
    any_mac=false
    for ((j=0; j<NODE_COUNT; j++)); do
      [[ -n "${NODE_MACS[${NODE_NAMES[j]}]:-}" ]] && any_mac=true
    done
    if $any_mac; then
      refresh_arp
    fi

    # Resolve MAC → IP for nodes still missing DHCP
    all_found=true
    for ((j=0; j<NODE_COUNT; j++)); do
      name="${NODE_NAMES[j]}"
      if [[ -n "${NODE_MACS[$name]:-}" && -z "${NODE_DHCP[$name]:-}" ]]; then
        NODE_DHCP[$name]=$(mac_to_ip "${NODE_MACS[$name]}")
      fi
      if [[ -z "${NODE_DHCP[$name]:-}" ]]; then
        all_found=false
      fi
    done

    if $all_found; then
      break
    fi

    printf '  Waiting for DHCP...'
    for ((j=0; j<NODE_COUNT; j++)); do
      name="${NODE_NAMES[j]}"
      printf ' %s=%s' "$name" "${NODE_DHCP[$name]:-pending}"
    done
    printf ' (%ds)\n' "$dhcp_elapsed"
    sleep 10
    dhcp_elapsed=$(( dhcp_elapsed + 10 ))
  done

  for ((j=0; j<NODE_COUNT; j++)); do
    name="${NODE_NAMES[j]}"
    ok "${name} (VMID ${NODE_VMIDS[j]})  MAC=${NODE_MACS[$name]}  DHCP=${NODE_DHCP[$name]}"
  done

  # ── Step 6: Poll until Talos API is reachable ─

  log "Step 6: Waiting for Talos API (port 50000) on DHCP addresses"

  for ((j=0; j<NODE_COUNT; j++)); do
    name="${NODE_NAMES[j]}"
    poll "Talos API on ${NODE_DHCP[$name]} (${name})" 10 check_talos_port "${NODE_DHCP[$name]}"
    ok "Talos API reachable on ${NODE_DHCP[$name]} (${name})"
  done

  # ── Step 7: Write DHCP endpoints into tfvars ─

  log "Step 7: Setting bootstrap endpoints in $TFVARS"

  ENDPOINTS_HCL="bootstrap_endpoints = {"
  for ((j=0; j<NODE_COUNT; j++)); do
    name="${NODE_NAMES[j]}"
    ENDPOINTS_HCL+=" \"$name\" = \"${NODE_DHCP[$name]}\","
  done
  ENDPOINTS_HCL+=" }"

  sed -i "s|^bootstrap_endpoints.*|${ENDPOINTS_HCL}|" "$TFVARS"
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

    if [[ "$READY_NODES" -ge "$NODE_COUNT" && "$TOTAL_NODES" -ge "$NODE_COUNT" ]]; then
      break
    fi

    printf '  Nodes Ready: %s/%s (%ds)\n' "$READY_NODES" "$NODE_COUNT" "$ready_elapsed"
    sleep 10
    ready_elapsed=$(( ready_elapsed + 10 ))
  done

  ok "All nodes Ready ($READY_NODES/$NODE_COUNT)"

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
  echo "  export KUBECONFIG=$KUBECONFIG_FILE"
  echo ""
fi
