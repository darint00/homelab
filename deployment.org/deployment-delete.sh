#!/bin/bash
# Delete all deployment components: nginx and argocd, and remove their namespaces
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Delete ArgoCD
if kubectl get ns argocd &>/dev/null; then
  echo "Deleting ArgoCD..."
  helm uninstall argocd -n argocd || true
  kubectl delete namespace argocd || true
else
  echo "Namespace argocd does not exist. Skipping."
fi

# Delete NGINX
if kubectl get ns nginx &>/dev/null; then
  echo "Deleting NGINX..."
  helm uninstall nginx -n nginx || true
  kubectl delete namespace nginx || true
else
  echo "Namespace nginx does not exist. Skipping."
fi

echo "Deletion complete."
