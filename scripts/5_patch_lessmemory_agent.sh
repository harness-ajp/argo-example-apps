kubectl patch deployment gitops-agent -n argocd --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "200m"}]'
