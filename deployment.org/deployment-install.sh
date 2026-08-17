#!/bin/bash
# Install all deployment components: nginx and argocd
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Install NGINX
# echo "Installing NGINX..."
# bash "$SCRIPT_DIR/nginx/scripts/install-nginx.sh"


# Install ArgoCD
echo "Installing ArgoCD..."
bash "$SCRIPT_DIR/argocd/scripts/install-argocd.sh"

# Apply ArgoCD Application for Headlamp
echo "Configuring ArgoCD to deploy Headlamp..."
kubectl apply -f "$SCRIPT_DIR/argocd/headlamp-application.yaml" -n argocd

# Apply ArgoCD Application for NGINX
echo "Configuring ArgoCD to deploy NGINX..."
kubectl apply -f "$SCRIPT_DIR/argocd/nginx-application.yaml" -n argocd

echo "Deployment complete."
