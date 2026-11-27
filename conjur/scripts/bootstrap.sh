#!/usr/bin/env bash
# Create Conjur account, init CLI, load Ansible policy, persist host API key.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"
ACCOUNT="${CONJUR_ACCOUNT:-demo}"

echo "==> Waiting for Conjur..."
for _ in $(seq 1 30); do
  code="$(curl -sk -o /dev/null -w '%{http_code}' https://localhost:8443/ || true)"
  [[ "$code" == "200" ]] && break
  sleep 2
done
[[ "$(curl -sk -o /dev/null -w '%{http_code}' https://localhost:8443/ || true)" == "200" ]] \
  || { echo "Conjur not ready on :8443" >&2; exit 1; }

echo "==> Ensure account '${ACCOUNT}'"
set +e
podman exec conjur_server conjurctl account create "${ACCOUNT}" > admin_data 2>admin_data.err
create_rc=$?
set -e

ADMIN_API_KEY=""
if grep -qiE 'already|exists' admin_data.err admin_data 2>/dev/null; then
  echo "Account already exists; retrieving admin API key..."
  ADMIN_API_KEY="$(podman exec conjur_server conjurctl role retrieve-key "${ACCOUNT}:user:admin" | tr -d '\r\n[:space:]')"
elif [[ "${create_rc}" -eq 0 ]]; then
  ADMIN_API_KEY="$(
    python3 - <<'PY'
from pathlib import Path
import re
text = Path("admin_data").read_text(errors="ignore")
err = Path("admin_data.err").read_text(errors="ignore") if Path("admin_data.err").exists() else ""
blob = text + "\n" + err
m = re.search(r"API key for admin:\s*(\S+)", blob)
if not m:
    raise SystemExit("could not parse admin API key from account create output")
print(m.group(1))
PY
  )"
else
  echo "account create failed:" >&2
  cat admin_data.err >&2 || true
  cat admin_data >&2 || true
  exit 1
fi

[[ -n "${ADMIN_API_KEY}" ]] || { echo "empty admin API key" >&2; exit 1; }
printf '%s\n' "${ADMIN_API_KEY}" > admin_api_key

echo "==> Init Conjur CLI client"
podman exec conjur_client conjur init oss -u https://proxy -a "${ACCOUNT}" --self-signed >/dev/null 2>&1 \
  || podman exec conjur_client conjur init -u https://proxy -a "${ACCOUNT}" >/dev/null 2>&1 \
  || true

echo "==> Login admin"
podman exec conjur_client conjur logout >/dev/null 2>&1 || true
podman exec conjur_client conjur login -i admin -p "${ADMIN_API_KEY}" >/dev/null

echo "==> Load policy ansible-ssh.yml"
set +e
podman exec conjur_client conjur policy load -b root -f /policy/ansible-ssh.yml > policy_data 2>policy_data.err
load_rc=$?
if [[ "${load_rc}" -ne 0 ]]; then
  podman exec conjur_client conjur policy update -b root -f /policy/ansible-ssh.yml > policy_data 2>policy_data.err
  load_rc=$?
fi
set -e
if [[ "${load_rc}" -ne 0 ]]; then
  echo "policy load/update failed:" >&2
  cat policy_data.err >&2 || true
  cat policy_data >&2 || true
  exit 1
fi

HOST_KEY="$(jq -r '.created_roles["'"${ACCOUNT}"':host:ansible/control-node"].api_key // empty' policy_data 2>/dev/null || true)"
if [[ -z "${HOST_KEY}" || "${HOST_KEY}" == "null" ]]; then
  echo "Policy already present; retrieving host API key..."
  HOST_KEY="$(podman exec conjur_server conjurctl role retrieve-key "${ACCOUNT}:host:ansible/control-node" | tr -d '\r\n[:space:]')"
fi
[[ -n "${HOST_KEY}" ]] || { echo "empty host API key" >&2; exit 1; }
printf '%s\n' "${HOST_KEY}" > host_api_key

podman cp conjur_client:/home/cli/conjur-server.pem ./conjur-server.pem 2>/dev/null \
  || cp -f conf/tls/nginx.crt ./conjur-server.pem

echo "Bootstrap complete. Host API key → conjur/host_api_key"
