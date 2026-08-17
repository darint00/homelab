# Deployment Overview

This directory contains resources for deploying key services into your Kubernetes cluster:

## Structure

- `nginx/`: Helm chart and scripts to install NGINX as a web server or ingress controller.
- `argocd/`: Helm chart and scripts to install ArgoCD for GitOps-based application management.

## What will be deployed

1. **NGINX**
   - Deployed via Helm chart.
   - Can be used as a basic web server or as an ingress controller for routing traffic.
   - Includes installation scripts for easy setup.

2. **ArgoCD**
   - Deployed via Helm chart.
   - Provides GitOps continuous delivery for Kubernetes.
   - Includes installation scripts for automated setup.

Each subfolder contains:
- Helm chart (with values.yaml and templates)
- Installation scripts
- Additional documentation as needed

---

Follow the instructions in each subfolder to deploy the respective service into your Kubernetes cluster.