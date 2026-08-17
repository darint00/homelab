#!/usr/bin/env bash
#
# stop.sh — Standalone destroy of the dc1-talos-claude 2-node Talos Kubernetes cluster.
#
# Performs:
#   1. Terraform init (if needed)
#   2. Terraform destroy (all resources)
#   3. Clear bootstrap endpoints in terraform.tfvars
#   4. Remove kubeconfig
#
# Usage:
#   ./stop.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TFVARS="terraform.tfvars"
KUBECONFIG_FILE="$HOME/.kube/dc1-talos-claude.yaml"

# ── Helpers ──────────────────────────────────

log()  { printf '\n\033[1;34m>>> %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '  \033[0;32m✔ %s\033[0m\n' "$*"; }

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
