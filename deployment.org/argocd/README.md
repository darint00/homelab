# ArgoCD Installation Guide

This guide provides step-by-step instructions for installing ArgoCD in your Kubernetes cluster using Helm.

## Prerequisites
- Kubernetes cluster access (kubectl configured)
- Helm installed

## Installation Steps

1. **Navigate to the ArgoCD deployment directory:**
   ```sh
   cd deployment/argocd
   ```

2. **Install ArgoCD using the provided script:**
   ```sh
   ./scripts/install-argocd.sh
   ```
   This script will deploy ArgoCD to your Kubernetes cluster using Helm.

3. **Verify the installation:**
   ```sh
   kubectl get pods -n argocd
   ```
   All ArgoCD pods should be in the `Running` or `Completed` state.

## Accessing the ArgoCD UI

1. **Port-forward the ArgoCD server service:**
   ```sh
   kubectl port-forward svc/argocd-server -n argocd 8080:80
   ```

2. **Open your browser and visit:**
   ```
   http://localhost:8080
   ```

## Uninstalling ArgoCD

To uninstall ArgoCD, run:
```sh
helm uninstall argocd -n argocd
```

---

**Note:** If you need to remove the namespace after uninstalling, run:
```sh
kubectl delete namespace argocd
```
