#!/usr/bin/env bash
#
# stop.sh — Destroy the k3s Ubuntu cluster and clean up all resources.
#
# Usage:
#   ./stop.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TFVARS="terraform.tfvars"
CLUSTER_NAME=$(grep '^cluster_name' "$TFVARS" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | tr -d '"')
KUBECONFIG_FILE="$HOME/.kube/${CLUSTER_NAME}.yaml"

log()  { printf '\n\033[1;34m>>> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✔ %s\033[0m\n' "$*"; }

# ── Step 1: Terraform init ───────────────
log "Step 1: Terraform init"
terraform init -input=false
ok "Initialized"

# ── Step 2: Terraform destroy ────────────
log "Step 2: Destroying cluster"
terraform destroy -auto-approve
ok "All resources destroyed"

# ── Step 3: Remove kubeconfig ────────────
log "Step 3: Cleaning up kubeconfig"
if [[ -f "$KUBECONFIG_FILE" ]]; then
  rm -f "$KUBECONFIG_FILE"
  ok "Removed $KUBECONFIG_FILE"
else
  ok "No kubeconfig to remove"
fi

log "Cluster destroyed"
