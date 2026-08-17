#!/bin/bash
# Install Headlamp into Kubernetes using the official Helm chart
set -e

NAMESPACE="headlamp"
RELEASE_NAME="headlamp"
CHART_REPO="https://headlamp-k8s.github.io/headlamp/"
CHART_NAME="headlamp/headlamp"

# Add the Headlamp Helm repo if not already present
if ! helm repo list | grep -q "headlamp"; then
  helm repo add headlamp "$CHART_REPO"
fi
helm repo update

# Create namespace if it doesn't exist
kubectl create namespace "$NAMESPACE" || true

# Install or upgrade Headlamp
helm upgrade --install "$RELEASE_NAME" "$CHART_NAME" -n "$NAMESPACE"

echo "Headlamp installation complete."
