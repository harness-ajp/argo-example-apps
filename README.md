# ArgoCD Setup on Local K8S
This README documents the end-to-end setup of ArgoCD on Docker Desktop, specifically configured to bypass "Short Read" errors, SSL inspection, and registry blocks encountered in restricted network environments.

# 🚀 ArgoCD Guestbook: Complete End-to-End Setup Guide

This guide documents the successful setup of ArgoCD and the Guestbook application on Docker Desktop. It includes the specific configurations required to bypass corporate firewall "Short Read" errors and registry blocks.

---

## 🛠 Phase 1: Cluster & Network Preparation

Before installing, ensure the Docker Desktop VM network is clear.

1. **Clear Registry Mirrors:** Open **Docker Desktop Settings** -> **Docker Engine**. Ensure `"registry-mirrors": []` is empty. Click **Apply & Restart**.
2. **Resource Check:** Ensure Kubernetes is enabled and has at least 4GB of RAM allocated.

---

## 🏗 Phase 2: Installing & Accessing ArgoCD

Run these commands to install the ArgoCD controller and its components.

```bash
# 1. Create the namespace
kubectl create namespace argocd

# 2. Apply the official manifests
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Port forward ArgoCD Server
kubectl port-forward svc/argocd-server -n argocd 8081:443

# 4. Secure Password for Argo
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

#5. Login to ArgoCD UI [https://localhost:8081](https://localhost:8081)

Login ID: admin
Passord: (See Step 4)


## 🏗 Phase 3: Deploying Applications

For this project there are two sample applications.  (a) Guestbook UI and (b) nginx 

```bash
# 1. Apply guestbook applications
kubectl apply -f my-guestbook.yaml

# 2. Apply nginx appliction
kubectl apply -f my-nginx.yaml
```

Go to the ArgoCD UI to see your application deployments.


