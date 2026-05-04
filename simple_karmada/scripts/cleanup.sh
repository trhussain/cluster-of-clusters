#!/bin/bash

set -e

kind delete clusters --all 2>/dev/null || true

pkill -f "kubectl port-forward" 2>/dev/null || true
pkill -f "kubectl proxy" 2>/dev/null || true
pkill -f "helm" 2>/dev/null || true

rm -rf $HOME/.karmada

kubectl config get-contexts -o name | grep -E "kind-|karmada" | xargs -I {} kubectl config delete-context {} 2>/dev/null || true
kubectl config get-clusters | grep -E "kind-|karmada" | xargs -I {} kubectl config delete-cluster {} 2>/dev/null || true
kubectl config get-users | grep -E "kind-|karmada" | xargs -I {} kubectl config delete-user {} 2>/dev/null || true

echo "Done."