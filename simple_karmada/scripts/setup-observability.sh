#!/bin/bash
set -e

for cmd in kubectl helm; do
  command -v "$cmd" &>/dev/null || {
    echo "Missing: $cmd"
    exit 1
  }
done

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "Installing Central Observability (Grafana + Prometheus) on kubectl-host..."

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --kube-context kind-cluster-01 \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=a \
  --timeout 10m

echo "Done. To open Grafana:"
echo "kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "Then visit http://localhost:3000 — login: admin / a"
