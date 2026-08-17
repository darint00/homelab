#!/bin/bash
# Install ArgoCD into Kubernetes using Helm
set -e

NAMESPACE="argocd"

kubectl create namespace "$NAMESPACE" || true

helm install argocd argo/argo-cd \
  --namespace $NAMESPACE 