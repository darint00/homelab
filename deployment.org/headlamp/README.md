# Headlamp Installation Guide

This guide provides instructions for installing Headlamp and accessing its web UI via port forwarding.

## Prerequisites
- Kubernetes cluster access (kubectl configured)
- Helm installed

## Installation Steps

1. **Navigate to the Headlamp deployment directory:**
   ```sh
   cd deployment/headlamp
   ```

2. **Install Headlamp using the provided script:**
   ```sh
   ./scripts/install-headlamp.sh
   ```
   This script will deploy Headlamp to your Kubernetes cluster using Helm.

## Accessing Headlamp UI

After installation, Headlamp runs as a Kubernetes service. To access the web UI locally, use `kubectl port-forward`:


1. **Find the Headlamp service name and namespace:**
   - By default, Headlamp is installed in the `headlamp` namespace with the service name `headlamp`.

2. **Run port-forward:**
   ```sh
   kubectl port-forward -n headlamp svc/headlamp 8080:80
   ```
   This command forwards port 8080 on your local machine to port 80 of the Headlamp service in the `headlamp` namespace.

3. **Open your browser and visit:**
   ```
   http://localhost:8080
   ```

You should now see the Headlamp web UI.

## Generating a Token for Authentication

To log in to Headlamp, you may need a Kubernetes user token. Here’s how to generate a token for a service account:

1. **Create a service account (if you don’t have one):**
   ```sh
   kubectl create serviceaccount headlamp-user -n headlamp
   ```

2. **Bind the service account to a cluster role (e.g., cluster-admin for full access):**
   ```sh
   kubectl create clusterrolebinding headlamp-user-binding \
     --clusterrole=cluster-admin \
     --serviceaccount=headlamp:headlamp-user
   ```

3. **Get the token for the service account:**
   ```sh
   kubectl -n headlamp create token headlamp-user
   ```
   Copy the output token and use it to log in to Headlamp.

---

**Note:** If you installed Headlamp in a different namespace or with a different service name, adjust the `kubectl port-forward` command accordingly.
