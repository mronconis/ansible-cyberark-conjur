#!/usr/bin/env bash
# Create a kind cluster and deploy AWX (Automation Controller open-source).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLUSTER_NAME="aap-cyberark-demo"
export PATH="/Applications/UTM.app/Contents/MacOS:${PATH}"
export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"

echo "==> Ensuring kind cluster '${CLUSTER_NAME}'"
if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --config "${ROOT}/kind-config.yaml"
else
  echo "Cluster already exists"
  kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

echo "==> Create namespace awx"
kubectl create namespace awx --dry-run=client -o yaml | kubectl apply -f -

echo "==> Deploy awx-operator + AWX instance (this can take several minutes)"
OPERATOR_VERSION="2.19.1"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

kubectl apply -f "https://raw.githubusercontent.com/ansible/awx-operator/${OPERATOR_VERSION}/config/crd/bases/awx.ansible.com_awxs.yaml" \
  --server-side 2>/dev/null || \
kubectl apply -f "https://raw.githubusercontent.com/ansible/awx-operator/${OPERATOR_VERSION}/config/crd/bases/awx.ansible.com_awxs.yaml"

cd "${TMP}"
cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=${OPERATOR_VERSION}
images:
  - name: quay.io/ansible/awx-operator
    newTag: ${OPERATOR_VERSION}
namespace: awx
EOF

kubectl apply -k .
kubectl apply -f "${ROOT}/awx.yaml"

# gcr.io/kubebuilder/kube-rbac-proxy:v0.15.0 is unpublished; use quay mirror
echo "==> Patching kube-rbac-proxy image (gcr.io mirror workaround)"
kubectl -n awx set image deployment/awx-operator-controller-manager \
  kube-rbac-proxy=quay.io/brancz/kube-rbac-proxy:v0.15.0 || true

echo "==> Waiting for awx-web to become Ready"
for i in $(seq 1 90); do
  ready="$(kubectl -n awx get pods -l app.kubernetes.io/name=awx-web \
    -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.ready}{"\n"}{end}{end}' 2>/dev/null || true)"
  if echo "${ready}" | grep -q . && ! echo "${ready}" | grep -qx 'false'; then
    if curl -fsS -o /dev/null "http://127.0.0.1:8088/api/v2/" 2>/dev/null; then
      echo "AWX API is ready"
      break
    fi
  fi
  echo "  waiting for awx-web / API... (${i}/90)"
  sleep 10
done

if ! curl -fsS -o /dev/null "http://127.0.0.1:8088/api/v2/"; then
  echo "ERROR: AWX API not reachable on http://127.0.0.1:8088" >&2
  kubectl -n awx get pods -o wide >&2 || true
  exit 1
fi

ADMIN_PASS="$(kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d)"
NODEPORT="$(kubectl -n awx get service awx-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo 30080)"

# Host/inventory writes enqueue dispatcher work; API-up is not enough.
echo "==> Waiting for a READY task instance (control plane capacity > 0)"
for i in $(seq 1 60); do
  cap="$(curl -fsS -u "admin:${ADMIN_PASS}" "http://127.0.0.1:8088/api/v2/ping/" 2>/dev/null \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(i.get("capacity",0) for i in d.get("instances",[])))' 2>/dev/null || echo 0)"
  if [[ "${cap}" =~ ^[0-9]+$ ]] && (( cap > 0 )); then
    echo "Task capacity ready (${cap})"
    break
  fi
  echo "  waiting for task capacity... (${i}/60)"
  sleep 5
done
cap="$(curl -fsS -u "admin:${ADMIN_PASS}" "http://127.0.0.1:8088/api/v2/ping/" 2>/dev/null \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(i.get("capacity",0) for i in d.get("instances",[])))' 2>/dev/null || echo 0)"
if ! [[ "${cap}" =~ ^[0-9]+$ ]] || (( cap <= 0 )); then
  echo "ERROR: No READY AWX task instances (capacity=${cap})" >&2
  kubectl -n awx get pods -o wide >&2 || true
  exit 1
fi

cat > "${ROOT}/.controller.env" <<EOF
CONTROLLER_HOST=http://127.0.0.1:8088
CONTROLLER_USERNAME=admin
CONTROLLER_PASSWORD=${ADMIN_PASS}
CONTROLLER_VERIFY_SSL=False
CONJUR_URL=https://host.containers.internal:8443
TARGET_HOST=host.containers.internal
EOF

echo "AWX UI: http://127.0.0.1:8088  (kind maps host 8088 → node ${NODEPORT})"
echo "Admin user: admin"
echo "Admin password: ${ADMIN_PASS}"
echo "Connection file: ${ROOT}/.controller.env"
