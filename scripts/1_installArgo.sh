# Create the namespace
kubectl create namespace argocd

# Install the official manifests
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.8/manifests/install.yaml
