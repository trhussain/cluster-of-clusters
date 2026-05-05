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
  --kube-context kind-host-01 \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=a \
  --timeout 10m

helm upgrade --install prometheus-node-exporter prometheus-community/prometheus-node-exporter \
  --kube-context kind-cluster-01 \
  --namespace monitoring \
  --create-namespace \
  --set service.type=NodePort 

helm upgrade --install prometheus-node-exporter prometheus-community/prometheus-node-exporter \
  --kube-context kind-cluster-02 \
  --namespace monitoring \
  --create-namespace \
  --set service.type=NodePort 

# get worker node IPs and ports
CLUSTER01_IP=$(docker inspect cluster-01-control-plane --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
CLUSTER02_IP=$(docker inspect cluster-02-control-plane --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

CLUSTER01_PORT=$(kubectl --context kind-cluster-01 -n monitoring get svc prometheus-node-exporter -o jsonpath='{.spec.ports[0].nodePort}')
CLUSTER02_PORT=$(kubectl --context kind-cluster-02 -n monitoring get svc prometheus-node-exporter -o jsonpath='{.spec.ports[0].nodePort}')

echo "cluster-01 node-exporter: $CLUSTER01_IP:$CLUSTER01_PORT"
echo "cluster-02 node-exporter: $CLUSTER02_IP:$CLUSTER02_PORT"

# tell host-01 prometheus to scrape them
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --kube-context kind-host-01 \
  --namespace monitoring \
  --reuse-values \
  --set-json "prometheus.prometheusSpec.additionalScrapeConfigs=[
    {\"job_name\":\"cluster-01-nodes\",\"static_configs\":[{\"targets\":[\"$CLUSTER01_IP:$CLUSTER01_PORT\"]}]},
    {\"job_name\":\"cluster-02-nodes\",\"static_configs\":[{\"targets\":[\"$CLUSTER02_IP:$CLUSTER02_PORT\"]}]}
  ]"

  
echo "Done. To open Grafana:"
echo "kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "Then visit http://localhost:3000 — login: admin / a"
