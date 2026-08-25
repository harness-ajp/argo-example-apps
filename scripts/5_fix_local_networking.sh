kubectl patch networkpolicy argocd-redis-network-policy -n argocd --type=json -p='[
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

kubectl patch networkpolicy argocd-repo-server-network-policy -n argocd --type='strategic' -p='spec: {ingress: [{from: [{podSelector: {matchLabels: {app.kubernetes.io/name: harness-gitops-agent}}}], ports: [{port: 8081, protocol: TCP}]}]}'

kubectl patch networkpolicy argocd-repo-server-network-policy -n argocd --type=json -p='[{"op":"add","path":"/spec/ingress/0/from/-","value":{"podSelector":{"matchLabels":{"app.kubernetes.io/name":"argocd-application-controller"}}}}]'

kubectl patch networkpolicy argocd-repo-server-network-policy -n argocd --type=json -p='[{"op":"add","path":"/spec/ingress/0/from/-","value":{"podSelector":{"matchLabels":{"app.kubernetes.io/name":"argocd-server"}}}}]'
