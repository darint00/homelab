#!/usr/bin/env bash
#
# cluster.sh — Manage the dc1 3-node Talos Kubernetes cluster on Proxmox.
#
# Nodes: dc1-node1 (controlplane), dc1-node2 (worker), dc1-node3 (worker)
#
# Usage:
#   ./cluster.sh --deploy [--nodes N]   deploy the cluster
#   ./cluster.sh --destroy              tear down the cluster and remove all VMs
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
  --deploy [--nodes N]   Deploy the cluster. Optionally override node count
                         (node1 = controlplane, node2..N = workers, default 3).
  --destroy              Tear down the cluster and remove all VMs from Proxmox.

Examples:
  ./$(basename "$0") --deploy
  ./$(basename "$0") --deploy --nodes 4
  ./$(basename "$0") --destroy
EOF
  exit 0
}

tfvar() {
  # Preserves values containing '=' (e.g. API tokens)
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

  # Read PVE info before Terraform runs — needed for API-level VM cleanup
  PVE_ENDPOINT=$(tfvar proxmox_endpoint)
  PVE_TOKEN=$(tfvar proxmox_api_token)
  PVE_NODE=$(tfvar proxmox_node)
  BASE_VMID=$(tfvar base_vmid)
  NODE_COUNT=$(tfvar node_count)
  CLUSTER_NAME=$(tfvar cluster_name)
  KUBECONFIG_FILE="$HOME/.kube/${CLUSTER_NAME}.yaml"

  vm_status() {
    curl -sk --max-time 5 -H "Authorization: PVEAPIToken=${PVE_TOKEN}" \
      "${PVE_ENDPOINT}/api2/json/nodes/${PVE_NODE}/qemu/${1}/status/current" \
      | jq -r '.data.status // empty' 2>/dev/null || true
  }

  # Hard-stops, unlocks, and deletes a VM via the Proxmox API including its disks.
  # Polls until Proxmox confirms the VM is fully gone (no longer visible in the GUI).
  force_remove_vm() {
    local vmid="$1"
    local status
    status=$(vm_status "$vmid")

    if [[ -z "$status" ]]; then
      ok "VM $vmid not present"
      return 0
    fi

    printf '  VM %d present (%s)\n' "$vmid" "$status"

    # Hard power-off (Talos has no guest agent so ACPI shutdown won't work)
    if [[ "$status" == "running" ]]; then
      printf '  Stopping VM %d...\n' "$vmid"
      curl -sk -X POST -H "Authorization: PVEAPIToken=${PVE_TOKEN}" \
        "${PVE_ENDPOINT}/api2/json/nodes/${PVE_NODE}/qemu/${vmid}/status/stop" \
        >/dev/null 2>&1 || true

      local waited=0
      while [[ "$(vm_status "$vmid")" == "running" && $waited -lt 60 ]]; do
        sleep 3; waited=$(( waited + 3 ))
      done
      ok "VM $vmid stopped"
    fi

    # Remove any lock left by a failed Terraform run so the DELETE isn't rejected
    curl -sk -X PUT \
      -H "Authorization: PVEAPIToken=${PVE_TOKEN}" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "delete=lock" \
      "${PVE_ENDPOINT}/api2/json/nodes/${PVE_NODE}/qemu/${vmid}/config" \
      >/dev/null 2>&1 || true

    # Delete the VM; purge removes it from pool/HA; destroy-unreferenced-disks removes orphaned disk images
    printf '  Deleting VM %d...\n' "$vmid"
    curl -sk -X DELETE -H "Authorization: PVEAPIToken=${PVE_TOKEN}" \
      "${PVE_ENDPOINT}/api2/json/nodes/${PVE_NODE}/qemu/${vmid}?destroy-unreferenced-disks=1&purge=1" \
      >/dev/null 2>&1 || true

    # Poll until Proxmox confirms the VM is fully gone (deletion is an async task)
    local del_waited=0
    while [[ -n "$(vm_status "$vmid")" && $del_waited -lt 60 ]]; do
      sleep 3; del_waited=$(( del_waited + 3 ))
    done

    if [[ -n "$(vm_status "$vmid")" ]]; then
      printf '  \033[1;33mWARNING: VM %d still appears in Proxmox — manual removal may be needed\033[0m\n' "$vmid"
    else
      ok "VM $vmid removed from Proxmox"
    fi
  }

  # ── Step 1: Terraform init ──────────────────
  log "Step 1: Terraform init"
  terraform init -input=false
  ok "Initialized"

  # ── Step 2: Terraform destroy ───────────────
  log "Step 2: Destroying cluster via Terraform"
  # '|| true' so we always continue to the API-level cleanup below
  terraform destroy -auto-approve || true
  ok "Terraform destroy complete"

  # ── Step 3: Verify VMs are gone from Proxmox ─
  log "Step 3: Verifying all VMs are removed from Proxmox"
  for ((j=0; j<NODE_COUNT; j++)); do
    vmid=$(( BASE_VMID + j ))
    force_remove_vm "$vmid"
  done

  # ── Step 4: Clear bootstrap endpoints ───────
  log "Step 4: Clearing bootstrap endpoints"
  sed -i 's/^bootstrap_endpoints.*/bootstrap_endpoints = {}/' "$TFVARS"
  ok "Bootstrap endpoints cleared"

  # ── Step 5: Remove kubeconfig ───────────────
  log "Step 5: Cleaning up kubeconfig"
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
    NODE_NAMES[i]="node$((i + 1))"
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

  # ── Step 4: Start VMs if provider left them stopped ─
  # bpg/proxmox may create VMs without starting them; the DHCP poll in Step 5
  # is the real gate for "VM is alive on the network".

  log "Step 4: Ensuring VMs are started"

  for ((j=0; j<NODE_COUNT; j++)); do
    vmid="${NODE_VMIDS[j]}"
    name="${NODE_NAMES[j]}"
    current_status=$(vm_status "$vmid")

    case "$current_status" in
      running|prelaunch)
        ok "VM ${vmid} (${name}) is ${current_status}" ;;
      stopped)
        printf '  VM %d (%s) is stopped — sending start command\n' "$vmid" "$name"
        curl -sk -X POST -H "Authorization: PVEAPIToken=${PVE_TOKEN}" \
          "${PVE_ENDPOINT}/api2/json/nodes/${PVE_NODE}/qemu/${vmid}/status/start" \
          >/dev/null 2>&1 || true
        ok "VM ${vmid} (${name}) start command sent" ;;
      *)
        printf '  VM %d (%s) status: %s — continuing\n' "$vmid" "$name" "${current_status:-unknown}" ;;
    esac
  done

  # Brief pause so VMs can transition out of prelaunch before DHCP polling begins
  sleep 5

  # ── Step 5: Discover DHCP addresses ──────────

  log "Step 5: Discovering DHCP addresses (MAC → ARP → IP)"

  declare -A NODE_MACS NODE_DHCP
  dhcp_elapsed=0

  while true; do
    for ((j=0; j<NODE_COUNT; j++)); do
      name="${NODE_NAMES[j]}"
      vmid="${NODE_VMIDS[j]}"
      if [[ -z "${NODE_MACS[$name]:-}" ]]; then
        NODE_MACS[$name]=$(get_mac "$vmid")
      fi
    done

    any_mac=false
    for ((j=0; j<NODE_COUNT; j++)); do
      [[ -n "${NODE_MACS[${NODE_NAMES[j]}]:-}" ]] && any_mac=true
    done
    if $any_mac; then
      refresh_arp
    fi

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
