#!/bin/bash
# Install NGINX into Kubernetes using Helm
set -e

HELM_CHART_PATH="$(dirname "$0")/../helm"
NAMESPACE="nginx"

kubectl create namespace "$NAMESPACE" || true
helm install nginx "$HELM_CHART_PATH" -n "$NAMESPACE"
