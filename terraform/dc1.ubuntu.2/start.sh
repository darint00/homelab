#!/usr/bin/env bash
#
# start.sh — Deploy a k3s Kubernetes cluster on Ubuntu VMs via Proxmox/Terraform.
#
# Usage:
#   ./start.sh
#
# Steps:
#   1. Clean up any existing resources
#   2. Terraform init & validate
#   3. Terraform apply (create VMs, wait for cloud-init)
#   4. Get VM IPs from terraform output
#   5. Wait for SSH access
#   6. Install k3s server on node1
#   7. Wait for k3s server API (port 6443)
#   8. Get k3s join token from node1
#   9. Install k3s agent on node2
#  10. Wait for all Kubernetes nodes to be Ready
#  11. Save kubeconfig
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
  grep "^${1}[[:space:]]*=" "$TFVARS" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | tr -d '"'
}

SSH_USER=$(tfvar cloud_init_username)
CLUSTER_NAME=$(tfvar cluster_name)
KUBECONFIG_FILE="$HOME/.kube/${CLUSTER_NAME}.yaml"

ssh_cmd() {
  # ssh_cmd <ip> <command...>
  local ip="$1"; shift
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR "${SSH_USER}@${ip}" "$@"
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

# ── Step 1: Clean up any existing resources ────

log "Step 1: Clean up any existing resources"

if [[ -f terraform.tfstate ]] && terraform state list 2>/dev/null | grep -q .; then
  terraform destroy -auto-approve || true
  ok "Existing resources destroyed"
else
  ok "No existing terraform state"
fi

# ── Step 2: Terraform init & validate ────────

log "Step 2: Terraform init"
terraform init -input=false

log "Step 2: Terraform validate"
terraform validate
ok "Initialized and validated"

# ── Step 3: Terraform apply ──────────────────

log "Step 3: Terraform apply (creating VMs, waiting for cloud-init)"
terraform plan -input=false -out=tfplan
terraform apply tfplan
rm -f tfplan
ok "VMs created and running"

# ── Step 4: Get VM IPs ──────────────────────

log "Step 4: Getting VM IP addresses"

NODE1_IP=$(terraform output -raw node1_ip)
NODE2_IP=$(terraform output -raw node2_ip)

[[ "$NODE1_IP" == "unknown" || -z "$NODE1_IP" ]] && err "Could not determine node1 IP"
[[ "$NODE2_IP" == "unknown" || -z "$NODE2_IP" ]] && err "Could not determine node2 IP"

ok "node1 (server): $NODE1_IP"
ok "node2 (agent):  $NODE2_IP"

# ── Step 5: Wait for SSH access ──────────────

log "Step 5: Waiting for SSH access"

check_ssh() { ssh_cmd "$1" "echo ok"; }

poll "SSH on $NODE1_IP (node1)" 5 check_ssh "$NODE1_IP"
ok "SSH ready on $NODE1_IP (node1)"

poll "SSH on $NODE2_IP (node2)" 5 check_ssh "$NODE2_IP"
ok "SSH ready on $NODE2_IP (node2)"

# ── Step 6: Install k3s server on node1 ─────

log "Step 6: Installing k3s server on node1 ($NODE1_IP)"

ssh_cmd "$NODE1_IP" \
  "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --tls-san ${NODE1_IP} --write-kubeconfig-mode 644' sh -"

ok "k3s server installed on node1"

# ── Step 7: Wait for k3s server API ─────────

log "Step 7: Waiting for k3s server API (port 6443)"

check_k3s_api() {
  timeout 3 bash -c "echo >/dev/tcp/${1}/6443" 2>/dev/null
}

poll "k3s API on $NODE1_IP" 5 check_k3s_api "$NODE1_IP"
ok "k3s API reachable on $NODE1_IP:6443"

# ── Step 8: Get join token from node1 ────────

log "Step 8: Getting k3s join token"

K3S_TOKEN=""
token_elapsed=0
while [[ -z "$K3S_TOKEN" ]]; do
  K3S_TOKEN=$(ssh_cmd "$NODE1_IP" "sudo cat /var/lib/rancher/k3s/server/node-token 2>/dev/null" || true)
  if [[ -z "$K3S_TOKEN" ]]; then
    printf '  Waiting for join token ... (%ds)\n' "$token_elapsed"
    sleep 5
    token_elapsed=$(( token_elapsed + 5 ))
  fi
done

ok "Join token retrieved"

# ── Step 9: Install k3s agent on node2 ──────

log "Step 9: Installing k3s agent on node2 ($NODE2_IP)"

ssh_cmd "$NODE2_IP" \
  "curl -sfL https://get.k3s.io | K3S_URL='https://${NODE1_IP}:6443' K3S_TOKEN='${K3S_TOKEN}' sh -"

ok "k3s agent installed on node2"

# ── Step 10: Wait for all nodes Ready ───────

log "Step 10: Waiting for Kubernetes nodes to be Ready"

ready_elapsed=0
while true; do
  NODE_STATUS=$(ssh_cmd "$NODE1_IP" "kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes --no-headers 2>/dev/null" || true)
  TOTAL_NODES=$(echo "$NODE_STATUS" | grep -c . || true)
  READY_NODES=$(echo "$NODE_STATUS" | awk '$2 == "Ready"' | wc -l || true)

  if [[ "$READY_NODES" -ge 2 && "$TOTAL_NODES" -ge 2 ]]; then
    break
  fi

  printf '  Nodes Ready: %s/%s (%ds)\n' "$READY_NODES" "2" "$ready_elapsed"
  sleep 10
  ready_elapsed=$(( ready_elapsed + 10 ))
done

ok "All nodes Ready ($READY_NODES/2)"

# ── Step 11: Save kubeconfig ────────────────

log "Step 11: Saving kubeconfig"

mkdir -p ~/.kube
ssh_cmd "$NODE1_IP" "cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s|https://127.0.0.1:6443|https://${NODE1_IP}:6443|g" \
  > "$KUBECONFIG_FILE"

export KUBECONFIG="$KUBECONFIG_FILE"
cp "$KUBECONFIG_FILE" ~/.kube/config.dc1

log "Cluster status"
kubectl get nodes -o wide

ok "k3s cluster is ready!"
echo ""
echo "  export KUBECONFIG=$KUBECONFIG_FILE"
echo ""
