kubectl patch networkpolicy argocd-redis-network-policy -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/ingress/0/from/-",
    "value": {
      "podSelector": {
        "matchLabels": {
          "app.kubernetes.io/name": "harness-gitops-agent"
        }
      }
    }
  }
]'
