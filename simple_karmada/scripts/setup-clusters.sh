#!/bin/bash
# basic cluster of clusters
set -e

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KARMADA_DIR="$HOME/.karmada" 
KARMADA_KUBECONFIG="$KARMADA_DIR/karmada-apiserver.config"
HOST_KUBECONFIG="$HOME/.kube/config"
HOST_IPADDRESS="${HOST_IPADDRESS:-}"
NODE_MEMORY_LIMIT="NOT SET"
TMP_CONFIG_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_CONFIG_DIR}"' EXIT
sleeper() { 
  local seconds=${1:-30}  # default 30 if not passed
  for i in $(seq $seconds -1 1); do
    printf "\r⏳ Waiting... %2d seconds remaining" $i
    sleep 1
  done
  printf "\r✅ Done waiting!                    \n"
}

resolve_host_ip() {
  if [[ -n "${HOST_IPADDRESS}" ]]; then
    return 0
  fi

  HOST_IPADDRESS=$(
    python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(("8.8.8.8", 80))
    print(s.getsockname()[0])
except Exception:
    pass
finally:
    s.close()
PY
  )

  if [[ -z "${HOST_IPADDRESS}" ]]; then
    echo "Unable to determine HOST_IPADDRESS automatically. Set HOST_IPADDRESS explicitly." >&2
    exit 1
  fi
}

render_kind_config() {
  # injects HOST_IPADDR into .yaml 
  local src=$1
  local dst=$2
  awk -v host_ip="${HOST_IPADDRESS}" '
    /^networking:/ {
      print $0
      print "  apiServerAddress: \"" host_ip "\""
      next
    }
    { print $0 }
  ' "${src}" >"${dst}"
}
create_cluster() {
  local name=$1
  local config=$2

  if kind get clusters 2>/dev/null | grep -qx "${name}"; then
    echo "Deleting existing cluster before rebuild: ${name}"
    kind delete cluster --name "${name}"
  fi

  render_kind_config "${config}" "${TMP_CONFIG_DIR}/${name}.yaml"

  echo "Creating kind cluster: ${name}"
  kind create cluster \
    --name "${name}" \
    --config "${TMP_CONFIG_DIR}/${name}.yaml"
}


echo "Cleaning up prior..."
${ROOT_DIR}/scripts/cleanup.sh
resolve_host_ip
echo "Using host API server address: ${HOST_IPADDRESS}"
echo "Target topology: 3 clusters / 12 kind node containers / ${NODE_MEMORY_LIMIT} mem per node"

echo "Spinning up KIND Clusters..."
create_cluster host-01 ${ROOT_DIR}/configs/karmada/host-config.yaml
create_cluster cluster-01 ${ROOT_DIR}/configs/karmada/worker01-config.yaml 
create_cluster cluster-02 ${ROOT_DIR}/configs/karmada/worker02-config.yaml 
echo "Spinning up KIND Worker Clusters 01 & 02..."

echo "==> Finished Cluster creation..."
kubectl get nodes
kubectl config get-contexts

echo "Waiting for Karmada API to be ready..."
sleeper 15

echo "Initializing Karmada on host-01..."
kubectl config use-context kind-host-01
karmadactl init \
    --karmada-data="$KARMADA_DIR" \
    --karmada-pki="$KARMADA_DIR/pki" \
    --karmada-apiserver-advertise-address=${HOST_IPADDRESS}

echo "Joining worker clusters to Karmada..."
karmadactl join cluster-01 \
  --kubeconfig=$HOME/.karmada/karmada-apiserver.config \
  --cluster-kubeconfig=$HOME/.kube/config \
  --cluster-context=kind-cluster-01

karmadactl join cluster-02 \
  --kubeconfig=$HOME/.karmada/karmada-apiserver.config \
  --cluster-kubeconfig=$HOME/.kube/config \
  --cluster-context=kind-cluster-02

echo "==> Verifying joined clusters..."
sleeper 15
kubectl --kubeconfig=$HOME/.karmada/karmada-apiserver.config get clusters

